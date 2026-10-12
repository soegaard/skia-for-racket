#lang racket/base

;; Reader-facing navigation and source access; no drawing or native initialization.
(require racket/list racket/string
         scribble/base scribble/core scribble/manual scribble/html-properties
         "catalog.rkt")

(provide tutorial-link tutorial-entry tutorial-next tutorial-sources tutorial-route
         command-text tutorial-index-link api-link)

(define (api-link)
  (hyperlink "https://github.com/soegaard/skia-for-racket/blob/main/docs/API.md"
             "API reference"))

(define (tutorial-link id)
  (define row (tutorial-by-id id))
  (elem #:style "skia-reader-navigation"
        (seclink "top" #:doc `(lib ,(string-append "skia/" (hash-ref row 'manual)))
                 (hash-ref row 'title))))

(define (tutorial-index-link [tag "top"] [label "Skia Tutorials"])
  (seclink tag #:doc '(lib "skia/scribblings/tutorials/index.scrbl") label))

;; Do not let Scribble turn the two ASCII hyphens of an option into an en dash.
(define (command-text text)
  (elem #:style "skia-command" (tt (literal text))))

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

(define (tutorial-next id)
  (define row (tutorial-by-id id))
  (list
   (apply itemlist
          (for/list ([next (in-list (hash-ref row 'next))])
            (define target (tutorial-by-id next))
            (item (tutorial-link next) ". " (hash-ref target 'goal))))
   (para #:style "skia-reader-next"
         "Return to " (tutorial-index-link) " to choose a different reading route.")))

(define (tutorial-route ids)
  (apply itemlist
         (for/list ([id (in-list ids)])
           (define row (tutorial-by-id id))
           (item (tutorial-link id) ". " (hash-ref row 'goal)))))

(define (source-link relative)
  (elem #:style (style "skia-reader-source-link"
                      (list (link-resource (tutorial-source-path relative))))
        (filepath relative)))

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
