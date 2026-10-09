#lang racket/base
;; API reflection only: never apply an exported procedure, read a parameter,
;; construct an exported class, or invoke a renderer to discover its signature.
(require racket/class racket/list racket/format)
(provide reflect-public-module public-value-shape gui-instantiated?)

(define (public-value-shape value)
  (cond
    [(procedure? value)
     (define-values (required allowed) (procedure-keywords value))
     (hasheq 'kind (if (parameter? value) "parameter" "procedure")
             ;; Decimal text preserves arbitrarily large (and negative) masks
             ;; through JSON readers that do not have exact integer arithmetic.
             'arity_mask (number->string (procedure-arity-mask value))
             'required_keywords (map keyword->string required)
             'allowed_keywords (if allowed (map keyword->string allowed) 'null))]
    [(class? value) (hasheq 'kind "class")]
    [(interface? value) (hasheq 'kind "interface")]
    [else (hasheq 'kind "value")]))

(define (gui-instantiated?)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (module->namespace 'racket/gui/base)
    #t))

(define (reflect-public-module module-path display-path)
  (dynamic-require module-path #f)
  (define-values (variables syntaxes) (module->exports module-path))
  (define (rows groups export-kind)
    (append-map
     (lambda (group)
       (define phase+space (car group))
       (for/list ([entry (in-list (cdr group))])
         (define name (car entry))
         (unless (symbol? name)
           (error 'public-api "unrecognized export descriptor in ~a" display-path))
         (define base
           (hasheq 'name (symbol->string name)
                   'phase (format "~s" phase+space)
                   'export_kind export-kind))
         (define shape
           (cond
             [(not (equal? phase+space 0)) (hasheq 'kind "phase-only")]
             [(equal? export-kind "value")
              ;; Missing/protected/uninitialized values are errors, not silently
              ;; converted to unknown signatures.
              (public-value-shape (dynamic-require module-path name))]
             [else
              ;; Rename transformers, contract-out bindings and structure
              ;; constructors may be listed as syntax but expose callable values.
              ;; Racket's documented dynamic-require evaluates an identifier use,
              ;; not an application. Genuine macros requiring syntax arguments
              ;; raise exn:fail:syntax?; retain their names, not invented arities.
              (with-handlers ([exn:fail:syntax? (lambda (_) (hasheq 'kind "syntax"))])
                (public-value-shape (dynamic-require module-path name)))]))
         (for/fold ([result base]) ([(key value) (in-hash shape)])
           (hash-set result key value))))
     groups))
  (define exports (append (rows variables "value") (rows syntaxes "syntax")))
  (define (key row)
    (list (hash-ref row 'phase) (hash-ref row 'name) (hash-ref row 'export_kind)))
  (define (key<? a b)
    (let loop ([xs (key a)] [ys (key b)])
      (cond [(null? xs) #f]
            [(string=? (car xs) (car ys)) (loop (cdr xs) (cdr ys))]
            [else (string<? (car xs) (car ys))])))
  (unless (= (length exports) (length (remove-duplicates (map key exports) equal?)))
    (error 'public-api "duplicate export descriptors in ~a" display-path))
  (hasheq 'path display-path 'exports (sort exports key<?)))
