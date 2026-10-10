#lang racket/base

(require scribble/eval)

(provide text-interaction
         text-interaction-eval
         text-racketmod+eval
         text-racketblock+eval
         text-def+int
         text-image)

(define text-eval (make-base-eval))

(void
 (interaction-eval
  #:eval text-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval text-eval
  (define (text-render-pict width height draw
                            #:background [background "#F4F0E8"]
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

(define-syntax-rule (text-interaction expression ...)
  (interaction #:eval text-eval expression ...))

(define-syntax-rule (text-interaction-eval expression ...)
  (interaction-eval #:eval text-eval expression ...))

(define-syntax-rule (text-racketmod+eval expression ...)
  (racketmod+eval #:eval text-eval expression ...))

(define-syntax-rule (text-racketblock+eval expression ...)
  (racketblock+eval #:eval text-eval expression ...))

(define-syntax-rule (text-def+int expression ...)
  (def+int #:eval text-eval expression ...))

(define-syntax-rule (text-image expression)
  (interaction-eval-show #:eval text-eval expression))
