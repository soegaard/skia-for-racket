#lang racket/base

;;;
;;; Paragraph Tutorial Evaluation
;;;

;; Runs the Paragraph tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

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

;;;
;;; Tutorial Evaluator Setup
;;;

; paragraph-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
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

;;;
;;; Scribble Forms and Preview Figure
;;;

; paragraph-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (paragraph-interaction expression ...)
  (interaction #:eval paragraph-eval expression ...))

; paragraph-interaction-eval : syntax -> syntax
;   Evaluates tutorial expressions in the shared documentation evaluator without displaying them.
(define-syntax-rule (paragraph-interaction-eval expression ...)
  (interaction-eval #:eval paragraph-eval expression ...))

; paragraph-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (paragraph-racketblock+eval expression ...)
  (racketblock+eval #:eval paragraph-eval expression ...))

; paragraph-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (paragraph-image expression)
  (interaction-eval-show #:eval paragraph-eval expression))

;; The final figure uses the very same drawing function as article-card.rkt.

; paragraph-article-pict : -> pict?
;   Renders the paragraph article illustration from the tutorial's drawing code.
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
