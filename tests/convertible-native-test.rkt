#lang racket/base

;;;
;;; Convertible Native Test
;;;

;; Covers file/convertible live Skia interoperability.
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;

(require rackunit rackunit/text-ui racket/class racket/file racket/list racket/path
         racket/runtime-path
         file/convertible
         (prefix-in pict: pict)
         (only-in racket/draw read-bitmap)
         (prefix-in html: scribble/html-render)
         (prefix-in latex: scribble/latex-render)
         scribble/render
         "../main.rkt")
(provide convertible-native-tests)


;;;
;;; Fixtures and Assertions
;;;

; png-signature : bytes?
;;   Holds the eight-byte PNG magic value used to identify converted output.
(define png-signature #"\211PNG\r\n\032\n")


; png-size : bytes? -> (listof exact-nonnegative-integer?)
;;   Reads IHDR width and height from a PNG fixture.
(define (png-size png)
  (list (integer-bytes->integer png #f #t 16 20)
        (integer-bytes->integer png #f #t 20 24)))


; png-pixel : bytes? exact-nonnegative-integer? exact-nonnegative-integer? -> bytes?
;;   Decodes a PNG with Racket Draw and reads one ARGB pixel as an independent oracle.
(define (png-pixel png x y)
  (define bitmap (read-bitmap (open-input-bytes png) 'png/alpha))
  (check-true (send bitmap ok?))
  (define argb (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 argb)
  argb)


; blank-page : document? -> any
;;   Adds an empty 20-by-12-point page to a PDF fixture.
(define (blank-page document)
  (call-with-document-page document 20 12 (lambda (_) (void))))


; finished-pdf : -> document?
;;   Creates and finishes a one-page PDF, leaving its wrapper for the caller to close.
(define (finished-pdf)
  (define document (make-pdf-document))
  (blank-page document)
  (document-finish! document)
  document)


; finished-svg : -> svg-document?
;;   Creates and finishes an empty SVG, leaving its wrapper for the caller to close.
(define (finished-svg)
  (define document (make-svg-document 20 12))
  (svg-document-finish! document)
  document)


; all-files : path-string? -> (listof path?)
;;   Lists output files recursively, excluding directories.
(define (all-files directory)
  (find-files (lambda (path) (not (directory-exists? path))) directory))


; has-extension? : path-string? regexp? -> boolean?
;;   Checks whether Scribble emitted any file matching the requested output suffix.
(define (has-extension? directory pattern)
  (for/or ([path (in-list (all-files directory))])
    (regexp-match? pattern (path->string path))))


; fixture-directory : path?
;;   Locates . relative to this module, independent of the invoking directory.
(define-runtime-path fixture-directory ".")

; fixture-path : path-string? -> path?
;;   Resolves a Scribble conversion fixture beside this test module.
(define (fixture-path name) (build-path fixture-directory name))


; render-fixture : module-path? procedure? string? procedure? -> any
;;   Renders a fixture in a temporary directory, checks its artifacts, and removes them afterward.
(define (render-fixture file renderer name check)
  (define directory (make-temporary-file "skia-convertible-scribble-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (render (list (dynamic-require file 'doc)) (list name)
              #:dest-dir directory #:render-mixin renderer #:quiet? #t)
      (check directory))
    (lambda () (delete-directory/files directory))))


;;;
;;; Regression Suite
;;;

; convertible-native-tests : test-suite?
;;   Collects the regression cases for file/convertible live Skia interoperability.
(define convertible-native-tests
  (test-suite
   "file/convertible live Skia interoperability"
   (test-case "all target values expose the conversion property"
     (with-skia ([surface (make-surface 3 2)]
                 [image (surface-snapshot surface)]
                 [pdf (finished-pdf)]
                 [svg (finished-svg)])
       (define page (make-output-page 3 2 void))
       (for ([value (in-list (list image surface pdf svg page))])
         (check-true (convertible? value)))))
   (test-case "unknown requests return defaults by identity without source checks"
     (define default-object (box 'default))
     (define default-procedure (lambda () (error 'default "must not run")))
     (define image (rgba-bytes->image 1 1 (bytes 255 0 0 255)))
     (define surface (make-surface 1 1))
     (define pdf (make-pdf-document))
     (define svg (make-svg-document 1 1))
     (define page (make-output-page 1 1 void))
     (dynamic-wind
       void
       (lambda ()
         (for ([value (in-list (list image surface pdf svg page))])
           (check-eq? (convert value 'not-a-format default-object) default-object)
           (check-eq? (convert value 'png@2x-bytes default-procedure) default-procedure)))
       (lambda ()
         (for ([value (in-list (list image surface pdf svg))]) (skia-close! value)))))
   (test-case "image conversion decodes transparently and survives source closure"
     (define png
       (with-skia ([image (rgba-bytes->image 2 1
                                             (bytes 255 0 0 255 0 0 0 0))])
         (convert image 'png-bytes)))
     (check-equal? (subbytes png 0 8) png-signature)
     (check-equal? (png-size png) '(2 1))
     (check-equal? (png-pixel png 0 0) (bytes 255 255 0 0))
     ;; RGB at zero alpha is unspecified by PNG's premultiplied source.
     (check-equal? (bytes-ref (png-pixel png 1 0) 0) 0))
   (test-case "surface PNG conversion observes later drawing"
     (with-skia ([surface (make-surface 2 1 #:background 'red)])
       (define before (convert surface 'png-bytes))
       (canvas-clear! (surface-canvas surface) 'blue)
       (define after (convert surface 'png-bytes))
       (check-equal? (png-pixel before 0 0) (bytes 255 255 0 0))
       (check-equal? (png-pixel after 0 0) (bytes 255 0 0 255))))
   (test-case "finished document conversions match their byte readers"
     (with-skia ([pdf (finished-pdf)] [svg (finished-svg)])
       (check-equal? (convert pdf 'pdf-bytes) (document->pdf-bytes pdf))
       (check-equal? (convert svg 'svg-bytes) (svg-document->bytes svg))))
   (test-case "document conversion does not finish or rescue invalid states"
     (define fallback (box 'unused))
     (with-skia ([pdf (make-pdf-document)] [svg (make-svg-document 10 8)])
       (check-exn #rx"finish" (lambda () (convert pdf 'pdf-bytes fallback)))
       (check-eq? (document-state pdf) 'open)
       (void (document-begin-page! pdf 10 8))
       (check-exn #rx"finish" (lambda () (convert pdf 'pdf-bytes fallback)))
       (check-eq? (document-state pdf) 'page)
       (document-abort! pdf)
       (check-exn #rx"closed" (lambda () (convert pdf 'pdf-bytes fallback)))
       (check-exn #rx"finish" (lambda () (convert svg 'svg-bytes fallback)))
       (check-eq? (svg-document-state svg) 'open)
       (svg-document-abort! svg)
       (check-exn #rx"closed" (lambda () (convert svg 'svg-bytes fallback)))))
   (test-case "supported failures propagate instead of using defaults"
     (define fallback (box 'unused))
     (define image (rgba-bytes->image 1 1 (bytes 0 0 0 0)))
     (dynamic-wind
       void
       (lambda ()
         (skia-close! image)
         (check-exn #rx"closed" (lambda () (convert image 'png-bytes fallback))))
       (lambda () (skia-close! image))))
   (test-case "output-page dispatch uses a 96-DPI raster and reruns callbacks"
     (define calls 0)
     ;; One point rounds from 4/3 pixels to two pixels at the fixed 96 DPI.
     (define page (make-output-page 1 1 (lambda (_) (set! calls (add1 calls)))))
     (define png (convert page 'png-bytes))
     (define svg (convert page 'svg-bytes))
     (define pdf (convert page 'pdf-bytes))
     (check-equal? (png-size png) '(2 2))
     (check-true (regexp-match? #rx#"</svg>" svg))
     (check-true (regexp-match? #rx#"^%PDF-" pdf))
     (check-equal? calls 3))
   (test-case "output-page PNG cleanup also covers a failed callback"
     (define escaped-canvas #f)
     (define calls 0)
     (check-exn #rx"stop"
                (lambda ()
                  (convert
                   (make-output-page 8 8
                     (lambda (canvas)
                       (set! calls (add1 calls))
                       (set! escaped-canvas canvas)
                       (error 'draw "stop")))
                   'png-bytes)))
     (check-equal? calls 1)
     (check-true (skia-closed? escaped-canvas)))
   (test-case "pict:bitmap consumes detached PNG data from images and surfaces"
     (define (check-pict source expected-size expected-pixel)
       (define picture (pict:bitmap source))
       (skia-close! source)
       (check-true (pict:pict? picture))
       (check-equal? (list (pict:pict-width picture) (pict:pict-height picture)) expected-size)
       (define bitmap (pict:pict->bitmap picture))
       (define argb (make-bytes 4))
       (send bitmap get-argb-pixels 0 0 1 1 argb)
       (check-equal? argb expected-pixel))
     (check-pict (rgba-bytes->image 3 2 (make-bytes 24 255)) '(3 2) (bytes 255 255 255 255))
     (check-pict (make-surface 2 3 #:background 'blue) '(2 3) (bytes 255 0 0 255)))
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
                       (check-true (has-extension? directory #rx#"[.]pdf$")))))))

(module+ test
  (skia-check!)

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests convertible-native-tests))
  (unless (zero? failures) (error 'convertible-native-test "~a failures" failures)))
