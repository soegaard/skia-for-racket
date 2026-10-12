#lang racket

(require skia "figures.rkt" "sprite-math.rkt")
(provide atlas-pict draw-checker)

(define (draw-checker canvas width height [cell 16])
  (with-skia ([first (make-paint #:color "#E9EEF4")]
              [second (make-paint #:color "#CED9E4")])
    (for* ([y (in-range 0 height cell)] [x (in-range 0 width cell)])
      (draw-rect canvas x y (min cell (- width x)) (min cell (- height y))
                 (if (even? (+ (quotient x cell) (quotient y cell))) first second)))))

(define (atlas-pict atlas count)
  (define width (* 2 (image-width atlas)))
  (define height (* 2 (image-height atlas)))
  (render-pict width height
               (lambda (canvas)
                 (draw-checker canvas width height)
                 ;; Draw the actual returned atlas image, enlarged with nearest sampling.
                 (draw-image-rect canvas atlas 0 0 width height #:sampling 'nearest)
                 (with-skia ([line (make-paint #:color "#657D97"
                                              #:style 'stroke #:stroke-width 1)]
                             [ink (make-paint #:color "#20364B")]
                             [font (make-font #:size 11)])
                   (for ([index (in-range count)])
                     (match-define (list x y w h) (sprite-source index))
                     (draw-rect canvas (* 2 x) (* 2 y) (* 2 w) (* 2 h) line)
                     (draw-simple-text canvas (number->string index)
                                       (* 2 (- x cell-gap)) (+ 9 (* 2 (- y cell-gap)))
                                       font ink))))))
