#lang racket/base

;;;
;;; Images Tutorial Evaluation
;;;

;; Runs the Images tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path
         scribble/eval)

(provide images-interaction
         images-interaction-eval
         images-racketmod+eval
         images-racketblock+eval
         images-def+int
         images-image)

;;;
;;; Evaluator and Figure Helpers
;;;

; fixture-directory : path?
;;   Locates fixture directory relative to this module rather than the current directory.
(define-runtime-path fixture-directory "fixtures")

; images-eval : procedure?
;;   Retains one evaluator so successive documentation examples share their bindings.
(define images-eval (make-base-eval))

(images-eval
 '(require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict)))

(images-eval
 `(define tutorial-fixture-directory
    ,(path->string fixture-directory)))

(images-eval
 '(define (tutorial-fixture name)
    (build-path tutorial-fixture-directory name)))

(images-eval
 '(define (images-render-pict width height draw)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F1EA")])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72))))

; images-interaction : syntax -> syntax
;;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (images-interaction expression ...)
  (interaction #:eval images-eval expression ...))

; images-interaction-eval : syntax -> syntax
;;   Evaluates tutorial expressions in the shared documentation evaluator without displaying them.
(define-syntax-rule (images-interaction-eval expression ...)
  (interaction-eval #:eval images-eval expression ...))

; images-racketmod+eval : syntax -> syntax
;;   Displays a module example and evaluates its expressions in the tutorial evaluator.
(define-syntax-rule (images-racketmod+eval expression ...)
  (racketmod+eval #:eval images-eval expression ...))

; images-racketblock+eval : syntax -> syntax
;;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (images-racketblock+eval expression ...)
  (racketblock+eval #:eval images-eval expression ...))

; images-def+int : syntax -> syntax
;;   Displays definitions followed by their evaluated tutorial interaction.
(define-syntax-rule (images-def+int expression ...)
  (def+int #:eval images-eval expression ...))

; images-image : syntax -> syntax
;;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (images-image expression)
  (interaction-eval-show #:eval images-eval expression))
