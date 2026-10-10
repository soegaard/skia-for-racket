#lang racket/base

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "pattern-sheet.rkt")

(provide pictures-interaction
         pictures-racketblock+eval
         pictures-image
         pictures-finished-pict)

(define pictures-eval (make-base-eval))

(void
 (interaction-eval
  #:eval pictures-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval pictures-eval
  (define (pictures-render-pict width height draw
                               #:background [background "#EDF2F7"]
                               #:scale [scale 0.8])
    (with-skia ([surface (make-surface width height
                                      #:background background)])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       scale)))))

(define-syntax-rule (pictures-interaction expression ...)
  (interaction #:eval pictures-eval expression ...))

(define-syntax-rule (pictures-racketblock+eval expression ...)
  (racketblock+eval #:eval pictures-eval expression ...))

(define-syntax-rule (pictures-image expression)
  (interaction-eval-show #:eval pictures-eval expression))

;; The first and last figures use the same drawing function as the standalone file.
(define (pictures-finished-pict #:scale [scale 0.63])
  (with-skia ([surface (make-surface sheet-width sheet-height
                                    #:background sheet-background)])
    (draw-pattern-sheet (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (surface->png-bytes surface))
       'png/alpha))
     scale)))
