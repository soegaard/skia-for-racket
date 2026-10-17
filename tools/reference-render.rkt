#lang racket/base

;;;
;;; Reference Manual Renderer
;;;

;; Builds the Reference and related manuals with stable cross-manual tag prefixes.
;; This documentation entry point produces linked HTML from the Scribble sources.

;;;
;;; Imports and Exports
;;;

;; A standalone rendering must use the same document identity as raco setup.
;; --lib alone controls imports, not the root tag prefix or the "top" tag.
(require racket/file racket/list
         scribble/core scribble/render scribble/tag scribble/xref
         (prefix-in html: scribble/html-render))
(provide document-with-prefix)


;;;
;;; Diagnostic Operations
;;;

; document-with-prefix : part? module-path? -> part?
;   Adds a module-derived tag prefix and top tag so separately rendered manuals retain stable
;   cross-reference identities.
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

  ;;;
  ;;; Command-Line Run
  ;;;

  ; destination : (or/c path-string? #f)
  ;   Selects the generated HTML output directory.
  (define destination #f)

  ; name : (or/c string? #f)
  ;   Overrides the generated document's output name when supplied.
  (define name #f)

  ; info-out : (or/c path-string? #f)
  ;   Selects a file to receive freshly generated Scribble cross-reference data.
  (define info-out #f)

  ; info-in : (listof path-string?)
  ;   Accumulates companion cross-reference inputs in reverse command-line order.
  (define info-in '())

  ; main-xref? : boolean?
  ;   Enables installed documentation cross-references in addition to companion inputs.
  (define main-xref? #f)

  ; lib? : boolean?
  ;   Selects collection-based document loading for this renderer.
  (define lib? #f)

  ; multiple? : boolean?
  ;   Selects a multi-page manual instead of a single HTML page.
  (define multiple? #f)

  ; redirect : (or/c string? #f)
  ;   Optionally supplies the external cross-reference redirect URL.
  (define redirect #f)

  ; module-name : string?
  ;   Names the document module parsed with the renderer's command-line options.
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

  ; module : module-path?
  ;   Wraps the document name as a collection-based module path.
  (define module `(lib ,module-name))

  ; document : part?
  ;   Loads the document with an empty argument vector so it cannot consume renderer options.
  (define document
    (parameterize ([current-command-line-arguments #()])
      (dynamic-require module 'doc)))

  ; multi-mixin : class? -> class?
  ;   Combines Scribble's HTML renderer and multipage mixins.
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

  ;;;
  ;;; Test Entry Point
  ;;;

  ; target-module : module-path?
  ;   Identifies the synthetic destination module used by cross-reference regression checks.
  (define target-module '(lib "scribble/base.rkt"))

  ; target : part?
  ;   Provides a titled destination with a section tag but no top tag for prefix-normalization
  ;   checks.
  (define target
    (part #f '((part "heading")) '("Destination") plain '()
          (list (para "A real destination.")) '()))

  ; adjusted : part?
  ;   Holds the destination after its module prefix and top tag have been installed.
  (define adjusted (document-with-prefix target target-module))
  (check-equal? (hash-ref (part-tag-prefix adjusted) 'tag-prefix)
                (module-path-prefix->string target-module))
  (check-equal? (part-tags adjusted) '((part "top") (part "heading")))
  (check-equal? (part-tags (document-with-prefix adjusted target-module)) (part-tags adjusted))
  (check-equal? (part-blocks adjusted) (part-blocks target))
  (check-exn exn:fail?
             (lambda () (document-with-prefix adjusted '(lib "scribble/manual.rkt"))))

  ; configured : part?
  ;   Preserves an unrelated tag-prefix setting to check non-destructive prefix updates.
  (define configured
    (struct-copy part target [tag-prefix (hash 'example-setting "kept")]))
  (check-equal? (hash-ref (part-tag-prefix (document-with-prefix configured target-module))
                         'example-setting) "kept")

  ; link : element?
  ;   Links to the synthetic destination's top tag using its module identity.
  (define link (seclink "top" #:doc target-module "Destination"))

  ; origin : part?
  ;   Contains the synthetic source document whose link must resolve to the adjusted destination.
  (define origin
    (part #f '((part "origin")) '("Origin") plain '() (list (para link)) '()))

  ; directory : path?
  ;   Owns the temporary render directory used by the cross-reference regression test.
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
