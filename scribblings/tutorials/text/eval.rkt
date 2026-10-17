#lang racket/base

;;;
;;; Text Tutorial Evaluation
;;;

;; Runs the Text tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require scribble/eval)

(provide text-interaction
         text-interaction-eval
         text-racketmod+eval
         text-racketblock+eval
         text-def+int
         text-image)

;;;
;;; Evaluator and Figure Helpers
;;;

; text-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
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

; text-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (text-interaction expression ...)
  (interaction #:eval text-eval expression ...))

; text-interaction-eval : syntax -> syntax
;   Evaluates tutorial expressions in the shared documentation evaluator without displaying them.
(define-syntax-rule (text-interaction-eval expression ...)
  (interaction-eval #:eval text-eval expression ...))

; text-racketmod+eval : syntax -> syntax
;   Displays a module example and evaluates its expressions in the tutorial evaluator.
(define-syntax-rule (text-racketmod+eval expression ...)
  (racketmod+eval #:eval text-eval expression ...))

; text-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (text-racketblock+eval expression ...)
  (racketblock+eval #:eval text-eval expression ...))

; text-def+int : syntax -> syntax
;   Displays definitions followed by their evaluated tutorial interaction.
(define-syntax-rule (text-def+int expression ...)
  (def+int #:eval text-eval expression ...))

; text-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (text-image expression)
  (interaction-eval-show #:eval text-eval expression))
