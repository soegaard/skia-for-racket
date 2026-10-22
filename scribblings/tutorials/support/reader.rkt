#lang racket/base

;;;
;;; Reader
;;;

;; Builds tutorial navigation, prerequisites, source links, and running instructions.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Reader-facing navigation and source access; no drawing or native initialization.

;;;
;;; Imports and Exports
;;;

(require racket/list racket/string
         scribble/base scribble/core scribble/manual scribble/html-properties
         "catalog.rkt"
         "../../support/documentation-navigation.rkt"
         "../../support/paragraph-feedback.rkt")

(provide tutorial-link tutorial-entry tutorial-next tutorial-sources tutorial-route tutorial-category
         command-text tutorial-index-link api-link tutorial-navigation tutorial-feedback-style)

;; tutorial-feedback-style : -> style?
;; Supplies the shared GitHub paragraph-feedback controls for each tutorial manual.
(define (tutorial-feedback-style)
  (skia-feedback-style))

;;;
;;; Documentation Navigation Links
;;;

; tutorial-navigation : string? #:index? [boolean?] -> paragraph?
;   Builds the tutorial collection band with the current page's identity.
(define (tutorial-navigation id #:index? [index? #f])
  (documentation-navigation-band 'tutorials #:index? index? #:tutorial-id id))

; api-link : -> element?
;   Links to the project's API overview.
(define (api-link)
  (hyperlink "https://github.com/soegaard/skia-for-racket/blob/main/docs/API.md"
             "API reference"))

; tutorial-link : string? -> element?
;   Links to a tutorial using its canonical catalog title.
(define (tutorial-link id)
  (define row (tutorial-by-id id))
  (elem #:style "skia-reader-navigation"
        (seclink "top" #:doc `(lib ,(string-append "skia/" (hash-ref row 'manual)))
                 (hash-ref row 'title))))

; tutorial-index-link : [any/c] [any/c] -> element?
;   Links to a selected section of the tutorial index.
(define (tutorial-index-link [tag "top"] [label "Skia Tutorials"])
  (seclink tag #:doc '(lib "skia/scribblings/tutorials/index.scrbl") label))

;;;
;;; Tutorial Entries and Next Steps
;;;

;; Do not let Scribble turn the two ASCII hyphens of an option into an en dash.


; command-text : string? -> element?
;   Keeps command-line punctuation literal in rendered documentation.
(define (command-text text)
  (elem #:style "skia-command" (tt (literal text))))

; tutorial-entry : string? -> list?
;   Builds prerequisites, environment requirements, and example-running instructions.
(define (tutorial-entry id)
  (define row (tutorial-by-id id))
  (define prerequisites (hash-ref row 'prerequisites))
  (list
   (para #:style "skia-reader-prerequisites"
         (bold "Before you begin. ")
         (if (null? prerequisites)
             "Know how to define values and functions and require modules in Racket."
             (append (list "Use the drawing concepts from ")
                     (add-between (map tutorial-link prerequisites) "; ")
                     (list ". Read only the concepts you have not used before."))))
   (para (tutorial-requirements row))
   (para (bold "Run the complete example. ")
         "Use the installed-package copier from any writable directory:")
   (verbatim (format "raco skia-examples ~a my-~a\ncd my-~a\n~a"
                     id id id (car (hash-ref row 'commands))))
   (para #:style "skia-reader-navigation"
         "Jump to " (seclink "example-source" "Complete example") ", "
         (seclink "try-it" "Try it") ", or " (seclink "next-steps" "Next steps") ". "
         "See " (tutorial-index-link "running-examples" "Running the examples")
         " for installation and copying instructions.")))

; tutorial-next : string? -> list?
;   Builds suggested next steps without changing subject-category membership.
(define (tutorial-next id)
  (define row (tutorial-by-id id))
  (list
   (apply itemlist
          (for/list ([next (in-list (hash-ref row 'next))])
            (define target (tutorial-by-id next))
            (item (tutorial-link next) ". " (hash-ref target 'goal))))
   (para #:style "skia-reader-next"
         "Return to " (tutorial-index-link)
         " to browse all tutorials or choose a suggested reading route.")))

;;;
;;; Subject Categories and Reading Routes
;;;

; tutorial-list : list? -> itemization?
;   Builds the ordered tutorial links from the supplied catalog records.
(define (tutorial-list rows)
  (apply itemlist
         (for/list ([row (in-list rows)])
           (define id (hash-ref row 'id))
           (item (tutorial-link id) ". " (hash-ref row 'goal)))))

; tutorial-route : list? -> itemization?
;   Builds the supplied reading sequence in its explicitly requested order.
(define (tutorial-route ids)
  (tutorial-list (map tutorial-by-id ids)))

; tutorial-category : string? -> itemization?
;   Builds a subject listing from the category's authoritative tutorial IDs.
(define (tutorial-category id)
  (define category (tutorial-category-by-id id))
  (tutorial-list (map tutorial-by-id (hash-ref category 'lessons))))

;;;
;;; Downloadable Sources
;;;

; source-link : string? -> element?
;   Links to a downloadable example source while displaying its relative path.
(define (source-link relative)
  (elem #:style (style "skia-reader-source-link"
                      (list (link-resource (tutorial-source-path relative))))
        (filepath relative)))

; tutorial-sources : string? -> list?
;   Lists the complete example source set and its copy-and-run commands.
(define (tutorial-sources id)
  (define row (tutorial-by-id id))
  (define directory (string-append "my-" id))
  (list
   (para #:style "skia-reader-sources"
         "Copy the complete source set from your installed Skia package into a new directory:")
   (verbatim (format "raco skia-examples ~a ~a\ncd ~a\n~a"
                     id directory directory (car (hash-ref row 'commands))))
   (para "The copier refuses to replace an existing directory. It includes the files below "
         "and preserves their relative paths. The links let you inspect individual files; "
         "keep their displayed directory names when saving them manually.")
   (apply itemlist (map (lambda (relative) (item (source-link relative)))
                        (hash-ref row 'files)))
   (para "These commands run from the copied directory. Select only the backend "
         "available on your machine:")
   (verbatim (string-join (hash-ref row 'commands) "\n"))
   (para "Skia must remain installed. Native libraries and system fonts are not copied. "
         "For a checkout, see " (tutorial-index-link "running-examples" "Running the examples")
         ". Return to " (seclink "try-it" "Try it") " or "
         (seclink "next-steps" "Next steps") ".")))
