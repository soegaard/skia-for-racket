#lang racket/base

;;;
;;; DC Output Example
;;;

;; Exports shared drawing-context callbacks to PDF, SVG, and raster previews.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Generate PDF/SVG examples without opening a GUI or acquiring a GPU.
;; The same draw callback can also be used in a render-canvas paint callback.
;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file
         (prefix-in sk: "../main.rkt") "../dc-output.rkt"
         "../tests/dc-output-fixtures.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; directory : string?
  ;   Selects the destination used by this example's output.
  (define directory "output/dc-output-example")
  (command-line #:once-each
    [("--directory") value "destination directory" (set! directory value)]
    #:args () (void))
  (make-directory* directory)

  ; page : output-page?
  ;   Describes the page drawing and its export dimensions.
  (define page (make-dc-output-page 200 160 draw-output-mixed-scene #:background 'white))
  (for ([fmt '(pdf svg)])
    (define target (build-path directory (format "shared-scene.~a" fmt)))
    (sk:save-output/audit page target fmt #:exists 'replace #:policy 'error)
    (printf "Wrote ~a\n" target))
  (sk:with-skia ([image (sk:output-page->image page #:dpi 144)])
    (call-with-output-file (build-path directory "shared-scene.png")
      (lambda (out) (write-bytes (sk:image->png-bytes image) out)) #:exists 'replace #:mode 'binary)))
