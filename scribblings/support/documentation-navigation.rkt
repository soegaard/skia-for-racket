#lang racket/base

;; The navigation is rendered by Scribble, so links stay real document targets
;; in standalone, installed, and relocated documentation.  JavaScript only
;; enhances the already-rendered Tutorials shortcut disclosure.

(require racket/list
         racket/runtime-path
         (for-syntax racket/base)
         scribble/base
         scribble/core
         scribble/html-properties
         "../tutorials/support/catalog.rkt"
         "documentation-catalog.rkt")

(provide documentation-navigation-band
         tutorial-navigation-band
         include-reference-section
         decorate-reference-index)

(define-runtime-path navigation-css "skia-doc-nav.css")
(define-runtime-path navigation-js "skia-doc-nav.js")

(define (html-attributes pairs)
  (make-attributes pairs))

(define (navigation-element tag style-name pairs . content)
  (make-element
   (make-style style-name
               (list (make-alt-tag tag)
                     (html-attributes pairs)))
   content))

(define (navigation-shell-element style-name pairs . content)
  (make-element
   (make-style style-name
               (list (make-alt-tag "div")
                     (make-css-style-addition navigation-css)
                     (make-js-style-addition navigation-js)
                     (html-attributes pairs)))
   content))

(define (navigation-pretitle content)
  ;; A `pretitle` block is rendered before Scribble's generated heading.  The
  ;; explicit `div` tag keeps the navigation structurally valid while making
  ;; it the first document-specific element in the main column.
  (make-paragraph
   (make-style 'pretitle
               (list (make-alt-tag "div")
                     (html-attributes
                      (list (cons 'class "skia-doc-nav-pretitle")))))
   (list content)))

(define (styled-seclink collection label current #:all-tutorials? [all-tutorials? #f])
  (define entry (documentation-collection-by-id collection))
  (define plain-link
    (seclink "top"
             #:doc `(lib ,(documentation-collection-module-path entry))
             #:underline? #f
             label))
  (make-link-element
   (make-style
    (string-append "skia-doc-nav__collection-link skia-doc-nav__collection-link--"
                   (symbol->string collection))
    (if (or current all-tutorials?)
        (list (html-attributes
               (append (if current (list (cons 'aria-current current)) null)
                       (if all-tutorials?
                           (list (cons 'data-skia-doc-nav-all "tutorials"))
                           null))))
        null))
   (element-content plain-link)
   (link-element-tag plain-link)))

(define (tutorial-seclink entry [current #f])
  (define plain-link
    (seclink "top"
             #:doc `(lib ,(string-append "skia/" (hash-ref entry 'manual)))
             #:underline? #f
             (hash-ref entry 'title)))
  (make-link-element
   (make-style "skia-doc-nav__tutorial-link"
               (if current
                   (list (html-attributes (list (cons 'aria-current "page"))))
                   null))
   (element-content plain-link)
   (link-element-tag plain-link)))

(define (collection-current collection active index?)
  (and (eq? collection active) (if index? "page" "location")))

(define (collection-destination entry active index?)
  (define id (documentation-collection-id entry))
  (if (documentation-collection-available? entry)
      (styled-seclink id
                      (documentation-collection-label entry)
                      (collection-current id active index?))
      (navigation-element
       "span"
       (string-append "skia-doc-nav__collection-link skia-doc-nav__collection-link--"
                      (symbol->string id)
                      " skia-doc-nav__collection-link--unavailable")
       (list (cons 'aria-disabled "true"))
       (documentation-collection-label entry))))

(define (collection-links active index? tutorial-id)
  (apply navigation-element
         "div"
         "skia-doc-nav__collections"
         null
         (for/list ([entry (in-list documentation-collections)])
           (define id (documentation-collection-id entry))
           (apply navigation-element
                  "div"
                  (string-append "skia-doc-nav__collection skia-doc-nav__collection--"
                                 (symbol->string id))
                  null
                  (append (list (collection-destination entry active index?))
                          (if (eq? id 'tutorials)
                              (list (tutorial-panel tutorial-id))
                              null))))))

(define (tutorial-list lessons tutorial-id)
  (apply navigation-element
         "ul"
         "skia-doc-nav__tutorial-list"
         null
         (for/list ([lesson (in-list lessons)])
           (navigation-element
            "li"
            "skia-doc-nav__tutorial-item"
            null
            (tutorial-seclink lesson
                              (and tutorial-id
                                   (equal? tutorial-id (hash-ref lesson 'id))))))))

(define (tutorial-panel tutorial-id)
  (define all-tutorials
    (styled-seclink 'tutorials "All tutorials" #f #:all-tutorials? #t))
  (apply navigation-element
         "div"
         "skia-doc-nav__panel"
         (list (cons 'id "skia-doc-nav-tutorials")
               (cons 'data-skia-doc-nav-panel "tutorials"))
         (append
          (list (navigation-element "p" "skia-doc-nav__all" null all-tutorials))
          (append-map
           (lambda (group)
             (define heading (car group))
             (define lessons (cdr group))
             (list
              (navigation-element "p" "skia-doc-nav__group-heading" null heading)
              (tutorial-list lessons tutorial-id)))
           (tutorial-shortcut-groups)))))

(define (documentation-navigation-band active
                                       #:index? [index? #f]
                                       #:tutorial-id [tutorial-id #f])
  (unless (or (not active) (documentation-collection-by-id active))
    (raise-argument-error 'documentation-navigation-band
                          "documentation collection id or #f" active))
  (when (and tutorial-id (not (eq? active 'tutorials)))
    (raise-arguments-error 'documentation-navigation-band
                           "tutorial id only for Tutorials pages"
                           "active collection" active
                           "tutorial id" tutorial-id))
  (when tutorial-id
    ;; `tutorial-by-id` is intentionally called here, so bad call sites fail
    ;; while the document is built rather than producing a silently incomplete
    ;; shortcut panel.
    (tutorial-by-id tutorial-id))
  (define active-name (if active (symbol->string active) "landing"))
  (navigation-pretitle
   (navigation-shell-element
    (string-append "skia-doc-nav-shell skia-doc-nav-shell--" active-name)
    (list (cons 'data-skia-doc-section active-name)
          (cons 'data-skia-doc-tutorial (or tutorial-id "")))
    (navigation-element
     "nav"
     (string-append "skia-doc-nav skia-doc-nav--" active-name)
     (list (cons 'role "navigation")
           (cons 'aria-label "Skia documentation")
           (cons 'data-skia-doc-section active-name))
     (navigation-element
      "div"
      "skia-doc-nav__bar"
      null
      (collection-links active index? tutorial-id))))))

(define (tutorial-navigation-band tutorial-id)
  (documentation-navigation-band 'tutorials #:tutorial-id tutorial-id))

(define (reference-page-part? parent-is-toc? part)
  ;; Scribble's `multi-page` renderer gives a top-level `toc` group and its
  ;; direct title children their own files, and it also emits the index as its
  ;; own page.  Lower sections stay on the leaf chapter page, so decorating
  ;; them would duplicate the landmark.
  (or parent-is-toc?
      (member 'toc (style-properties (part-style part)))
      (eq? 'index (style-name (part-style part)))))

(define (decorate-reference-section document)
  (unless (part? document)
    (raise-argument-error 'include-reference-section "part?" document))
  (define (walk part parent-is-toc?)
    (define toc? (member 'toc (style-properties (part-style part))))
    (define own-page? (reference-page-part? parent-is-toc? part))
    (make-part
     (part-tag-prefix part)
     (part-tags part)
     (part-title-content part)
     (part-style part)
     (part-to-collect part)
     (if own-page?
         (cons (documentation-navigation-band 'reference)
               (part-blocks part))
         (part-blocks part))
     (for/list ([child (in-list (part-parts part))])
       (walk child toc?))))
  (walk document #f))

(define (decorate-reference-index document)
  ;; `index-section` belongs to the Reference root rather than to an included
  ;; group, so the include decorator never sees it.  Decorate its generated
  ;; part directly to preserve one landmark on doc-index.html as well.
  (unless (part? document)
    (raise-argument-error 'decorate-reference-index "part?" document))
  (make-part
   (part-tag-prefix document)
   (part-tags document)
   (part-title-content document)
   (part-style document)
   (part-to-collect document)
   (cons (documentation-navigation-band 'reference) (part-blocks document))
   (part-parts document)))

(define-syntax (include-reference-section stx)
  (syntax-case stx ()
    [(_ module-path)
     (with-syntax ([doc-from-module (datum->syntax #'module-path 'doc)])
       (unless (module-path? (syntax->datum #'module-path))
         (raise-syntax-error #f "not a module path" stx #'module-path))
       #'(begin
           (require (only-in module-path [doc-from-module doc]))
           (decorate-reference-section doc)))]))

(module+ test
  (require rackunit)
  (check-not-exn (lambda () (documentation-navigation-band 'reference)))
  (check-not-exn (lambda () (tutorial-navigation-band "quick")))
  (check-exn exn:fail:contract?
             (lambda () (documentation-navigation-band 'reference #:tutorial-id "quick"))))
