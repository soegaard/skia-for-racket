#lang racket/base

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "card-with-shadows.rkt")

(provide effects-interaction
         effects-racketblock+eval
         effects-image
         effects-finished-pict)

(define effects-eval (make-base-eval))

(void
 (interaction-eval
  #:eval effects-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval effects-eval
  (define (effects-render-pict width height draw
                               #:background [background "#EEF3F8"]
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

(define-syntax-rule (effects-interaction expression ...)
  (interaction #:eval effects-eval expression ...))

(define-syntax-rule (effects-racketblock+eval expression ...)
  (racketblock+eval #:eval effects-eval expression ...))

(define-syntax-rule (effects-image expression)
  (interaction-eval-show #:eval effects-eval expression))

;; The opening image and final figure use the standalone drawing function.
(define (effects-finished-pict #:scale [scale 0.65])
  (with-skia ([surface (make-surface card-image-width card-image-height
                                    #:background background-color)])
    (draw-card (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (surface->png-bytes surface))
       'png/alpha))
     scale)))
