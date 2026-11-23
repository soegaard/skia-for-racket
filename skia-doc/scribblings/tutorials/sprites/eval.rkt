#lang racket

;;;
;;; Sprites Tutorial Evaluation
;;;

;; Runs the Sprites tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path scribble/eval skia "atlas.rkt" "model.rkt" "scene.rkt"
         "../support/figures.rkt" "../support/sprite-figures.rkt" "../support/sprite-math.rkt")
(provide sprites-interaction balls-pict balls-motion ball-atlas-pict one-ball-pict placements-pict)

;;;
;;; Tutorial Evaluator Setup
;;;

; model-source : path?
;   Locates model source relative to this module rather than the current directory.
(define-runtime-path model-source "model.rkt")

; math-source : path?
;   Locates math source relative to this module rather than the current directory.
(define-runtime-path math-source "../support/sprite-math.rkt")

; evaluator : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define evaluator (make-base-eval))
(evaluator `(require racket (file ,(path->string model-source))
                      (file ,(path->string math-source))))

;;;
;;; Sprite Atlas and Motion Figures
;;;

; balls-pict : [any/c] #:scale [real?] -> pict?
;   Renders the balls illustration from the tutorial's drawing code.
(define (balls-pict [steps 0] #:scale [scale 0.8])
  (define world (make-ball-world 30))
  (for ([_ (in-range steps)]) (step-balls! world fixed-step void))
  (with-skia ([atlas (make-ball-atlas)])
    (render-pict scene-width scene-height
                 (lambda (canvas) (draw-balls canvas atlas world)) #:scale scale)))

; balls-motion : -> pict?
;   Builds the balls motion illustration from the tutorial's actual drawing.
(define (balls-motion)
  (figure-row (captioned-pict "t = 0 seconds" (balls-pict 0 #:scale 0.4))
              (captioned-pict "t = 1 second" (balls-pict 120 #:scale 0.4))))

; ball-atlas-pict : -> pict?
;   Renders the ball atlas illustration from the tutorial's drawing code.
(define (ball-atlas-pict)
  (with-skia ([atlas (make-ball-atlas)]) (atlas-pict atlas 8)))

; one-ball-pict : -> pict?
;   Renders the one ball illustration from the tutorial's drawing code.
(define (one-ball-pict)
  (with-skia ([atlas (make-ball-atlas)])
    (render-pict
     280 170
     (lambda (canvas)
       (draw-checker canvas 280 170)
       (draw-atlas canvas atlas
                   (list (make-atlas-transform 140 76 #:anchor sprite-anchor #:scale 2))
                   (list (sprite-source 2)) #:sampling 'linear)
       (with-skia ([ink (make-paint #:color "#20364B")]
                   [mark (make-paint #:color "#07172A" #:style 'stroke
                                     #:stroke-width 1.7)]
                   [font (make-font #:size 14)])
         ;; The cross marks the transformed anchor, not the atlas cell origin.
         (draw-circle canvas 140 76 6 mark)
         (draw-line canvas 129 76 151 76 mark)
         (draw-line canvas 140 65 140 87 mark)
         (draw-simple-text canvas "cell 2 / anchor at (140, 76)" 42 152 font ink))))))

; placements-pict : -> pict?
;   Renders the placements illustration from the tutorial's drawing code.
(define (placements-pict)
  (with-skia ([atlas (make-ball-atlas)])
    (render-pict
     600 174
     (lambda (canvas)
       (canvas-clear! canvas "#091426")
       (draw-atlas canvas atlas
                   (list (make-atlas-transform 100 76 #:anchor sprite-anchor)
                         (make-atlas-transform 300 76 #:anchor sprite-anchor
                                               #:scale 1.5 #:rotation 40)
                         (make-atlas-transform 500 76 #:anchor sprite-anchor
                                               #:scale 2 #:rotation -35))
                   (make-list 3 (sprite-source 0)) #:sampling 'linear)
       (with-skia ([ink (make-paint #:color "#EAF5FF")]
                   [font (make-font #:size 14)])
         (for ([x '(40 228 420)] [text '("1x / 0 degrees" "1.5x / 40 degrees" "2x / -35 degrees")])
           (draw-simple-text canvas text x 152 font ink)))))))

;;;
;;; Scribble Interaction Form
;;;

; sprites-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (sprites-interaction expression ...)
  (interaction #:eval evaluator expression ...))
