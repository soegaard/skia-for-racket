#lang racket/base

(require scribble/eval)

(provide shaping-interaction
         shaping-interaction-eval
         shaping-racketmod+eval
         shaping-racketblock+eval
         shaping-def+int
         shaping-image)

(define shaping-eval (make-base-eval))

(void
 (interaction-eval
  #:eval shaping-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval shaping-eval
  (define (shaping-render-pict width height draw
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

(define-syntax-rule (shaping-interaction expression ...)
  (interaction #:eval shaping-eval expression ...))

(define-syntax-rule (shaping-interaction-eval expression ...)
  (interaction-eval #:eval shaping-eval expression ...))

(define-syntax-rule (shaping-racketmod+eval expression ...)
  (racketmod+eval #:eval shaping-eval expression ...))

(define-syntax-rule (shaping-racketblock+eval expression ...)
  (racketblock+eval #:eval shaping-eval expression ...))

(define-syntax-rule (shaping-def+int expression ...)
  (def+int #:eval shaping-eval expression ...))

(define-syntax-rule (shaping-image expression)
  (interaction-eval-show #:eval shaping-eval expression))
