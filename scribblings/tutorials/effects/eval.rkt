#lang racket/base

;;;
;;; Effects Tutorial Evaluation
;;;

;; Runs the Effects tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "card-with-shadows.rkt")

(provide effects-interaction
         effects-racketblock+eval
         effects-image
         effects-finished-pict)

;;;
;;; Evaluator and Figure Helpers
;;;

; effects-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
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

; effects-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (effects-interaction expression ...)
  (interaction #:eval effects-eval expression ...))

; effects-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (effects-racketblock+eval expression ...)
  (racketblock+eval #:eval effects-eval expression ...))

; effects-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (effects-image expression)
  (interaction-eval-show #:eval effects-eval expression))

;; The opening image and final figure use the standalone drawing function.

; effects-finished-pict : #:scale [real?] -> pict?
;   Renders the effects finished illustration from the tutorial's drawing code.
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
