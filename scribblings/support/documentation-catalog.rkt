#lang racket/base

;; Shared, native-free metadata for the documentation collections.  The
;; tutorial titles, manual paths, and route memberships remain authoritative in
;; the existing tutorial catalog.

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

(struct documentation-collection (id label available? module-path output-directory color-key)
  #:transparent)

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

(define (documentation-collection-by-id id)
  (or (for/first ([entry (in-list documentation-collections)]
                  #:when (eq? id (documentation-collection-id entry)))
        entry)
      (raise-arguments-error 'documentation-collection-by-id
                             "unknown documentation collection"
                             "id" id)))

(define (available-documentation-collections)
  (filter documentation-collection-available? documentation-collections))

(define (tutorial-id entry)
  (hash-ref entry 'id))

(define (tutorial-output-directory id)
  ;; These names are the public manual identities registered in info.rkt.  The
  ;; catalog ID is deliberately used rather than inferring from the source
  ;; path, which keeps Quick's separate source location unremarkable here.
  (tutorial-by-id id)
  (string-append "skia-tutorial-" id))

(define (tutorial-shortcut-groups)
  ;; The index routes may repeat prerequisites.  The first route occurrence
  ;; owns a lesson in the shortcut panel, preserving catalog route order.
  (define seen (make-hash))
  (for/list ([route (in-list routes)]
             #:do [(define ids
                     (for/list ([id (in-list (hash-ref route 'lessons))]
                                #:unless (hash-ref seen id #f))
                       (hash-set! seen id #t)
                       id))]
             #:when (pair? ids))
    (cons (hash-ref route 'title) (map tutorial-by-id ids))))

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

(define (validate-documentation-catalog!)
  (validate-documentation-collections!)
  (define tutorial-ids (map tutorial-id tutorials))
  (unless (= (length tutorial-ids) (length (remove-duplicates tutorial-ids)))
    (error 'validate-documentation-catalog! "duplicate tutorial id"))
  (define route-ids (append-map (lambda (route) (hash-ref route 'lessons)) routes))
  (for ([id (in-list route-ids)])
    (unless (member id tutorial-ids)
      (error 'validate-documentation-catalog! "route has unknown tutorial id: ~e" id)))
  (for ([id (in-list tutorial-ids)])
    (unless (member id route-ids)
      (error 'validate-documentation-catalog! "tutorial is absent from all routes: ~e" id)))
  (void))

(validate-documentation-catalog!)

(module+ test
  (require rackunit)
  (check-equal? (map documentation-collection-id documentation-collections)
                '(reference guide tutorials))
  (check-equal? (map documentation-collection-id (available-documentation-collections))
                '(reference tutorials))
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
                '("Start with drawing"
                  "Text and printable documents"
                  "Effects and reusable drawings"
                  "Windows and interactive drawings"
                  "Pixels and color"
                  "Programmable paints"
                  "Constructed geometry"
                  "Sprite animation and games"))
  (define grouped-ids
    (append-map (lambda (group) (map tutorial-id (cdr group)))
                (tutorial-shortcut-groups)))
  (check-equal? (length grouped-ids) (length tutorials))
  (check-equal? (sort grouped-ids string<?) (sort (map tutorial-id tutorials) string<?)))
