#lang racket/base
(require racket/class racket/cmdline "../main.rkt" "../bitmap.rkt")

(define (render-bitmap filename)
  ;; The returned bitmap owns a copy and can outlive the Skia surface.
  (define bm
    (with-skia ([s (make-surface 320 240)]
                [p (make-paint #:color (rgba 35 115 235 180))])
      (draw-circle (surface-canvas s) 160 120 80 p)
      (surface->bitmap s)))
  ;; This example deliberately exercises racket/draw's PNG encoder instead.
  (when (file-exists? filename)
    (error 'bitmap-bridge "output file already exists: ~a" filename))
  (unless (send bm save-file filename 'png)
    (error 'bitmap-bridge "could not save ~a" filename)))

(module+ main
  (define filename
    (command-line #:program "bitmap-bridge.rkt" #:args ([output "bitmap.png"]) output))
  (render-bitmap filename)
  (printf "Wrote ~a\n" filename))
