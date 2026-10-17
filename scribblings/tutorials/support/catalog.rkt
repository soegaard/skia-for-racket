#lang racket/base

;;;
;;; Catalog
;;;

;; Loads and validates tutorial metadata, subject categories, and separate reading routes.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;;;
;;; Imports and Exports
;;;

(require json racket/file racket/list racket/runtime-path racket/string)

(provide catalog
         tutorials categories routes
         tutorial-by-id tutorial-category-by-id tutorial-category-groups
         tutorial-source-path repository-root tutorial-requirements
         validate-tutorial-catalog!)

;;;
;;; Documentation Data and Helpers
;;;

; catalog-path : path?
;;   Locates catalog path relative to this module rather than the current directory.
(define-runtime-path catalog-path "catalog.json")
; repository-root : path?
;;   Locates repository root relative to this module rather than the current directory.
(define-runtime-path repository-root "../../..")
; catalog : hash?
;;   Loads the authoritative tutorial metadata without initializing native drawing.
(define catalog (call-with-input-file catalog-path read-json))
; tutorials : list?
;;   Retains the tutorial records used for titles, sources, requirements, and links.
(define tutorials (hash-ref catalog 'tutorials))
; categories : list?
;;   Defines subject grouping and order independently of suggested reading routes.
(define categories (hash-ref catalog 'categories))
; routes : list?
;;   Defines optional ordered reading sequences, which may share tutorials.
(define routes (hash-ref catalog 'routes))

; nonempty-string? : any/c -> boolean?
;;   Checks that a metadata field is a nonempty string.
(define (nonempty-string? value)
  (and (string? value) (positive? (string-length value))))

; validate-tutorial-catalog! : [hash?] -> void?
;;   Checks schema, unique IDs, complete subject membership, and valid reading routes.
(define (validate-tutorial-catalog! [catalog* catalog])
  (unless (equal? (hash-ref catalog* 'schema_version #f) 2)
    (error 'validate-tutorial-catalog! "expected tutorial catalog schema version 2"))
  (define tutorials* (hash-ref catalog* 'tutorials))
  (define categories* (hash-ref catalog* 'categories))
  (define routes* (hash-ref catalog* 'routes))
  (define tutorial-ids
    (for/list ([entry (in-list tutorials*)])
      (define id (hash-ref entry 'id #f))
      (unless (nonempty-string? id)
        (error 'validate-tutorial-catalog! "tutorial has no id: ~e" entry))
      (unless (nonempty-string? (hash-ref entry 'menu_title #f))
        (error 'validate-tutorial-catalog! "tutorial has no menu title: ~e" id))
      id))
  (unless (= (length tutorial-ids) (length (remove-duplicates tutorial-ids)))
    (error 'validate-tutorial-catalog! "duplicate tutorial id"))
  (define category-ids
    (for/list ([category (in-list categories*)])
      (define id (hash-ref category 'id #f))
      (unless (nonempty-string? id)
        (error 'validate-tutorial-catalog! "category has no id: ~e" category))
      (unless (nonempty-string? (hash-ref category 'title #f))
        (error 'validate-tutorial-catalog! "category has no title: ~e" id))
      (define lessons (hash-ref category 'lessons #f))
      (unless (and (list? lessons) (pair? lessons))
        (error 'validate-tutorial-catalog! "category has no lessons: ~e" id))
      id))
  (unless (= (length category-ids) (length (remove-duplicates category-ids)))
    (error 'validate-tutorial-catalog! "duplicate tutorial category id"))
  (define categorized-ids
    (append-map (lambda (category) (hash-ref category 'lessons)) categories*))
  (for ([id (in-list categorized-ids)])
    (unless (member id tutorial-ids)
      (error 'validate-tutorial-catalog! "category has unknown tutorial id: ~e" id)))
  (unless (= (length categorized-ids) (length (remove-duplicates categorized-ids)))
    (error 'validate-tutorial-catalog! "tutorial belongs to more than one category"))
  (unless (and (= (length categorized-ids) (length tutorial-ids))
               (andmap (lambda (id) (member id categorized-ids)) tutorial-ids))
    (error 'validate-tutorial-catalog! "tutorial is absent from all categories"))
  (for ([route (in-list routes*)])
    (define lessons (hash-ref route 'lessons #f))
    (unless (and (list? lessons) (pair? lessons))
      (error 'validate-tutorial-catalog! "route has no lessons: ~e" route))
    (for ([id (in-list lessons)])
      (unless (member id tutorial-ids)
        (error 'validate-tutorial-catalog! "route has unknown tutorial id: ~e" id))))
  (void))

(validate-tutorial-catalog!)

; tutorial-by-id : string? -> hash?
;;   Looks up one tutorial and raises an error for an unknown catalog ID.
(define (tutorial-by-id id)
  (or (for/first ([entry (in-list tutorials)]
                  #:when (equal? id (hash-ref entry 'id)))
        entry)
      (raise-arguments-error 'tutorial-by-id "unknown tutorial"
                             "name" id
                             "available" (map (lambda (row) (hash-ref row 'id)) tutorials))))

; tutorial-category-by-id : string? -> hash?
;;   Looks up one subject category and raises an error for an unknown ID.
(define (tutorial-category-by-id id)
  (or (for/first ([category (in-list categories)]
                  #:when (equal? id (hash-ref category 'id)))
        category)
      (raise-arguments-error 'tutorial-category-by-id "unknown tutorial category"
                             "id" id
                             "available" (map (lambda (row) (hash-ref row 'id)) categories))))

; tutorial-category-groups : -> list?
;;   Returns subject headings paired with tutorial records in catalog order.
(define (tutorial-category-groups)
  (for/list ([category (in-list categories)])
    (cons (hash-ref category 'title)
          (map tutorial-by-id (hash-ref category 'lessons)))))

;; Paths in the catalog describe the copied tree, not arbitrary filesystem paths.
; tutorial-source-path : string? [path-string?] -> path?
;;   Resolves a validated relative example path within the source tree.
(define (tutorial-source-path relative [root repository-root])
  (unless (and (string? relative)
               (regexp-match? #px"^[a-zA-Z0-9_./-]+$" relative)
               (andmap (lambda (part) (not (member part '("" "." ".."))))
                       (string-split relative "/" #:trim? #f)))
    (raise-argument-error 'tutorial-source-path "safe relative example path" relative))
  (define parts (string-split relative "/"))
  (apply build-path root "scribblings"
         (if (equal? (car parts) "quick") parts (cons "tutorials" parts))))

; tutorial-requirements : hash? -> string?
;;   Joins a tutorial's prerequisite environment descriptions into reader-facing prose.
(define (tutorial-requirements row)
  (string-join (hash-ref row 'requirements) " "))

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)
  (check-equal? (hash-ref catalog 'schema_version) 2)
  (check-equal? (map (lambda (category) (hash-ref category 'title)) categories)
                '("Getting Started"
                  "Geometry"
                  "Paints and Effects"
                  "Images and Color"
                  "Text"
                  "Recording and Export"
                  "Windows and Interaction"
                  "Sprites and Games"))
  (check-equal? (map car (tutorial-category-groups))
                (map (lambda (category) (hash-ref category 'title)) categories))
  (check-exn exn:fail?
             (lambda ()
               (validate-tutorial-catalog!
                (hash-set catalog 'schema_version 1))))
  (check-equal? (tutorial-source-path "quick/moonlight.rkt")
                (build-path repository-root "scribblings" "quick" "moonlight.rkt")))
