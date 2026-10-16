#lang racket/base

;; A standalone rendering must use the same document identity as raco setup.
;; --lib alone controls imports, not the root tag prefix or the "top" tag.
(require racket/file racket/list
         scribble/core scribble/render scribble/tag scribble/xref
         (prefix-in html: scribble/html-render))
(provide document-with-prefix)

(define (document-with-prefix document module)
  (unless (part? document)
    (raise-argument-error 'document-with-prefix "part?" document))
  (define prefix (module-path-prefix->string module))
  (define old (part-tag-prefix document))
  (define old-prefix (if (hash? old) (hash-ref old 'tag-prefix #f) old))
  (when (and old-prefix (not (equal? old-prefix prefix)))
    (error 'document-with-prefix "conflicting document prefix for ~e: ~e" module old-prefix))
  (define tags (part-tags document))
  (struct-copy part document
    [tag-prefix (hash-set (if (hash? old) old (hash)) 'tag-prefix prefix)]
    [tags (if (member '(part "top") tags) tags (cons '(part "top") tags))]))

(module+ main
  (require racket/cmdline setup/xref)
  (define destination #f)
  (define name #f)
  (define info-out #f)
  (define info-in '())
  (define main-xref? #f)
  (define lib? #f)
  (define multiple? #f)
  (define redirect #f)
  (define module-name
    (command-line
     #:program "reference-render.rkt"
     #:once-any
     [("--html") "Write one HTML page" (set! multiple? #f)]
     [("--htmls") "Write a multi-page manual" (set! multiple? #t)]
     #:once-each
     [("--lib") "Use a collection-based document path" (set! lib? #t)]
     [("--dest") path "Output directory" (set! destination path)]
     [("--dest-name") value "Output name" (set! name value)]
     [("--info-out") path "Write fresh cross-reference information" (set! info-out path)]
     [("--redirect-main") url "Public URL for Racket documentation" (set! redirect url)]
     [("+m") "Load installed documentation cross-references" (set! main-xref? #t)]
     #:multi
     [("++info-in") path "Load companion cross-references" (set! info-in (cons path info-in))]
     #:args (module) module))
  (unless (and lib? destination name)
    (raise-user-error 'reference-render "--lib, --dest, and --dest-name are required"))
  (define module `(lib ,module-name))
  (define document
    (parameterize ([current-command-line-arguments #()])
      (dynamic-require module 'doc)))
  (define (multi-mixin %) (html:render-multi-mixin (html:render-mixin %)))
  (render (list (document-with-prefix document module)) (list name)
          #:dest-dir destination
          #:render-mixin (if multiple? multi-mixin html:render-mixin)
          #:redirect-main redirect
          #:xrefs (if main-xref? (list (load-collections-xref)) '())
          #:info-in-files (reverse info-in)
          #:info-out-file info-out
          #:quiet? #f))

(module+ test
  ;; These tests use real Scribble but no Skia, native library, GUI, or GPU.
  (require rackunit (only-in scribble/base para seclink))
  (define target-module '(lib "scribble/base.rkt"))
  (define target
    (part #f '((part "heading")) '("Destination") plain '()
          (list (para "A real destination.")) '()))
  (define adjusted (document-with-prefix target target-module))
  (check-equal? (hash-ref (part-tag-prefix adjusted) 'tag-prefix)
                (module-path-prefix->string target-module))
  (check-equal? (part-tags adjusted) '((part "top") (part "heading")))
  (check-equal? (part-tags (document-with-prefix adjusted target-module)) (part-tags adjusted))
  (check-equal? (part-blocks adjusted) (part-blocks target))
  (check-exn exn:fail?
             (lambda () (document-with-prefix adjusted '(lib "scribble/manual.rkt"))))
  (define configured
    (struct-copy part target [tag-prefix (hash 'example-setting "kept")]))
  (check-equal? (hash-ref (part-tag-prefix (document-with-prefix configured target-module))
                         'example-setting) "kept")
  (define link (seclink "top" #:doc target-module "Destination"))
  (define origin
    (part #f '((part "origin")) '("Origin") plain '() (list (para link)) '()))
  (define directory (make-temporary-file "reference-prefix-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define info (build-path directory "test.sxref"))
      ;; Reproduce the old failure before checking the corrected case.
      (render (list origin target) '("origin" "target") #:dest-dir directory
              #:info-out-file info #:quiet? #t)
      (define (load-info)
        (load-xref (list (lambda () (call-with-input-file info read)))))
      (define-values (missing _missing-anchor)
        (xref-tag->path+anchor (load-info) (link-element-tag link)))
      (check-false missing)
      (render (list origin adjusted) '("origin" "target") #:dest-dir directory
              #:info-out-file info #:quiet? #t)
      (define-values (path anchor)
        (xref-tag->path+anchor (load-info) (link-element-tag link)))
      (check-not-false path)
      (check-true (and path (file-exists? path)))
      ;; Scribble represents a destination at the root of its rendered page
      ;; with no fragment.  A non-root destination has a string fragment.
      (check-true (or (not anchor) (string? anchor)))
      (define origin-html (file->string (build-path directory "origin.html")))
      (check-true (regexp-match? #rx"href=\"[^\"]*target\\.html(?:#[^\"]*)?\""
                                 origin-html))
      (check-false (regexp-match? #rx"class=\"[^\"]*badlink" origin-html)))
    (lambda () (delete-directory/files directory))))
