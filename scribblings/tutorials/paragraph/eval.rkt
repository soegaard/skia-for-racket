#lang racket/base

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "article-card.rkt")

(provide paragraph-interaction
         paragraph-interaction-eval
         paragraph-racketblock+eval
         paragraph-image
         paragraph-article-pict)

(define paragraph-eval (make-base-eval))

(void
 (interaction-eval
  #:eval paragraph-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval paragraph-eval
  (define (paragraph-render-pict width height draw
                                 #:background [background "#F4F6F9"]
                                 #:scale [scale 0.72])
    (with-skia ([surface (make-surface width height
                                      #:background background)])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       scale)))))

(define-syntax-rule (paragraph-interaction expression ...)
  (interaction #:eval paragraph-eval expression ...))

(define-syntax-rule (paragraph-interaction-eval expression ...)
  (interaction-eval #:eval paragraph-eval expression ...))

(define-syntax-rule (paragraph-racketblock+eval expression ...)
  (racketblock+eval #:eval paragraph-eval expression ...))

(define-syntax-rule (paragraph-image expression)
  (interaction-eval-show #:eval paragraph-eval expression))

;; The final figure uses the very same drawing function as article-card.rkt.
(define (paragraph-article-pict)
  (with-skia ([surface (make-surface card-width card-height
                                    #:background "#EDF2F7")])
    (draw-article-card (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (surface->png-bytes surface))
       'png/alpha))
     0.66)))
