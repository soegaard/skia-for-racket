#lang racket

(require skia "model.rkt" "../support/sprite-math.rkt")
(provide draw-balls ball-transform)

(define (ball-transform sprite)
  (make-atlas-transform (ball-x sprite) (ball-y sprite)
                        #:scale (ball-scale sprite)
                        #:rotation (ball-angle sprite)
                        #:anchor sprite-anchor))

(define (draw-balls canvas atlas world)
  (define sprites (ball-world-balls world))
  (canvas-clear! canvas "#091426")
  (with-skia ([grid (make-paint #:color "#142840" #:style 'stroke #:stroke-width 1)]
              [line (make-paint #:color "#34516E" #:style 'stroke #:stroke-width 1.5)]
              [ink (make-paint #:color "#EAF5FF")]
              [subtle (make-paint #:color "#92ACC6")]
              [title (make-font #:size 24)]
              [detail (make-font #:size 13)])
    (for ([x (in-range 18 scene-width 40)])
      (draw-line canvas x 78 x (- scene-height 18) grid))
    (for ([y (in-range 78 scene-height 40)])
      (draw-line canvas 18 y (- scene-width 18) y grid))
    (draw-rect canvas 18 78 (- scene-width 36) (- scene-height 96) line)
    (draw-simple-text canvas "BOUNCING SPRITES" 24 35 title ink)
    (draw-simple-text canvas "One atlas. Changing placements. No ball-to-ball collisions."
                      25 59 detail subtle)
    ;; A source rectangle is selected independently for every placement.
    (draw-atlas canvas atlas
                (map ball-transform sprites)
                (map (lambda (sprite) (sprite-source (ball-cell sprite))) sprites)
                #:sampling 'linear)))
