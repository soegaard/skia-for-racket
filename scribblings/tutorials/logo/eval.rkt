#lang racket/base

(require scribble/eval)

(provide logo-racketblock+eval
         logo-racketmod+eval
         logo-interaction
         logo-interaction-eval
         logo-def+int
         logo-image)

(define logo-eval (make-base-eval))

(void
 (interaction-eval
  #:eval logo-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-render-pict width height draw)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F0E7")])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
       (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

;; These figures compare the small option sets used in the tutorial.
(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-style-pict)
    (define width 720)
    (define height 230)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F6F0")]
                [font (make-font #:size 18)]
                [label-paint (make-paint #:color "#293241")])
      (define canvas (surface-canvas surface))
      (define shape
        '((move 0 -70)
          (line 58 45)
          (line -58 45)
          (close)))
      (for ([x '(120 360 600)]
            [style '(fill stroke stroke-and-fill)]
            [label '("'fill" "'stroke" "'stroke-and-fill")])
        (with-skia ([path (make-path shape)]
                    [paint (make-paint #:color "#246B5A"
                                       #:style style
                                       #:stroke-width 14
                                       #:join 'round)])
          (with-canvas-state canvas
            (canvas-translate! canvas x 130)
            (draw-path canvas path paint)))
        (draw-simple-text canvas label (- x 55) 215 font label-paint))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-join-pict)
    (define width 720)
    (define height 240)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F6F0")]
                [font (make-font #:size 18)]
                [label-paint (make-paint #:color "#293241")])
      (define canvas (surface-canvas surface))
      (define corner
        '((move -62 62)
          (line 0 -62)
          (line 62 62)))
      (for ([x '(120 360 600)]
            [join '(miter round bevel)]
            [label '("'miter" "'round" "'bevel")])
        (with-skia ([path (make-path corner)]
                    [paint (make-paint #:color "#246B5A"
                                       #:style 'stroke
                                       #:stroke-width 28
                                       #:join join
                                       #:cap 'butt)])
          (with-canvas-state canvas
            (canvas-translate! canvas x 125)
            (draw-path canvas path paint)))
        (draw-simple-text canvas label (- x 34) 225 font label-paint))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-fill-rule-pict)
    (define width 780)
    (define height 270)
    (define same-direction
      '((move 20 25)
        (line 180 25)
        (line 180 185)
        (line 20 185)
        (close)
        (move 65 70)
        (line 135 70)
        (line 135 140)
        (line 65 140)
        (close)))
    (define reversed-inner
      '((move 20 25)
        (line 180 25)
        (line 180 185)
        (line 20 185)
        (close)
        (move 65 70)
        (line 65 140)
        (line 135 140)
        (line 135 70)
        (close)))
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F6F0")]
                [font (make-font #:size 16)]
                [label-paint (make-paint #:color "#293241")]
                [fill (make-paint #:color "#246B5A")]
                [outline (make-paint #:color "#173B35"
                                     #:style 'stroke
                                     #:stroke-width 2)])
      (define canvas (surface-canvas surface))
      (define (panel x commands rule line1 line2)
        (with-skia ([path (make-path commands #:fill-rule rule)])
          (with-canvas-state canvas
            (canvas-translate! canvas x 15)
            (draw-path canvas path fill)
            (draw-path canvas path outline)))
        (draw-simple-text canvas line1 (+ x 25) 225 font label-paint)
        (draw-simple-text canvas line2 (+ x 25) 247 font label-paint))
      (panel 20 same-direction 'winding "'winding" "same direction")
      (panel 290 reversed-inner 'winding "'winding" "inner reversed")
      (panel 560 same-direction 'even-odd "'even-odd" "same direction")
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

;; This figure is documentation material. It shows the control point for the
;; first quadratic segment used by the quadratic logo.
(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-quadratic-control-pict)
    (define width 500)
    (define height 500)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F6F0")]
                [guide (make-paint #:color "#AEB6C1"
                                   #:style 'stroke
                                   #:stroke-width 2)]
                [curve-paint (make-paint #:color "#246B5A"
                                         #:style 'stroke
                                         #:stroke-width 7
                                         #:cap 'round)]
                [point-paint (make-paint #:color "#C8553D")]
                [label-paint (make-paint #:color "#293241")]
                [font (make-font #:size 16)]
                [curve
                 (make-path
                  '((move 250 50)
                    (quad 415 100 390 250)))])
      (define canvas (surface-canvas surface))
      (draw-line canvas 250 50 415 100 guide)
      (draw-line canvas 415 100 390 250 guide)
      (draw-path canvas curve curve-paint)
      (for ([point '((250 50) (415 100) (390 250))])
        (draw-circle canvas (first point) (second point) 7 point-paint))
      (draw-simple-text canvas "start" 188 43 font label-paint)
      (draw-simple-text canvas "control" 376 88 font label-paint)
      (draw-simple-text canvas "end" 405 266 font label-paint)
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

;; This figure is documentation material. It shows the control points for the
;; first cubic segment used by the final outer contour.
(void
 (interaction-eval
  #:eval logo-eval
  (define (logo-cubic-control-pict)
    (define width 500)
    (define height 500)
    (with-skia ([surface (make-surface width height
                                      #:background "#F8F6F0")]
                [guide (make-paint #:color "#AEB6C1"
                                   #:style 'stroke
                                   #:stroke-width 2)]
                [curve-paint (make-paint #:color "#246B5A"
                                         #:style 'stroke
                                         #:stroke-width 7
                                         #:cap 'round)]
                [point-paint (make-paint #:color "#C8553D")]
                [label-paint (make-paint #:color "#293241")]
                [font (make-font #:size 16)]
                [curve
                 (make-path
                  '((move 250 50)
                    (cubic 405 85 440 280 250 440)))])
      (define canvas (surface-canvas surface))
      (draw-line canvas 250 50 405 85 guide)
      (draw-line canvas 405 85 440 280 guide)
      (draw-line canvas 440 280 250 440 guide)
      (draw-path canvas curve curve-paint)
      (for ([point '((250 50) (405 85) (440 280) (250 440))])
        (draw-circle canvas (first point) (second point) 7 point-paint))
      (draw-simple-text canvas "start" 188 43 font label-paint)
      (draw-simple-text canvas "control 1" 362 72 font label-paint)
      (draw-simple-text canvas "control 2" 385 305 font label-paint)
      (draw-simple-text canvas "end" 268 449 font label-paint)
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

(define-syntax-rule (logo-interaction expression ...)
  (interaction #:eval logo-eval expression ...))

(define-syntax-rule (logo-interaction-eval expression ...)
  (interaction-eval #:eval logo-eval expression ...))

(define-syntax-rule (logo-racketmod+eval expression ...)
  (racketmod+eval #:eval logo-eval expression ...))

(define-syntax-rule (logo-racketblock+eval expression ...)
  (racketblock+eval #:eval logo-eval expression ...))

(define-syntax-rule (logo-def+int expression ...)
  (def+int #:eval logo-eval expression ...))

(define-syntax-rule (logo-image expression)
  (interaction-eval-show #:eval logo-eval expression))
