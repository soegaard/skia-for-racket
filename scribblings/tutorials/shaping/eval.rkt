#lang racket/base

;;;
;;; Shaping Tutorial Evaluation
;;;

;; Runs the Shaping tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require scribble/eval)

(provide shaping-interaction
         shaping-interaction-eval
         shaping-racketmod+eval
         shaping-racketblock+eval
         shaping-def+int
         shaping-image)

;;;
;;; Evaluator and Figure Helpers
;;;

; shaping-eval : procedure?
;;   Retains one evaluator so successive documentation examples share their bindings.
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

; shaping-interaction : syntax -> syntax
;;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (shaping-interaction expression ...)
  (interaction #:eval shaping-eval expression ...))

; shaping-interaction-eval : syntax -> syntax
;;   Evaluates tutorial expressions in the shared documentation evaluator without displaying them.
(define-syntax-rule (shaping-interaction-eval expression ...)
  (interaction-eval #:eval shaping-eval expression ...))

; shaping-racketmod+eval : syntax -> syntax
;;   Displays a module example and evaluates its expressions in the tutorial evaluator.
(define-syntax-rule (shaping-racketmod+eval expression ...)
  (racketmod+eval #:eval shaping-eval expression ...))

; shaping-racketblock+eval : syntax -> syntax
;;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (shaping-racketblock+eval expression ...)
  (racketblock+eval #:eval shaping-eval expression ...))

; shaping-def+int : syntax -> syntax
;;   Displays definitions followed by their evaluated tutorial interaction.
(define-syntax-rule (shaping-def+int expression ...)
  (def+int #:eval shaping-eval expression ...))

; shaping-image : syntax -> syntax
;;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (shaping-image expression)
  (interaction-eval-show #:eval shaping-eval expression))
