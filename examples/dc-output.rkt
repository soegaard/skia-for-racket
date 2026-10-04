#lang racket/base
;; Generate PDF/SVG examples without opening a GUI or acquiring a GPU.
;; The same draw callback can also be used in a render-canvas paint callback.
(require racket/cmdline racket/file
         (prefix-in sk: "../main.rkt") "../dc-output.rkt"
         "../tests/dc-output-fixtures.rkt")
(module+ main
  (define directory "output/dc-output-example")
  (command-line #:once-each
    [("--directory") value "destination directory" (set! directory value)]
    #:args () (void))
  (make-directory* directory)
  (define page (make-dc-output-page 200 160 draw-output-mixed-scene #:background 'white))
  (for ([fmt '(pdf svg)])
    (define target (build-path directory (format "shared-scene.~a" fmt)))
    (sk:save-output/audit page target fmt #:exists 'replace #:policy 'error)
    (printf "Wrote ~a\n" target))
  (sk:with-skia ([image (sk:output-page->image page #:dpi 144)])
    (call-with-output-file (build-path directory "shared-scene.png")
      (lambda (out) (write-bytes (sk:image->png-bytes image) out)) #:exists 'replace #:mode 'binary)))
