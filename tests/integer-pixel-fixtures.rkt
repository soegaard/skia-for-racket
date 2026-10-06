#lang racket/base
(require "../main.rkt")
(provide integer-fixture-info integer-fixture-samples fill-integer-fixture!
         draw-integer-fixture make-integer-fixture-image integer-fixture-width integer-fixture-height)
(define integer-fixture-width 80)
(define integer-fixture-height 64)
(define (integer-fixture-info format [width 4] [height 2])
  (make-image-info width height #:color-type format
                   #:alpha-type (if (memq format '(rgb-888x gray-8 rgb-565)) 'opaque 'premul)))
(define (integer-fixture-samples format)
  (case format
    [(rgba-8888 bgra-8888) '#(#(255 0 0 255) #(0 255 0 255) #(0 0 255 255) #(255 255 255 255))]
    [(rgb-888x) '#(#(255 0 0) #(0 255 0) #(0 0 255) #(255 255 255))]
    [(rgb-565) '#(#(31 0 0) #(0 63 0) #(0 0 31) #(31 63 31))]
    [(rgba-1010102) '#(#(1023 0 0 3) #(0 1023 0 3) #(0 0 1023 3) #(1023 1023 1023 3))]
    [(gray-8 alpha-8) '#(#(0) #(85) #(170) #(255))]
    [else (error 'integer-fixture-samples "unknown fixture")]))
(define (fill-integer-fixture! buffer format)
  (call-with-raster-buffer-pixmap buffer
    (lambda (view)
      (for* ([y (in-range 2)] [x (in-range 4)])
        (pixmap-set-sample! view x y (vector-ref (integer-fixture-samples format) x)))) #:writable? #t))
(define (draw-integer-fixture canvas image #:scale [scale 16])
  (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
    (draw-rect canvas 2 2 4 4 marker))
  (with-canvas-state canvas
    (canvas-translate! canvas 8 24)
    (canvas-scale! canvas scale scale)
    (draw-image canvas image 0 0 #:sampling 'nearest)))

;; Explicit staging for document/GPU consumers: selected integer source ->
;; nearest-neighbor RGBA pixmap -> independent immutable image. The image is
;; drawn 1:1, so PDF/SVG viewer interpolation is not part of the storage oracle.
(define (make-integer-fixture-image format)
  (with-skia ([source (make-raster-buffer-from-info (integer-fixture-info format))]
              [staging (make-raster-buffer-from-info (make-image-info 64 32))])
    (fill-integer-fixture! source format)
    (call-with-raster-buffer-pixmap source
      (lambda (src)
        (call-with-raster-buffer-pixmap staging
          (lambda (dst) (pixmap-scale! dst src #:sampling 'nearest)) #:writable? #t)))
    (raster-buffer->image staging)))
