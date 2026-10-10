#lang racket/base

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "vector-raster.rkt")

(provide vector-interaction
         vector-racketblock+eval
         vector-image
         vector-finished-pict)

(define vector-eval (make-base-eval))

(void
 (interaction-eval
  #:eval vector-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval vector-eval
  (define (vector-image-pict image #:scale [scale 0.70])
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (image->png-bytes image))
       'png/alpha))
     scale))))

(void
 (interaction-eval
  #:eval vector-eval
  (define (vector-render-pict width height draw
                              #:background [background "#F3F7FB"]
                              #:scale [scale 0.70])
    (with-skia ([surface (make-surface width height
                                      #:background background)])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       scale)))))

;; Enlarge the *actual* captured image through Skia with nearest sampling.
(void
 (interaction-eval
  #:eval vector-eval
  (define (vector-source-tile-pict image)
    (with-skia ([surface (make-surface 128 128)])
      (draw-image-rect (surface-canvas surface) image 0 0 128 128
                       #:sampling 'nearest)
      (pict:bitmap
       (draw:read-bitmap
        (open-input-bytes (surface->png-bytes surface))
        'png/alpha))))))

(define-syntax-rule (vector-interaction expression ...)
  (interaction #:eval vector-eval expression ...))

(define-syntax-rule (vector-racketblock+eval expression ...)
  (racketblock+eval #:eval vector-eval expression ...))

(define-syntax-rule (vector-image expression)
  (interaction-eval-show #:eval vector-eval expression))

;; The opening figure calls the standalone program's drawing function.
(define (vector-finished-pict #:scale [scale 0.64])
  (define page
    (make-output-page sheet-width sheet-height draw-study
                      #:unit 'px
                      #:background paper-color))
  (with-skia ([image (output-page->image page #:dpi 96 #:text-mode 'outline)])
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (image->png-bytes image))
       'png/alpha))
     scale)))
