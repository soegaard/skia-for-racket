#lang racket

;;;
;;; Squadron Atlas
;;;

;; Draws original ship, enemy, projectile, and explosion artwork into an atlas.
;; This original CPU artwork supplies the tutorial renderer and its documentation figures.


;;;
;;; Imports and Exports
;;;

(require skia "../support/sprite-math.rkt")
(provide make-game-atlas sprite-names draw-game-cell)

;;;
;;; Game Sprite Atlas
;;;

;; Original geometric artwork. No original Galaga graphics are used.

; sprite-names : vector?
;   Orders atlas cell names so drawing and animation choose the same artwork.
(define sprite-names
  '#(player-0 player-1 scout-0 scout-1 guard-0 guard-1
             player-shot enemy-shot blast-0 blast-1 blast-2 blast-3 blast-4 blast-5
             shield star))

; draw-game-cell : canvas? exact-nonnegative-integer? -> void?
;   Draws the game cell component in the current canvas coordinate system.
(define (draw-game-cell canvas index)
  (with-skia ([white (make-paint #:color "#EDF9FF")]
              [cyan (make-paint #:color "#56E0F5")]
              [blue (make-paint #:color "#346CCF")]
              [pink (make-paint #:color "#FA789F")]
              [amber (make-paint #:color "#FFCC72")]
              [dark (make-paint #:color "#13233B")]
              [outline (make-paint #:color "#D6F6FF" #:style 'stroke #:stroke-width 1.2)])
    (cond
      [(< index 2)
       (draw-polygon canvas '((24 4) (29 23) (43 36) (29 33) (24 39) (19 33) (5 36) (19 23))
                     white)
       (draw-polygon canvas '((24 11) (27 27) (24 31) (21 27)) cyan)
       (draw-polygon canvas '((18 25) (18 31) (8 33)) blue)
       (draw-polygon canvas '((30 25) (40 33) (30 31)) blue)
       (draw-polygon canvas (list '(21 36) (list 24 (if (zero? index) 43 46)) '(27 36)) amber)]
      [(< index 6)
       (define guard? (>= index 4))
       (define wing-y (if (even? index) 14 29))
       (define body (if guard? pink cyan))
       (draw-polygon canvas (list '(24 10) (list 4 wing-y) '(10 35) '(20 29)
                                  '(24 43) '(28 29) '(38 35) (list 44 wing-y)) body)
       (draw-polygon canvas '((24 9) (32 23) (24 38) (16 23))
                     (if guard? amber blue))
       (draw-circle canvas 20 23 2.5 white)
       (draw-circle canvas 28 23 2.5 white)
       (when guard?
         (draw-line canvas 14 32 8 40 outline)
         (draw-line canvas 34 32 40 40 outline))]
      [(= index 6)
       (draw-rounded-rect canvas 19 8 10 32 5 5 cyan)
       (draw-rounded-rect canvas 22 9 4 28 2 2 white)]
      [(= index 7)
       (draw-polygon canvas '((24 7) (31 23) (24 41) (17 23)) pink)
       (draw-polygon canvas '((24 13) (27 24) (24 34) (21 24)) amber)]
      [(< index 14)
       (define stage (- index 8))
       (define radius (+ 5 (* stage 3)))
       (define alpha (max 0 (- 255 (* stage 38))))
       (with-skia ([ring (make-paint #:color (rgba 255 183 79 alpha)
                                    #:style 'stroke #:stroke-width (max 1 (- 5 stage)))]
                   [spark (make-paint #:color (rgba 255 235 169 alpha))])
         (draw-circle canvas 24 24 radius ring)
         (for ([ray (in-range 8)])
           (define angle (+ (* ray (/ pi 4)) (* stage 0.1)))
           (draw-circle canvas (+ 24 (* radius (cos angle))) (+ 24 (* radius (sin angle)))
                        (max 1 (- 4 (* stage 0.5))) spark)))]
      [(= index 14) (draw-circle canvas 24 24 21 outline)]
      [else
       (draw-polygon canvas '((24 4) (28 19) (43 24) (28 29) (24 44) (20 29) (5 24) (20 19))
                     amber)])))

; make-game-atlas : -> image?
;   Constructs game atlas for the example's drawing pipeline.
(define (make-game-atlas)
  (with-skia ([surface (make-surface atlas-width (atlas-height 16)
                                     #:background 'transparent)])
    (define canvas (surface-canvas surface))
    (for ([index (in-range 16)])
      (match-define (list x y width height) (sprite-source index))
      (with-canvas-state canvas
        (canvas-translate! canvas x y)
        (canvas-clip-rect! canvas 0 0 width height)
        (draw-game-cell canvas index)))
    (surface-snapshot surface)))
