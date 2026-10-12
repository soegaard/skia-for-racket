#lang racket/base

(require json racket/file racket/list racket/runtime-path racket/string)

(provide tutorials routes tutorial-by-id tutorial-source-path repository-root tutorial-requirements)

(define-runtime-path catalog-path "catalog.json")
(define-runtime-path repository-root "../../..")
(define catalog (call-with-input-file catalog-path read-json))
(define tutorials (hash-ref catalog 'tutorials))
(define routes (hash-ref catalog 'routes))

(define (tutorial-by-id id)
  (or (for/first ([entry (in-list tutorials)]
                 #:when (equal? id (hash-ref entry 'id)))
        entry)
      (raise-arguments-error 'tutorial-by-id "unknown tutorial"
                             "name" id
                             "available" (map (lambda (row) (hash-ref row 'id)) tutorials))))

;; Paths in the catalog describe the copied tree, not arbitrary filesystem paths.
(define (tutorial-source-path relative [root repository-root])
  (unless (and (string? relative)
               (regexp-match? #px"^[a-zA-Z0-9_./-]+$" relative)
               (andmap (lambda (part) (not (member part '("" "." ".."))))
                       (string-split relative "/" #:trim? #f)))
    (raise-argument-error 'tutorial-source-path "safe relative example path" relative))
  (define parts (string-split relative "/"))
  (apply build-path root "scribblings"
         (if (equal? (car parts) "quick") parts (cons "tutorials" parts))))

(define (tutorial-requirements row)
  (string-join (hash-ref row 'requirements) " "))
