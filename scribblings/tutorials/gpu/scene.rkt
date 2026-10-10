#lang racket

(require skia)

(provide scene-width
         scene-height
         scene-background
         draw-scene)

(define scene-width 760)
(define scene-height 420)
(define scene-background "#0B1024")

(define (draw-background canvas)
  (define shader
    (make-linear-gradient-shader
     0 0 scene-width scene-height
     '("#0B1024" "#18345A" "#235B70")
     #:positions '(0 3/5 1)))
  (define paint
    (make-paint #:shader shader))
  (draw-rect canvas
             0 0
             scene-width scene-height
             paint))

(define (draw-grid canvas)
  (define grid
    (make-paint #:color (rgba 230 242 250 22)
                #:style 'stroke
                #:stroke-width 1))
  (for ([x (in-range 40 scene-width 40)])
    (draw-line canvas x 28 x (- scene-height 28) grid))
  (for ([y (in-range 40 scene-height 40)])
    (draw-line canvas 28 y (- scene-width 28) y grid)))

(define (draw-orbit canvas)
  (define orbit
    (make-path
     '((move 72 314)
       (cubic 208 62 548 56 690 300))))
  (define orbit-paint
    (make-paint #:color (rgba 237 245 250 150)
                #:style 'stroke
                #:stroke-width 3
                #:cap 'round))
  (define ring
    (make-paint #:color (rgba 237 245 250 90)
                #:style 'stroke
                #:stroke-width 2))
  (draw-path canvas orbit orbit-paint)
  (draw-oval canvas 242 100 278 205 ring)
  (draw-circle canvas 381 202 65 ring))

(define (draw-node canvas x y radius colors)
  (define shader
    (make-radial-gradient-shader
     x y radius
     colors
     #:positions '(0 7/10 1)))
  (define paint
    (make-paint #:shader shader))
  (draw-circle canvas x y radius paint))

(define (draw-nodes canvas)
  (draw-node canvas
             170 190 56
             (list "#FFF2BC"
                   "#F6B861"
                   (rgba 246 184 97 0)))
  (draw-node canvas
             383 113 44
             (list "#E2FAFF"
                   "#4FC7D0"
                   (rgba 79 199 208 0)))
  (draw-node canvas
             590 228 64
             (list "#F1E6FF"
                   "#9D78D8"
                   (rgba 157 120 216 0))))

(define (draw-center canvas)
  (define fill
    (make-paint #:color "#F4F7F8"))
  (define inner
    (make-paint #:color "#203A59"))
  (draw-circle canvas 381 202 28 fill)
  (draw-circle canvas 381 202 12 inner))

(define (draw-scene canvas)
  (draw-background canvas)
  (draw-grid canvas)
  (draw-orbit canvas)
  (draw-nodes canvas)
  (draw-center canvas))
