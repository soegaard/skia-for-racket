#lang racket/base

;;;
;;; Reference Runtime Inventory
;;;

;; Checks live public binding shapes and cross-reference targets against the documentation
;; inventory.
;; This acceptance tool connects source declarations, runtime exports, and generated manual links.

;;;
;;; Imports and Exports
;;;

;; Read native Scribble forms and inspect public bindings without creating native objects.
(require json racket/class racket/cmdline racket/file racket/list racket/path racket/runtime-path
         racket/string scribble/xref setup/xref syntax/modread
         (only-in scribble/base seclink)
         (only-in scribble/core link-element-tag)
         (for-label (prefix-in main: skia) (prefix-in color: skia/color)))

;; This independent submodule can be tested without running the command-line worker.
(module constant-contracts racket/base
  (provide constant-shape constant-value-valid?)


  ;;;
  ;;; Constant Contract Validation
  ;;;

  ; symbol-vector-contract : list?
  ;;   Represents the supported immutable-vector-of-symbols constant contract as a Racket datum.
  (define symbol-vector-contract '(and/c (vectorof symbol?) immutable?))

  ; symbol-vector-json : list?
  ;;   Represents the same constant contract using strings suitable for JSON evidence.
  (define symbol-vector-json '("and/c" ("vectorof" "symbol?") "immutable?"))


  ; constant-shape : any/c -> hash?
  ;;   Describes a simple predicate or the supported compound constant contract without evaluating
  ;;   it.
  (define (constant-shape contract)
    (define shape (hasheq 'kind "value" 'arguments '() 'value_kind "constant"))
    (cond
      [(symbol? contract) (hash-set shape 'value_predicate (symbol->string contract))]
      [(equal? contract symbol-vector-contract)
       (hash-set shape 'value_contract symbol-vector-json)]
      [else (error 'reference-runtime "unsupported compound constant contract: ~e" contract)]))


  ; constant-value-valid? : hash? module-path? any/c -> any/c
  ;;   Checks an exported constant using standard predicates or its module's predicate, rejecting
  ;;   unknown compound contracts.
  (define (constant-value-valid? spec module value)
    (define contract (hash-ref spec 'value_contract #f))
    (cond
      [contract
       (unless (equal? contract symbol-vector-json)
         (error 'reference-runtime "unsupported constant contract: ~e" contract))
       (and (vector? value) (immutable? value)
            (for/and ([element (in-vector value)]) (symbol? element)))]
      [else
       (define name (string->symbol (hash-ref spec 'value_predicate)))
       ;; Standard predicates belong to racket/base; public Skia submodules do
       ;; not have to re-export them to document their own list/string constants.
       (define predicate
         (case name
           [(list?) list?]
           [(string?) string?]
           [(vector?) vector?]
           [else (dynamic-require module name)]))
       (and (procedure? predicate) (predicate value))])))

(require (submod "." constant-contracts))


;;;
;;; Diagnostic Operations
;;;

; root : path?
;;   Locates .. relative to this module, independent of the invoking directory.
(define-runtime-path root "..")

; specs-file : (or/c path-string? #f)
;;   Holds the required source-checker JSON input selected on the command line.
(define specs-file #f)

; output-file : (or/c path-string? #f)
;;   Holds the required destination for runtime and cross-reference evidence.
(define output-file #f)

; xref-file : (or/c path-string? #f)
;;   Selects a fresh Scribble cross-reference file, mutually exclusive with installed documentation.
(define xref-file #f)

; tutorial-xref-files : (listof path-string?)
;;   Preserves the command-line order of tutorial cross-reference files added to the fresh build.
(define tutorial-xref-files '())

; installed? : boolean?
;;   Selects installed collection cross-references instead of a fresh build.
(define installed? #f)

; reference-directory : (or/c path-string? #f)
;;   Identifies the expected Reference HTML directory for containment and filename checks.
(define reference-directory #f)
(command-line
 #:once-each
 [("--specs") path "Source checker JSON" (set! specs-file path)]
 [("--output") path "Write runtime evidence JSON" (set! output-file path)]
 [("--xref-file") path "Read a fresh Scribble --info-out file" (set! xref-file path)]
 [("--installed") "Query installed documentation" (set! installed? #t)]
 [("--reference-dir") path "Expected skia-reference HTML directory"
                         (set! reference-directory path)]
 #:multi
 [("--tutorial-xref") path "Add fresh tutorial cross-reference information"
                         (set! tutorial-xref-files (append tutorial-xref-files (list path)))])


; need : any/c string? any/c ... -> void?
;;   Raises a Reference inventory failure with formatted context when a required condition is false.
(define (need value message . arguments)
  (unless value (apply error 'reference-runtime message arguments)))
(need (and specs-file output-file) "--specs and --output are required")
(need (not (and installed? xref-file)) "choose installed xref or an explicit xref file")
(need (or (null? tutorial-xref-files) (and xref-file (not installed?)))
      "--tutorial-xref requires a fresh --xref-file build")

; absolute : path-string? -> path?
;;   Resolves a path to a complete simplified filesystem path for checkout and build identity
;;   checks.
(define (absolute path) (simplify-path (path->complete-path path) #t))
(need (equal? (absolute (collection-file-path "main.rkt" "skia"))
              (absolute (build-path root "main.rkt")))
      "the skia collection must resolve to this checkout, not another installed copy")

; source-report : hash?
;;   Contains source declarations and manual-link expectations read from the checker JSON.
(define source-report (call-with-input-file specs-file read-json))

; specifications : (listof hash?)
;;   Lists the documented public binding specifications to compare with runtime exports.
(define specifications (hash-ref source-report 'definitions))

; declarations : hash?
;;   Maps binding-name strings to parsed documentation shapes; duplicate names are rejected.
(define declarations (make-hash))


; read-module : path-string? -> any/c
;;   Reads a module datum with its declared reader without instantiating the module.
(define (read-module path)
  (call-with-input-file path
    (lambda (in)
      (with-module-reading-parameterization
       (lambda () (syntax->datum (read-syntax path in)))))))


; record! : symbol? hash? -> void?
;;   Records one documented binding shape, rejecting nonliteral or duplicate names.
(define (record! name shape)
  (need (symbol? name) "expected a literal binding name")
  (define key (symbol->string name))
  (need (not (hash-has-key? declarations key)) "duplicate definition: ~a" key)
  (hash-set! declarations key shape))


; procedure-shape : list? -> hash?
;;   Converts a Scribble call specification into positional arity and keyword metadata, rejecting
;;   unsupported signatures.
(define (procedure-shape call)
  (define required 0)
  (define optional 0)
  (define keywords '())
  (define required-keywords '())
  (define arguments '())
  (define rest? #f)
  (for ([field (in-list (cdr call))])
    (cond
      [(memq field '(... ...+))
       (need (and (not rest?) (zero? optional) (pair? arguments)
                  (eq? (hash-ref (last arguments) 'keyword) 'null)
                  (not (hash-ref (last arguments) 'optional)))
             "unsupported rest/case signature")
       (set! rest? #t)
       (when (eq? field '...) (set! required (sub1 required)))
       (set! arguments
             (append (drop-right arguments 1)
                     (list (hash-set (last arguments) 'repeat
                                     (if (eq? field '...) "zero-or-more" "one-or-more")))))]
      [else
       (need (and (list? field) (pair? field)) "unsupported rest/case signature")
       (define kw? (keyword? (car field)))
       (need (or (not rest?) kw?) "unsupported rest/case signature after ellipsis")
       (need (member (length field) (if kw? '(3 4) '(2 3))) "invalid argument specification")
       (define default? (= (length field) (if kw? 4 3)))
       (define keyword (and kw? (keyword->string (car field))))
       (cond
         [kw?
          (need (not (member keyword keywords)) "duplicate keyword")
          (set! keywords (cons keyword keywords))
          (unless default? (set! required-keywords (cons keyword required-keywords)))]
         [default? (set! optional (add1 optional))]
         [else
          (need (zero? optional) "required argument after optional argument")
          (set! required (add1 required))])
       (set! arguments
             (append arguments
                     (list (hasheq 'name (symbol->string (list-ref field (if kw? 1 0)))
                                   'keyword (or keyword 'null) 'optional default?))))]))
  (hasheq 'kind "procedure" 'arguments arguments
          'arity_mask (number->string
                       (if rest? (- (arithmetic-shift 1 required))
                           (for/sum ([n (in-range required (+ required optional 1))])
                             (arithmetic-shift 1 n))))
          'allowed_keywords (sort keywords string<?)
          'required_keywords (sort required-keywords string<?)))


; record-structure! : list? -> void?
;;   Records constructor, predicate, descriptor, and accessor shapes for supported transparent
;;   structure declarations.
(define (record-structure! datum)
  (define struct-name (cadr datum))
  (define fields (caddr datum))
  (define-values (name inherited-fields)
    (cond
      [(symbol? struct-name) (values struct-name '())]
      [(equal? struct-name '(exn:fail:skia-dc:unsupported exn:fail:contract))
       (values 'exn:fail:skia-dc:unsupported
               '((message string?) (continuation-marks continuation-mark-set?)))]
      [else (error 'reference-runtime "unsupported structure name/supertype: ~e" struct-name)]))
  (need (and (list? fields) (eq? (list-ref datum 3) '#:transparent))
        "unsupported structure declaration")
  (need (andmap (lambda (field)
                 (and (list? field) (= (length field) 2) (symbol? (car field)))) fields)
        "unsupported structure field")
  (need (= (length fields) (length (remove-duplicates (map car fields))))
        "duplicate structure field")
  (need (or (null? (cddddr datum)) (not (keyword? (car (cddddr datum)))))
        "unsupported structure options after #:transparent")
  (define group (symbol->string name))
  (define predicate (string->symbol (string-append group "?")))
  (define (member! id shape role)
    (record! id (hash-set (hash-set shape 'definition_group group) 'structure_role role)))
  (member! name (procedure-shape (cons name (append inherited-fields fields))) "constructor")
  (member! (string->symbol (string-append "struct:" group))
           (hasheq 'kind "value" 'arguments '() 'value_kind "struct-type") "descriptor")
  (member! predicate (procedure-shape (list predicate '(v any/c))) "predicate")
  (for ([field (in-list fields)])
    (define accessor (string->symbol (string-append group "-" (symbol->string (car field)))))
    (member! accessor (procedure-shape (list accessor (list 'value predicate))) "accessor")))


; walk : any/c -> void?
;;   Collects documentation declarations while ignoring quoted and displayed example code.
(define (walk datum)
  (when (pair? datum)
    (case (car datum)
      [(quote quasiquote racketblock racketblock0 racketmod examples interaction) (void)]
      [(defstruct*) (record-structure! datum)]
      [(defproc) (record! (caadr datum) (procedure-shape (cadr datum)))]
      [(defclass)
       (record! (cadr datum) (hasheq 'kind "class" 'arguments '()))]
      [(definterface)
       (record! (cadr datum) (hasheq 'kind "interface" 'arguments '()))]
      [(defthing)
       (need (symbol? (cadr datum)) "unsupported constant declaration")
       (record! (cadr datum) (constant-shape (caddr datum)))]
      [(defform) (record! (caadr datum) (hasheq 'kind "syntax" 'arguments '()))]
      [(defparam)
       (record! (cadr datum)
                (hasheq 'kind "parameter" 'arguments '() 'arity_mask "3"
                        'allowed_keywords '() 'required_keywords '()))]
      [else (for-each walk datum)])))

(for ([chapter (in-list (hash-ref source-report 'chapters))])
  (walk (read-module (build-path root chapter))))
(need (= (hash-count declarations) (length specifications))
      "native reader and source checker disagree on the definition count")


; live-specifications : (listof hash?)
;;   Selects documented bindings whose runtime shapes can be checked in the normal worker.
(define live-specifications
  (filter (lambda (spec) (equal? (hash-ref spec 'runtime_check "live") "live"))
          specifications))

; deferred-runtime-specifications : (listof hash?)
;;   Separates bindings requiring specialized runtime checks from the live inventory.
(define deferred-runtime-specifications
  (filter (lambda (spec) (not (equal? (hash-ref spec 'runtime_check "live") "live")))
          specifications))

(for ([spec (in-list specifications)])
  (define name (hash-ref spec 'name))
  (define shape (hash-ref declarations name (lambda () #f)))
  (need shape "native Scribble reader did not find ~a" name)
  (for ([(field value) (in-hash shape)])
    (need (equal? value (hash-ref spec field)) "native reader mismatch: ~a / ~a" name field))
  (when (equal? (hash-ref spec 'runtime_check "live") "live")
    (unless (equal? (hash-ref spec 'kind) "syntax")
      (for ([module (in-list (hash-ref spec 'exports))])
        (define value (dynamic-require (string->symbol module) (string->symbol name)))
        (cond
          [(equal? (hash-ref spec 'kind) "value")
           (cond
             [(equal? (hash-ref spec 'value_kind #f) "struct-type")
              (need (struct-type? value)
                    "not a structure-type descriptor: ~a / ~a" module name)]
             [(equal? (hash-ref spec 'value_kind #f) "constant")
              (need (constant-value-valid? spec (string->symbol module) value)
                    "constant does not satisfy its declared contract: ~a / ~a" module name)]
             [else (error 'reference-runtime "unsupported value kind: ~a" name)])]
          [(equal? (hash-ref spec 'kind) "class")
           (need (class? value) "not a class: ~a / ~a" module name)]
          [(equal? (hash-ref spec 'kind) "interface")
           (need (interface? value) "not an interface: ~a / ~a" module name)]
          [else
         (need (procedure? value) "not a procedure: ~a / ~a" module name)
         (when (equal? (hash-ref spec 'kind) "parameter")
           (need (parameter? value) "not a parameter: ~a" name))
         (need (= (procedure-arity-mask value) (string->number (hash-ref spec 'arity_mask)))
               "live arity mismatch: ~a / ~a" module name)
         (define-values (required allowed) (procedure-keywords value))
         (need (and allowed
                    (equal? (map keyword->string required) (hash-ref spec 'required_keywords))
                    (equal? (map keyword->string allowed) (hash-ref spec 'allowed_keywords)))
               "live keyword mismatch: ~a / ~a" module name)])))))

(need (identifier-binding #'main:with-skia #f) "with-skia has no imported label binding")
(for ([pair (in-list (list (list #'main:color? #'color:color?)
                           (list #'main:color->argb #'color:color->argb)
                           (list #'main:rgba #'color:rgba)
                           (list #'main:struct:rgba #'color:struct:rgba)
                           (list #'main:rgba? #'color:rgba?)
                           (list #'main:rgba-red #'color:rgba-red)
                           (list #'main:rgba-green #'color:rgba-green)
                           (list #'main:rgba-blue #'color:rgba-blue)
                           (list #'main:rgba-alpha #'color:rgba-alpha)
                           (list #'main:rgb #'color:rgb)
                           (list #'main:color->rgba #'color:color->rgba)))])
  (need (free-label-identifier=? (car pair) (cadr pair))
        "declared color re-exports are not the same label binding"))

; alias-namespaces : hash?
;;   Caches module namespaces used to compare exported aliases without mixing binding scopes.
(define alias-namespaces (make-hash))
(for* ([spec (in-list live-specifications)]
       [module (in-list (hash-ref spec 'exports))]
       #:unless (equal? module (hash-ref spec 'canonical_module)))
  (define canonical (hash-ref spec 'canonical_module))
  (define namespace
    (hash-ref! alias-namespaces (list canonical module)
      (lambda ()
        (define ns (make-base-namespace))
        (parameterize ([current-namespace ns])
          (eval `(require (for-label
                           (prefix-in canonical: ,(string->symbol canonical))
                           (prefix-in alias: ,(string->symbol module))))))
        ns)))
  (define name (hash-ref spec 'name))
  (parameterize ([current-namespace namespace])
    (need (eval `(free-label-identifier=?
                  (quote-syntax ,(string->symbol (string-append "canonical:" name)))
                  (quote-syntax ,(string->symbol (string-append "alias:" name)))))
          "re-export label binding differs: ~a / ~a" module name)))

;; This exercises syntax, internal definitions and multiple values without native allocation.

; pure-namespace : namespace?
;;   Provides an isolated base namespace for checks that must remain independent of native
;;   execution.
(define pure-namespace (make-base-namespace))
(parameterize ([current-namespace pure-namespace])
  (namespace-require 'skia)
  (need (equal? (call-with-values
                (lambda () (eval '(with-skia () (define x 1) (values x 2)))) list)
                '(1 2))
        "with-skia empty-body syntax/result regression"))


; xref : (or/c xref? #f)
;;   Holds installed or merged fresh-build cross-references when link verification is enabled.
(define xref
  (cond [installed? (load-collections-xref)]
        [xref-file
         (load-xref (for/list ([path (in-list (cons xref-file tutorial-xref-files))])
                      (lambda () (call-with-input-file path read))))]
        [else #f]))

; seen-tags : hash?
;;   Tracks resolved definition tags so aliases cannot silently map to incompatible targets.
(define seen-tags (make-hash))

; targets : (listof hash?)
;;   Contains verified public-binding HTML paths and anchors within the intended Reference build.
(define targets
  (if xref
      (begin
        (need reference-directory "xref checks require --reference-dir")
        (for*/list ([spec (in-list specifications)]
                    [module (in-list (hash-ref spec 'exports))])
          (define name (hash-ref spec 'name))
          ;; Scribble records one target for a documented binding. A re-export
          ;; can share that binding without having its own raw xref key, so find
          ;; the target through any declared export. The free-label check above
          ;; establishes that these exports are the same public binding.
          (define tags
            (remove-duplicates
             (filter values
                     (for/list ([candidate
                                 (in-list
                                  (remove-duplicates
                                   (cons (hash-ref spec 'canonical_module)
                                         (hash-ref spec 'exports))))])
                       (xref-binding->definition-tag
                        xref
                        (list (string->symbol candidate) (string->symbol name))
                        0)))))
          (need (pair? tags) "missing definition target: ~a" name)
          (need (= (length tags) 1) "re-export has distinct definition targets: ~a" name)
          (define tag (car tags))
          (define group (hash-ref spec 'definition_group name))
          (define previous (hash-ref seen-tags tag #f))
          (need (or (not previous) (equal? previous group))
                "unrelated definitions resolved to one target: ~a and ~a" previous group)
          (hash-set! seen-tags tag group)
          (define-values (path anchor) (xref-tag->path+anchor xref tag))
          (need (and path anchor (file-exists? path)) "missing HTML target: ~a" name)
          (define relative (find-relative-path (absolute reference-directory) (absolute path)))
          (need (and (relative-path? relative) (not (member 'up (explode-path relative))))
                "~a resolved outside the new Reference: ~a" name path)
          (hasheq 'module module 'name name 'tag (format "~s" tag)
                  'definition_group group
                  'relative_path (regexp-replace* #rx"\\\\" (path->string relative) "/")
                  'anchor anchor)))
      '()))
;; Each declared export must map to the one documented entry for its binding.
(for ([spec (in-list specifications)] #:when xref)
  (define matches (filter (lambda (row) (equal? (hash-ref row 'name) (hash-ref spec 'name)))
                          targets))
  (need (= (length (remove-duplicates (map (lambda (row) (hash-ref row 'tag)) matches))) 1)
        "re-export has duplicate canonical targets: ~a" (hash-ref spec 'name)))

(for ([spec (in-list specifications)]
      #:when (and xref (equal? (hash-ref spec 'structure_role #f) "constructor")))
  (define group (hash-ref spec 'definition_group))
  (define members
    (filter (lambda (row) (equal? (hash-ref row 'definition_group) group)) targets))
  (define locations
    (remove-duplicates
     (map (lambda (row) (hash-ref row 'relative_path)) members)))
  (need (= (length locations) 1) "structure members resolve to different pages: ~a" group))

;; Construct the same document-aware links as the manual and ask Scribble for their tags.
;; The HTML checker checks these exact destinations, not hand-written fragment spellings.

; tutorial-targets : (listof hash?)
;;   Contains verified tutorial destinations from the merged cross-reference set.
(define tutorial-targets
  (if xref
      (for/list ([link (in-list (hash-ref source-report 'tutorial_links '()))])
        (define module `(lib ,(string-append "skia/" (hash-ref link 'manual))))
        (define tag
          (link-element-tag
           (seclink (hash-ref link 'tag) #:doc module (hash-ref link 'label))))
        (define-values (path anchor) (xref-tag->path+anchor xref tag))
        (need (and path (file-exists? path)) "unresolved tutorial: ~a" (hash-ref link 'manual))
        (define directory
          (simplify-path
           (build-path (absolute reference-directory) 'up (hash-ref link 'directory)) #t))
        (define relative (find-relative-path directory (absolute path)))
        (need (and (relative-path? relative) (not (member 'up (explode-path relative))))
              "tutorial resolved outside the intended build: ~a" path)
        (hash-set (hash-set link 'relative_path
                            (regexp-replace* #rx"\\\\" (path->string relative) "/"))
                  'anchor (or anchor "")))
      '()))


;; Resolve both current and compatibility tags through Scribble, not guessed anchors.

; section-targets : (listof hash?)
;;   Contains verified named Reference section targets with stable published filenames.
(define section-targets
  (if xref
      (for/list ([link (in-list (hash-ref source-report 'section_links '()))])
        (define tag
          (link-element-tag
           (seclink (hash-ref link 'tag)
                    #:doc '(lib "skia/scribblings/reference/reference.scrbl")
                    (hash-ref link 'label))))
        (define-values (path anchor) (xref-tag->path+anchor xref tag))
        (need (and path (file-exists? path))
              "unresolved Reference section: ~a" (hash-ref link 'tag))
        (define relative (find-relative-path (absolute reference-directory) (absolute path)))
        (define name (regexp-replace* #rx"\\\\" (path->string relative) "/"))
        (need (equal? name (hash-ref link 'filename))
              "published Reference filename changed: ~a" path)
        (hash-set (hash-set link 'relative_path name) 'anchor (or anchor "")))
      '()))

(call-with-output-file output-file #:exists 'error
  (lambda (out)
    (write-json (hasheq 'status "passed" 'racket_version (version)
                        'definitions (length specifications)
                        'binding_identity_checked (null? deferred-runtime-specifications)
                        'binding_identity_checked_definitions (length live-specifications)
                        'binding_identity_deferred_definitions
                        (length deferred-runtime-specifications)
                        'xref_checked (and xref #t) 'installed_xref installed?
                        'targets targets 'tutorial_targets tutorial-targets
                        'section_targets section-targets) out)
    (newline out)))
(printf "Reference runtime checks passed for ~a definitions; xref: ~a\n"
        (length specifications) (and xref #t))
