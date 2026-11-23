#lang racket/base

;; Rendering integration belongs to documentation; core file/convertible and
;; pict conversions remain in skia-lib/tests/convertible-native-test.rkt.
(require rackunit racket/file racket/path racket/runtime-path skia
         (prefix-in html: scribble/html-render)
         (prefix-in latex: scribble/latex-render) scribble/render)

; all-files : path-string? -> (listof path?)
;   Lists output files recursively, excluding directories.
(define (all-files directory)
  (find-files (lambda (path) (not (directory-exists? path))) directory))


; has-extension? : path-string? regexp? -> boolean?
;   Checks whether Scribble emitted any file matching the requested output suffix.
(define (has-extension? directory pattern)
  (for/or ([path (in-list (all-files directory))])
    (regexp-match? pattern (path->string path))))


; fixture-directory : path?
;   Locates . relative to this module, independent of the invoking directory.
(define-runtime-path fixture-directory ".")

; fixture-path : path-string? -> path?
;   Resolves a Scribble conversion fixture beside this test module.
(define (fixture-path name) (build-path fixture-directory name))


; render-fixture : module-path? procedure? string? procedure? -> any
;   Renders a fixture in a temporary directory, checks its artifacts, and removes them afterward.
(define (render-fixture file renderer name check)
  (define directory (make-temporary-file "skia-convertible-scribble-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (render (list (dynamic-require file 'doc)) (list name)
              #:dest-dir directory #:render-mixin renderer #:quiet? #t)
      (check directory))
    (lambda () (delete-directory/files directory))))



(module+ test
   (test-case "Scribble renderers select PNG, preferred SVG, and PDF assets"
     ;; These are render-only fixtures. The LaTeX case validates the generated
     ;; .tex and PDF asset; it intentionally does not claim TeX compilation.
     (render-fixture (fixture-path "convertible-scribble-png.scrbl") html:render-mixin "png"
                     (lambda (directory)
                       (define html (build-path directory "png.html"))
                       (check-true (file-exists? html))
                       (check-true (regexp-match? #rx#"pict[.]png" (file->bytes html)))
                       (check-true (has-extension? directory #rx#"[.]png$"))))
     (render-fixture (fixture-path "convertible-scribble-svg.scrbl") html:render-mixin "svg"
                     (lambda (directory)
                       (define html (build-path directory "svg.html"))
                       (check-true (file-exists? html))
                       (check-true (regexp-match? #rx#"image/svg[+]xml" (file->bytes html)))
                       (check-true (has-extension? directory #rx#"[.]svg$"))))
     (render-fixture (fixture-path "convertible-scribble-pdf.scrbl") latex:render-mixin "latex"
                     (lambda (directory)
                       (define tex (build-path directory "latex.tex"))
                       (check-true (file-exists? tex))
                       (check-true (regexp-match? #rx#"[.]pdf" (file->bytes tex)))
                       (check-true (has-extension? directory #rx#"[.]pdf$"))))))
