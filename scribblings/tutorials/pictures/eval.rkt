#lang racket/base

;;;
;;; Pictures Tutorial Evaluation
;;;

;; Runs the Pictures tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "pattern-sheet.rkt")

(provide pictures-interaction
         pictures-racketblock+eval
         pictures-image
         pictures-finished-pict)

;;;
;;; Evaluator and Figure Helpers
;;;

; pictures-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
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

; pictures-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (pictures-interaction expression ...)
  (interaction #:eval pictures-eval expression ...))

; pictures-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (pictures-racketblock+eval expression ...)
  (racketblock+eval #:eval pictures-eval expression ...))

; pictures-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (pictures-image expression)
  (interaction-eval-show #:eval pictures-eval expression))

;; The first and last figures use the same drawing function as the standalone file.

; pictures-finished-pict : #:scale [real?] -> pict?
;   Renders the pictures finished illustration from the tutorial's drawing code.
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
