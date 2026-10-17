#lang racket

;;;
;;; Sprites Atlas
;;;

;; Draws the original ball artwork into a padded CPU sprite atlas.
;; This original CPU artwork supplies the tutorial renderer and its documentation figures.


;;;
;;; Imports and Exports
;;;

(require skia "../support/sprite-math.rkt")
(provide make-ball-atlas ball-colors)

;;;
;;; Drawing Data and Helpers
;;;

; ball-colors : list?
;;   Orders the ball colors used by the comparison or drawing.
(define ball-colors
  '("#58DCF2" "#FFB65A" "#B895FA" "#FF769C"
    "#81E7A0" "#6CA9FF" "#FFEA78" "#F18CFF"))

; make-ball-atlas : -> image?
;;   Constructs ball atlas for the example's drawing pipeline.
(define (make-ball-atlas)
  (with-skia ([surface (make-surface atlas-width (atlas-height 8)
                                     #:background 'transparent)])
    (define canvas (surface-canvas surface))
    (for ([color (in-list ball-colors)] [index (in-naturals)])
      (match-define (list x y width height) (sprite-source index))
      (with-skia ([gradient (make-radial-gradient-shader
                             18 16 27 (list "#FFFFFF" color "#162441")
                             #:positions '(0 0.28 1))]
                  [paint (make-paint #:shader gradient)]
                  [halo (make-paint #:color (rgba 190 220 255 30))]
                  [shine (make-paint #:color (rgba 255 255 255 210))])
        (with-canvas-state canvas
          (canvas-translate! canvas x y)
          (canvas-clip-rect! canvas 0 0 width height)
          (draw-circle canvas 24 24 23 halo)
          (draw-circle canvas 24 24 20 paint)
          ;; The off-center highlight makes rotations visible.
          (draw-oval canvas 12 10 8 5 shine))))
    (surface-snapshot surface)))
