#lang racket/base

;;;
;;; Documentation Catalog
;;;

;; Defines and validates documentation collections and their subject-based tutorial groups.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Shared, native-free metadata for the documentation collections.  The
;; tutorial titles, manual paths, and route memberships remain authoritative in
;; the existing tutorial catalog.

;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/string
         "../tutorials/support/catalog.rkt")

(provide (struct-out documentation-collection)
         documentation-collections
         documentation-collection-by-id
         available-documentation-collections
         tutorial-output-directory
         tutorial-shortcut-groups
         validate-documentation-collections!
         validate-documentation-catalog!)

;;;
;;; Documentation Collections and Tutorial Shortcuts
;;;

(struct documentation-collection (id label available? module-path output-directory color-key)
  #:transparent)
;; id: unique symbol identifying a documentation collection.
;; label: nonempty display string for the navigation band.
;; available?: boolean controlling whether the collection has a navigable destination.
;; module-path: Scribble module path string, or #f for an unavailable collection.
;; output-directory: stable manual output-directory string used by registration and checks.
;; color-key: symbol identifying the collection's CSS color family.
;; Field order matches constructor calls below; list order determines the visible band order.
;; Enabled collections require nonempty module-path and output-directory strings.

; documentation-collections : list?
;   Orders the Reference, Guide, and Tutorials records used by the navigation band.
(define documentation-collections
  (list
   (documentation-collection
    'reference "Reference" #t
    "skia/scribblings/reference/reference.scrbl" "skia-reference" 'reference)
   ;; Keep the disabled record here so enabling a real Guide is a single,
   ;; validated metadata change.  A disabled record deliberately has no target.
   (documentation-collection 'guide "Guide" #f #f "skia-guide" 'guide)
   (documentation-collection
    'tutorials "Tutorials" #t
    "skia/scribblings/tutorials/index.scrbl" "skia-tutorials" 'tutorials)))

; documentation-collection-by-id : symbol? -> documentation-collection?
;   Looks up a documentation collection and rejects an unknown ID.
(define (documentation-collection-by-id id)
  (or (for/first ([entry (in-list documentation-collections)]
                  #:when (eq? id (documentation-collection-id entry)))
        entry)
      (raise-arguments-error 'documentation-collection-by-id
                             "unknown documentation collection"
                             "id" id)))

; available-documentation-collections : -> (listof documentation-collection?)
;   Returns only collections that currently have enabled destinations.
(define (available-documentation-collections)
  (filter documentation-collection-available? documentation-collections))

; tutorial-id : hash? -> string?
;   Extracts the stable ID from a tutorial metadata record.
(define (tutorial-id entry)
  (hash-ref entry 'id))

; tutorial-output-directory : string? -> string?
;   Returns the registered output-directory name for a known tutorial.
(define (tutorial-output-directory id)
  ;; These names are the public manual identities registered in info.rkt.  The
  ;; catalog ID is deliberately used rather than inferring from the source
  ;; path, which keeps Quick's separate source location unremarkable here.
  (tutorial-by-id id)
  (string-append "skia-tutorial-" id))

; tutorial-shortcut-groups : -> list?
;   Returns subject-based shortcuts without deriving membership from reading routes.
(define (tutorial-shortcut-groups)
  ;; Categories describe subject browsing. Reading routes may overlap and do
  ;; not decide the navigation menu's order or membership.
  (tutorial-category-groups))

;;;
;;; Catalog Consistency Checks
;;;

; validate-documentation-collections! : [list?] -> void?
;   Checks unique collection IDs and destinations for every enabled collection.
(define (validate-documentation-collections! [collections documentation-collections])
  (define ids (map documentation-collection-id collections))
  (unless (= (length ids) (length (remove-duplicates ids)))
    (error 'validate-documentation-catalog! "duplicate documentation collection id"))
  (for ([entry (in-list collections)])
    (when (documentation-collection-available? entry)
      (unless (and (string? (documentation-collection-module-path entry))
                   (positive? (string-length (documentation-collection-module-path entry)))
                   (string? (documentation-collection-output-directory entry))
                   (positive? (string-length (documentation-collection-output-directory entry))))
        (error 'validate-documentation-catalog!
               "enabled collection has no destination: ~e" entry))))
  (void))

; validate-documentation-catalog! : -> void?
;   Validates the shared collection metadata and the referenced tutorial catalog.
(define (validate-documentation-catalog!)
  (validate-documentation-collections!)
  (validate-tutorial-catalog!)
  (define tutorial-ids (map tutorial-id tutorials))
  (unless (= (length tutorial-ids) (length (remove-duplicates tutorial-ids)))
    (error 'validate-documentation-catalog! "duplicate tutorial id"))
  (define route-ids (append-map (lambda (route) (hash-ref route 'lessons)) routes))
  (for ([id (in-list route-ids)])
    (unless (member id tutorial-ids)
      (error 'validate-documentation-catalog! "route has unknown tutorial id: ~e" id)))
  (void))

(validate-documentation-catalog!)

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)
  (check-equal? (map documentation-collection-id documentation-collections)
                '(reference guide tutorials))
  (check-equal? (map documentation-collection-id (available-documentation-collections))
                '(reference tutorials))

  ; synthetic-guide : documentation-collection?
  ;   Supplies an enabled Guide record solely to test destination validation.
  (define synthetic-guide
    (documentation-collection 'guide "Guide" #t
                              "skia/scribblings/guide/guide.scrbl" "skia-guide" 'guide))
  (check-not-exn
   (lambda ()
     (validate-documentation-collections!
      (list (first documentation-collections)
            synthetic-guide
            (last documentation-collections)))))
  (check-exn exn:fail?
             (lambda ()
               (validate-documentation-collections!
                (list (struct-copy documentation-collection synthetic-guide
                                   [module-path #f])))))
  (check-exn exn:fail?
             (lambda ()
               (validate-documentation-collections!
                (list (first documentation-collections)
                      (first documentation-collections)))))
  (check-equal? (map car (tutorial-shortcut-groups))
                '("Getting Started"
                  "Geometry"
                  "Paints and Effects"
                  "Images and Color"
                  "Text"
                  "Recording and Export"
                  "Windows and Interaction"
                  "Sprites and Games"))

  ; grouped-ids : list?
  ;   Collects tutorial IDs in subject-menu order for completeness and uniqueness checks.
  (define grouped-ids
    (append-map (lambda (group) (map tutorial-id (cdr group)))
                (tutorial-shortcut-groups)))
  (check-equal? (length grouped-ids) (length tutorials))
  (check-equal? (sort grouped-ids string<?) (sort (map tutorial-id tutorials) string<?)))
