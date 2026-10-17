#lang racket/base

;; Generate the neutral Pages landing page from the same catalog used by the
;; Scribble component.  This keeps its available collections and 22 tutorial
;; shortcuts synchronized without asking a browser to fetch runtime metadata.

(require racket/cmdline
         racket/file
         racket/format
         racket/list
         racket/runtime-path
         racket/string
         "../scribblings/support/documentation-catalog.rkt")

(define-runtime-path landing-template "../scribblings/tutorials/pages-index.html")
(define template-marker "<!-- skia-documentation-navigation -->")

(define output #f)
(command-line
 #:program "render-documentation-landing.rkt"
 #:once-each
 [("--output") path "write the landing page to this path" (set! output path)])
(unless output
  (raise-user-error 'render-documentation-landing.rkt "--output is required"))

(define html-replacements
  (list (cons "&" "&amp;")
        (cons "<" "&lt;")
        (cons ">" "&gt;")
        (cons "\"" "&quot;")
        (cons "'" "&#39;")))

(define (escape-html value)
  (for/fold ([result (~a value)]) ([replacement (in-list html-replacements)])
    (string-replace result (car replacement) (cdr replacement))))

(define (collection-link entry)
  (define id (documentation-collection-id entry))
  (define label (escape-html (documentation-collection-label entry)))
  (define destination
    (if (documentation-collection-available? entry)
        (format "<a class=\"skia-doc-nav__collection-link skia-doc-nav__collection-link--~a\" href=\"~a/index.html\">~a</a>"
                id
                (documentation-collection-output-directory entry)
                label)
        (format "<span class=\"skia-doc-nav__collection-link skia-doc-nav__collection-link--~a skia-doc-nav__collection-link--unavailable\" aria-disabled=\"true\">~a</span>"
                id
                label)))
  (string-append
   (format "<div class=\"skia-doc-nav__collection skia-doc-nav__collection--~a\">\n" id)
   destination
   (if (eq? id 'tutorials) (tutorial-panel-html) "")
   "</div>"))

(define (tutorial-link entry)
  (format "<li><a class=\"skia-doc-nav__tutorial-link\" href=\"~a/index.html\">~a</a></li>"
          (tutorial-output-directory (hash-ref entry 'id))
          (escape-html (hash-ref entry 'menu_title))))

(define (tutorial-panel-html)
  (string-append
   "<div class=\"skia-doc-nav__panel\" id=\"skia-doc-nav-tutorials\" data-skia-doc-nav-panel=\"tutorials\">\n"
   "<p class=\"skia-doc-nav__all\"><a class=\"skia-doc-nav__collection-link skia-doc-nav__collection-link--tutorials\" data-skia-doc-nav-all=\"tutorials\" href=\"skia-tutorials/index.html\">All tutorials</a></p>\n"
   "<div class=\"skia-doc-nav__tutorial-groups\">\n"
   (string-join
    (for/list ([group (in-list (tutorial-shortcut-groups))])
      (string-append
       "<div class=\"skia-doc-nav__tutorial-group\">\n"
       "<p class=\"skia-doc-nav__group-heading\">" (escape-html (car group)) "</p>\n"
       "<ul class=\"skia-doc-nav__tutorial-list\">\n"
       (string-join (map tutorial-link (cdr group)) "\n")
       "</ul>\n</div>"))
    "\n")
   "\n</div>\n"
   "</div>"))

(define (navigation-html)
  (string-append
   "<div class=\"skia-doc-nav-shell skia-doc-nav-shell--landing\" data-skia-doc-section=\"landing\">\n"
   "<nav class=\"skia-doc-nav skia-doc-nav--landing\" role=\"navigation\" aria-label=\"Skia documentation\" data-skia-doc-section=\"landing\">\n"
   "<div class=\"skia-doc-nav__bar\"><div class=\"skia-doc-nav__collections\">\n"
   (string-join (map collection-link documentation-collections) "\n")
   "</div></div></nav></div>"))

(define template (file->string landing-template))
(unless (= (length (regexp-match* (regexp (regexp-quote template-marker)) template)) 1)
  (raise-user-error 'render-documentation-landing.rkt
                    "landing template must contain exactly one navigation marker"))
(define page (string-replace template template-marker (navigation-html)))

(make-parent-directory* output)
(call-with-output-file output
  (lambda (out) (display page out))
  #:exists 'replace)
