#lang racket/base

;; Retention keys must match both Racket path conventions after the split.
(require rackunit racket/file racket/path racket/runtime-path syntax/modread json)
(define-runtime-path collection-root "..")
(module+ test
  (test-case "editable tutorial retention matches Unix and Windows traversal paths"
    ;; Evaluate the actual metadata expression with each path convention. Racket's
    ;; stripper keys retention by path equality, which does not normalize slashes.
    (define metadata
      (call-with-input-file (build-path collection-root "info.rkt")
        (lambda (in)
          (with-module-reading-parameterization (lambda () (read in))))))
    ;; Package creation can rewrite #lang info to a single module expression.
    (define (retention-expression form)
      (cond
        [(and (list? form) (>= (length form) 3) (equal? (car form) 'define)
              (equal? (cadr form) 'binary-keep-files))
         (caddr form)]
        [(list? form) (for/or ([part (in-list form)]) (retention-expression part))]
        [else #f]))
    (define expression
      (or (retention-expression metadata)
          (error 'retention "binary-keep-files definition missing")))
    (define catalogue
      (call-with-input-file
          (build-path collection-root "scribblings" "tutorials" "support" "catalog.json")
        read-json))
    (for ([convention '(unix windows)])
      (define (join . pieces)
        (apply build-path
               (for/list ([piece (in-list pieces)])
                 (bytes->path (string->bytes/utf-8 piece) convention))))
      (define namespace (make-base-namespace))
      (namespace-set-variable-value! 'build-path join #t namespace)
      (define retained (parameterize ([current-namespace namespace]) (eval expression)))
      (define keeps
        (for/hash ([path (in-list retained)])
          (values (if (path-for-some-system? path)
                      path
                      (bytes->path (string->bytes/utf-8 path) convention))
                  #t)))
      (for* ([tutorial (in-list (hash-ref catalogue 'tutorials))]
             [file (in-list (hash-ref tutorial 'files))])
        (define relative
          (string-append "scribblings/" (if (regexp-match? #rx"^quick/" file) "" "tutorials/")
                         file))
        (check-true (hash-ref keeps (apply join (regexp-split #rx"/" relative)) #f)
                    (format "~a: ~a" convention relative)))))
)
