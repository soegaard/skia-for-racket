#lang scribble/manual

@(require "accessible-figures.rkt" scribble/eval (prefix-in pict: pict))
@(define-values (finished-preview finish-figure) (make-figure-preview))
@(define evaluator (make-base-eval))

@title{Early Figure Smoke Test}

@|finished-preview|

The finished panel above is supplied later. This code does not produce another figure:

@racketblock[(define width 32)]

@(tutorial-figure "Direct panel: 24 by 16." (pict:blank 24 16))

@(interaction-eval #:eval evaluator (require pict) (define draws 0))
@(finish-figure
  (tutorial-figure "Finished panel: Bézier -- origin & scale."
    (interaction-eval-show #:eval evaluator
      (begin (set! draws (add1 draws)) (blank 32 20)))))

@(unless (= (evaluator 'draws) 1) (error 'early-figures-smoke "figure evaluated twice"))
@(close-eval evaluator)
