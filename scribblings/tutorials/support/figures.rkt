#lang racket/base

;; Presentation helpers only. Each caller supplies the real tutorial drawing.
(require skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict))

(provide render-pict image-pict captioned-pict figure-row)

(define (render-pict width height draw
                     #:scale [scale 1]
                     #:background [background 'white]
                     #:color-space [color-space #f])
  (with-skia ([surface (make-surface width height
                                     #:background background
                                     #:color-space color-space)])
    (draw (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap (open-input-bytes (surface->png-bytes surface)) 'png/alpha))
     scale)))

;; Magnification happens in Skia, not in the HTML/CSS image scaler.
(define (image-pict image factor #:sampling [sampling 'nearest])
  (define width (* factor (image-width image)))
  (define height (* factor (image-height image)))
  (render-pict width height
               (lambda (canvas)
                 (draw-image-rect canvas image 0 0 width height #:sampling sampling))))

(define (captioned-pict caption picture)
  (pict:vc-append 8 picture (pict:text caption)))

(define (figure-row . pictures)
  (apply pict:ht-append 16 pictures))
