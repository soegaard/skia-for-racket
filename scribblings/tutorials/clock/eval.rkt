#lang racket/base

(require scribble/eval)

(provide clock-racketblock+eval
         clock-racketmod+eval
         clock-interaction
         clock-interaction-eval
         clock-def+int
         clock-image)

(define clock-eval (make-base-eval))

(void
 (interaction-eval
  #:eval clock-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval clock-eval
  (define (clock-render-pict width height draw)
    (with-skia ([surface (make-surface width height
                                      #:background "#E9EDF2")])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.62)))))

;; This diagram is documentation material. It shows the surface coordinate
;; system and the translated local coordinate system used by the clock.
(void
 (interaction-eval
  #:eval clock-eval
  (define (clock-coordinate-pict)
    (define width 600)
    (define height 600)
    (define center-x 300)
    (define center-y 300)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F9FB")]
                [grid (make-paint #:color "#E1E5EA"
                                  #:style 'stroke
                                  #:stroke-width 1)]
                [surface-axis (make-paint #:color "#697386"
                                          #:style 'stroke
                                          #:stroke-width 2
                                          #:cap 'round)]
                [local-axis (make-paint #:color "#C94F3D"
                                        #:style 'stroke
                                        #:stroke-width 3
                                        #:cap 'round)]
                [surface-text (make-paint #:color "#4B5565")]
                [local-text (make-paint #:color "#A43D30")]
                [surface-font (make-font #:size 15)]
                [local-font (make-font #:size 16)])
      (define canvas (surface-canvas surface))
      (for ([x (in-range 100 600 100)])
        (draw-line canvas x 0 x height grid))
      (for ([y (in-range 100 600 100)])
        (draw-line canvas 0 y width y grid))
      (draw-line canvas 0 0 565 0 surface-axis)
      (draw-line canvas 0 0 0 565 surface-axis)
      (draw-simple-text canvas "surface (0, 0)" 12 24
                        surface-font surface-text)
      (draw-simple-text canvas "+x" 566 18 surface-font surface-text)
      (draw-simple-text canvas "+y" 10 585 surface-font surface-text)
      (draw-line canvas 55 center-y 545 center-y local-axis)
      (draw-line canvas center-x 55 center-x 545 local-axis)
      (draw-circle canvas center-x center-y 6 local-text)
      (draw-simple-text canvas "local (0, 0)" 314 290
                        local-font local-text)
      (draw-simple-text canvas "surface (300, 300)" 314 312
                        surface-font surface-text)
      (draw-simple-text canvas "+x" 548 292 local-font local-text)
      (draw-simple-text canvas "-x" 30 292 local-font local-text)
      (draw-simple-text canvas "+y" 308 565 local-font local-text)
      (draw-simple-text canvas "-y" 308 48 local-font local-text)
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.62)))))



;; This figure summarizes the transform sequence used throughout the tutorial.
(void
 (interaction-eval
  #:eval clock-eval
  (define (clock-transform-flow-pict)
    (define width 900)
    (define height 250)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F9FB")]
                [frame (make-paint #:color "#D7DDE5"
                                   #:style 'stroke
                                   #:stroke-width 2)]
                [axis (make-paint #:color "#697386"
                                  #:style 'stroke
                                  #:stroke-width 2
                                  #:cap 'round)]
                [accent (make-paint #:color "#C94F3D"
                                    #:style 'stroke
                                    #:stroke-width 3
                                    #:cap 'round)]
                [dot (make-paint #:color "#C94F3D")]
                [text-paint (make-paint #:color "#293241")]
                [font (make-font #:size 16)])
      (define canvas (surface-canvas surface))
      (define (panel x label)
        (draw-rounded-rect canvas x 18 260 214 12 12 frame)
        (draw-simple-text canvas label (+ x 16) 48 font text-paint))
      (panel 10 "1. Surface coordinates")
      (panel 320 "2. Translate to center")
      (panel 630 "3. Rotate, then draw")

      (draw-line canvas 55 78 235 78 axis)
      (draw-line canvas 55 78 55 202 axis)
      (draw-circle canvas 55 78 5 dot)

      (draw-line canvas 365 78 545 78 axis)
      (draw-line canvas 365 78 365 202 axis)
      (with-canvas-state canvas
        (canvas-translate! canvas 450 145)
        (draw-line canvas -82 0 82 0 accent)
        (draw-line canvas 0 -65 0 65 accent)
        (draw-circle canvas 0 0 5 dot))

      (draw-line canvas 675 78 855 78 axis)
      (draw-line canvas 675 78 675 202 axis)
      (with-canvas-state canvas
        (canvas-translate! canvas 760 145)
        (canvas-rotate! canvas 45)
        (draw-line canvas -82 0 82 0 accent)
        (draw-line canvas 0 -65 0 65 accent)
        (draw-line canvas 0 14 0 -70 accent)
        (draw-circle canvas 0 0 5 dot))

      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.70)))))

(define-syntax-rule (clock-interaction expression ...)
  (interaction #:eval clock-eval expression ...))

(define-syntax-rule (clock-interaction-eval expression ...)
  (interaction-eval #:eval clock-eval expression ...))

(define-syntax-rule (clock-racketmod+eval expression ...)
  (racketmod+eval #:eval clock-eval expression ...))

(define-syntax-rule (clock-racketblock+eval expression ...)
  (racketblock+eval #:eval clock-eval expression ...))

(define-syntax-rule (clock-def+int expression ...)
  (def+int #:eval clock-eval expression ...))

(define-syntax-rule (clock-image expression)
  (interaction-eval-show #:eval clock-eval expression))
