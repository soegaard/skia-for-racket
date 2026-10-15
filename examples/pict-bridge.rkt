#lang racket/base

;; Run with: racket examples/pict-bridge.rkt output/pict-bridge.png
(require racket/class racket/cmdline
         (prefix-in pict: pict)
         skia skia/pict)

(define output-file
  (command-line
   #:program "pict-bridge"
   #:args (filename)
   filename))

(define picture
  (with-skia ([surface (make-surface 240 140 #:background 'white)]
              [blue (make-paint #:color 'blue #:antialias? #t)]
              [orange (make-paint #:color 'orange #:antialias? #t)])
    (define canvas (surface-canvas surface))
    (draw-circle canvas 70 70 45 blue)
    (draw-rounded-rect canvas 115 35 90 70 12 12 orange)
    ;; The pict owns a copied bitmap after this scope closes the surface.
    (surface->pict surface #:backing-scale 2)))

(define bitmap (pict:pict->bitmap picture))
(unless (send bitmap save-file output-file 'png)
  (error 'pict-bridge "could not write PNG: ~a" output-file))
