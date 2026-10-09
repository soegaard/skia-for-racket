#lang racket/base

(require scribble/eval)

(provide skia-interaction
         skia-interaction-eval
         skia-racketblock+eval
         skia-racketmod+eval
         skia-def+int
         skia-image)

;; Keep one evaluator for the whole tutorial. Later examples can use
;; definitions from earlier sections, just as they do in Racket's Quick guide.
(define skia-eval (make-base-eval))

(void
 (interaction-eval
  #:eval skia-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

;; Turn the real pixels produced by Skia into a pict that Scribble can show.
;; The bitmap is scaled only for the page; the Skia surface remains 800 by 500.
(void
 (interaction-eval
  #:eval skia-eval
  (define (quick-render-pict width height draw)
    (with-skia ([surface (make-surface width height)])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.7)))))


;; Draw a coordinate guide as documentation material. The guide represents the
;; 800 by 500 drawing rectangle, but it is not part of the Moonlight scene.
(void
 (interaction-eval
  #:eval skia-eval
  (define (quick-coordinate-grid-pict width height)
    (define left 70)
    (define top 45)
    (define right 45)
    (define bottom 60)
    (define diagram-width (+ left width right))
    (define diagram-height (+ top height bottom))
    (define x0 left)
    (define y0 top)
    (define x1 (+ x0 width))
    (define y1 (+ y0 height))
    (with-skia ([surface
                 (make-surface diagram-width diagram-height
                               #:background "#F7F8FB")]
                [grid-paint
                 (make-paint #:color "#D8DEE9"
                             #:style 'stroke
                             #:stroke-width 1)]
                [border-paint
                 (make-paint #:color "#344054"
                             #:style 'stroke
                             #:stroke-width 2)]
                [label-paint
                 (make-paint #:color "#344054")]
                [point-paint
                 (make-paint #:color "#B54747")]
                [font (make-font #:size 16)]
                [small-font (make-font #:size 14)])
      (define canvas (surface-canvas surface))
      (define moon-x (+ x0 650))
      (define moon-y (+ y0 90))
      (for ([x (in-range 0 (add1 width) 100)])
        (define screen-x (+ x0 x))
        (draw-line canvas screen-x y0 screen-x y1 grid-paint)
        (draw-simple-text canvas
                          (number->string x)
                          (- screen-x 10)
                          (- y0 12)
                          small-font
                          label-paint))
      (for ([y (in-range 0 (add1 height) 100)])
        (define screen-y (+ y0 y))
        (draw-line canvas x0 screen-y x1 screen-y grid-paint)
        (draw-simple-text canvas
                          (number->string y)
                          (- x0 42)
                          (+ screen-y 5)
                          small-font
                          label-paint))
      (draw-rect canvas x0 y0 width height border-paint)
      (draw-simple-text canvas "x" (+ x1 20) (+ y0 5) font label-paint)
      (draw-simple-text canvas "y" (- x0 5) (+ y1 35) font label-paint)
      (draw-circle canvas moon-x moon-y 6 point-paint)
      (draw-simple-text canvas
                        "(650, 90)"
                        (+ moon-x 12)
                        (- moon-y 8)
                        small-font
                        point-paint)
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.62)))))

(define-syntax-rule (skia-interaction expression ...)
  (interaction #:eval skia-eval expression ...))

(define-syntax-rule (skia-interaction-eval expression ...)
  (interaction-eval #:eval skia-eval expression ...))

(define-syntax-rule (skia-racketmod+eval expression ...)
  (racketmod+eval #:eval skia-eval expression ...))

(define-syntax-rule (skia-racketblock+eval expression ...)
  (racketblock+eval #:eval skia-eval expression ...))

(define-syntax-rule (skia-def+int expression ...)
  (def+int #:eval skia-eval expression ...))

(define-syntax-rule (skia-image expression)
  (interaction-eval-show #:eval skia-eval expression))
