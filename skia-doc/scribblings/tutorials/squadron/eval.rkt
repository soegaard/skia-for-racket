#lang racket

;;;
;;; Squadron Tutorial Evaluation
;;;

;; Runs the Squadron tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path scribble/eval skia "atlas.rkt" "model.rkt" "scene.rkt"
         "../support/figures.rkt" "../support/sprite-figures.rkt" "../support/sprite-math.rkt")
(provide squadron-interaction game-pict game-atlas-pict fleet-pict ship-pict
         dive-pict explosion-pict collision-pict game-states-pict)

;;;
;;; Tutorial Evaluator Setup
;;;

; model-source : path?
;   Locates model source relative to this module rather than the current directory.
(define-runtime-path model-source "model.rkt")

; evaluator : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define evaluator (make-base-eval))
(evaluator `(require racket (file ,(path->string model-source))))

;;;
;;; Game State and Sprite Figures
;;;

; game-pict : -> pict?
;   Renders the game illustration from the tutorial's drawing code.
(define (game-pict)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict scene-width scene-height
                 (lambda (canvas) (draw-game canvas atlas (demonstration-game))) #:scale 0.72)))

; game-atlas-pict : -> pict?
;   Renders the game atlas illustration from the tutorial's drawing code.
(define (game-atlas-pict)
  (with-skia ([atlas (make-game-atlas)]) (atlas-pict atlas 16)))

; ship-pict : -> pict?
;   Renders the ship illustration from the tutorial's drawing code.
(define (ship-pict)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict
     440 130
     (lambda (canvas)
       (draw-checker canvas 440 130)
       (draw-atlas canvas atlas
                   (list (make-atlas-transform 100 65 #:anchor sprite-anchor #:scale 2)
                         (make-atlas-transform 220 65 #:anchor sprite-anchor #:scale 2)
                         (make-atlas-transform 350 65 #:anchor sprite-anchor))
                   (map sprite-source '(0 1 6)) #:sampling 'nearest)))))

; fleet-pict : -> pict?
;   Renders the fleet illustration from the tutorial's drawing code.
(define (fleet-pict)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict
     640 310
     (lambda (canvas)
       (define world (make-game))
       (define sprites (take (game-sprites world) 21))
       (canvas-clear! canvas "#070D21")
       (draw-atlas canvas atlas
                   (for/list ([sprite (in-list sprites)])
                     (make-atlas-transform (second sprite) (third sprite) #:anchor sprite-anchor))
                   (map (lambda (sprite) (sprite-source (first sprite))) sprites)
                   #:sampling 'linear)))))

; dive-pict : -> pict?
;   Renders the dive illustration from the tutorial's drawing code.
(define (dive-pict)
  (define diagram-scale 0.66)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict
     640 620
     (lambda (canvas)
       (canvas-clear! canvas "#070D21")
       (with-skia ([line (make-paint #:color "#547A9A" #:style 'stroke #:stroke-width 2)]
                   [ink (make-paint #:color "#DCF4FF")]
                   [font (make-font #:size 16)])
         ;; Transform paths and sprites together so visible tangents match headings.
         (with-canvas-state canvas
           (canvas-translate! canvas (/ (* 640 (- 1 diagram-scale)) 2) 0)
           (canvas-scale! canvas diagram-scale diagram-scale)
           (for ([side '(-1 1)] [start-x '(175 465)])
             (define (sample age) (dive age start-x 80 320 side))
             (define points
               (for/vector ([age (in-range 0 289 6)])
                 (define-values (x y) (dive-point (sample age)))
                 (vector x y)))
             (draw-polygon canvas points line #:closed? #f)
             (for ([age '(0 84 168 252)])
               (define attack (sample age))
               (define sprite (enemy 7 'scout 1 attack))
               (define-values (x y) (dive-point attack))
               (draw-atlas canvas atlas
                           (list (make-atlas-transform x y
                                                       #:anchor sprite-anchor
                                                       #:rotation (enemy-angle sprite 0)))
                           (list (sprite-source 2)) #:sampling 'linear))))
         (draw-simple-text canvas "Two mirrored dives; target chosen at launch" 138 584 font ink)))
     #:scale 0.75)))

; explosion-pict : -> pict?
;   Renders the explosion illustration from the tutorial's drawing code.
(define (explosion-pict)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict
     600 110
     (lambda (canvas)
       (draw-checker canvas 600 110)
       (draw-atlas canvas atlas
                   (for/list ([x '(50 150 250 350 450 550)])
                     (make-atlas-transform x 50 #:anchor sprite-anchor #:scale 1.5))
                   (map sprite-source '(8 9 10 11 12 13)) #:sampling 'nearest)))))

; collision-pict : -> pict?
;   Renders the collision illustration from the tutorial's drawing code.
(define (collision-pict)
  (with-skia ([atlas (make-game-atlas)])
    (render-pict
     690 220
     (lambda (canvas)
       (canvas-clear! canvas "#070D21")
       (draw-atlas canvas atlas
                   (list (make-atlas-transform 170 92 #:anchor sprite-anchor #:scale 2)
                         (make-atlas-transform 510 92 #:anchor sprite-anchor #:scale 2))
                   (list (sprite-source 2) (sprite-source 2)) #:sampling 'linear)
       (with-skia ([ring (make-paint #:color "#FFCD78"
                                     #:style 'stroke #:stroke-width 2)]
                   [line (make-paint #:color "#67E4EF"
                                     #:style 'stroke #:stroke-width 3)]
                   [hit (make-paint #:color "#81E7A0")]
                   [font (make-font #:size 18)]
                   [ink (make-paint #:color "#EAF8FF")])
         (draw-circle canvas 170 92 38 ring)
         (draw-circle canvas 510 92 38 ring)
         (draw-line canvas 170 170 170 10 line)
         (draw-line canvas 555 170 555 10 line)
         (draw-circle canvas 170 92 4 hit)
         (draw-simple-text canvas "HIT: segment crosses circle" 34 198 font ink)
         (draw-simple-text canvas "MISS: 45 units from center" 370 198 font ink))))))

; game-states-pict : -> pict?
;   Renders the game states illustration from the tutorial's drawing code.
(define (game-states-pict)
  (with-skia ([atlas (make-game-atlas)])
    (define (one mode)
      (define world (make-game))
      (set-game-mode! world mode)
      (when (eq? mode 'wave-clear) (set-game-enemies! world '()))
      (when (eq? mode 'game-over) (set-game-lives! world 0))
      (render-pict
       560 180
       (lambda (canvas)
         (with-canvas-state canvas
           (canvas-translate! canvas -40 -305)
           (draw-game canvas atlas world)))
       #:scale 0.55))
    (figure-row (captioned-pict "After clearing a wave" (one 'wave-clear))
                (captioned-pict "After the last life" (one 'game-over)))))

;;;
;;; Scribble Interaction Form
;;;

; squadron-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (squadron-interaction expression ...)
  (interaction #:eval evaluator expression ...))
