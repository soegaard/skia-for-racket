#lang racket/base
(require racket/cmdline "../main.rkt")

;; Visual smoke test for the 0.5 vector layer: dash/corner/discrete/trim path
;; effects, path measurement/segments/tangents, and boolean path operations.
(define (render-path-effects filename)
  (with-skia ([s (make-surface 1000 700 #:background "#F3F5F9")]
              [card (make-paint #:color 'white)]
              [border (make-paint #:color "#D8DFEA" #:style 'stroke #:stroke-width 2)]
              [ink (make-paint #:color "#223149")]
              [faint (make-paint #:color "#D4DDEA" #:style 'stroke #:stroke-width 2)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#16A598")]
              [orange (make-paint #:color "#F38C42")]
              [orange-stroke (make-paint #:color "#F38C42" #:style 'stroke
                                         #:stroke-width 4 #:cap 'round)]
              [purple (make-paint #:color "#8A63D2")]
              [font (make-font #:size 20)]
              [small-font (make-font #:size 14)])
    (define c (surface-canvas s))
    (for* ([x '(30 355 680)] [y '(30 365)])
      (draw-rounded-rect c x y 290 305 18 18 card)
      (draw-rounded-rect c x y 290 305 18 18 border))

    ;; 1: dashes on a cubic curve.
    (draw-simple-text c "dash" 50 68 font ink)
    (with-skia ([curve (make-path '((move 55 225)
                                    (cubic 90 90 220 310 295 105)))]
                [effect (make-dash-path-effect '(14 8) 3)]
                [paint (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width 7 #:cap 'round
                                   #:path-effect effect)])
      (draw-path c curve faint)
      (draw-path c curve paint))

    ;; 2: corner rounding on a deliberately sharp polyline.
    (draw-simple-text c "corner" 375 68 font ink)
    (with-skia ([zig (make-path '((move 380 250)
                                  (line 420 105)
                                  (line 485 235)
                                  (line 545 105)
                                  (line 615 250)))]
                [effect (make-corner-path-effect 20)]
                [paint (make-paint #:color "#16A598" #:style 'stroke
                                   #:stroke-width 9 #:cap 'round
                                   #:join 'miter #:path-effect effect)])
      (draw-path c zig faint)
      (draw-path c zig paint))

    ;; 3: seeded discrete path effect.
    (draw-simple-text c "discrete" 700 68 font ink)
    (with-skia ([curve (make-path '((move 705 225)
                                    (cubic 750 100 865 295 945 115)))]
                [effect (make-discrete-path-effect 12 5 2026)]
                [paint (make-paint #:color "#F38C42" #:style 'stroke
                                   #:stroke-width 5 #:cap 'round
                                   #:path-effect effect)])
      (draw-path c curve faint)
      (draw-path c curve paint))

    ;; 4: trim effect on a closed circular contour.
    (draw-simple-text c "trim" 50 403 font ink)
    (with-skia ([circle (make-path)]
                [effect (make-trim-path-effect 0.10 0.72)]
                [paint (make-paint #:color "#8A63D2" #:style 'stroke
                                   #:stroke-width 11 #:cap 'round
                                   #:path-effect effect)])
      (path-add-circle! circle 175 525 88)
      (draw-path c circle faint)
      (draw-path c circle paint))

    ;; 5: measured cubic, extracted segment, position, and tangent.
    (draw-simple-text c "measure / segment / tangent" 375 403 font ink)
    (with-skia ([curve (make-path '((move 380 570)
                                    (cubic 415 430 560 650 620 455)))]
                [measure (make-path-measure curve)]
                [segment-paint (make-paint #:color "#326DE6" #:style 'stroke
                                           #:stroke-width 7 #:cap 'round)])
      (draw-path c curve faint)
      (define len (path-measure-length measure))
      (with-skia ([segment (path-measure-segment measure (* len 0.22) (* len 0.67))])
        (draw-path c segment segment-paint))
      (define-values (x y tx ty)
        (path-measure-position+tangent measure (* len 0.56)))
      (when x
        (draw-circle c x y 7 orange)
        (draw-line c x y (+ x (* 42 tx)) (+ y (* 42 ty)) orange-stroke)))

    ;; 6: union, intersection, and xor on overlapping circles.
    (draw-simple-text c "boolean path ops" 700 403 font ink)
    (define (boolean-swatch y op label paint)
      (with-skia ([a (make-path)] [b (make-path)])
        (path-add-circle! a 785 y 42)
        (path-add-circle! b 835 y 42)
        (with-skia ([result (path-op a b op)])
          (draw-path c result paint)
          (draw-path c a faint)
          (draw-path c b faint)
          (draw-simple-text c label 875 (+ y 5) small-font ink))))
    (boolean-swatch 465 'union "union" teal)
    (boolean-swatch 535 'intersect "intersect" purple)
    (boolean-swatch 605 'xor "xor" orange)

    (save-png s filename)))

(module+ main
  (define filename
    (command-line #:program "path-effects.rkt"
                  #:args ([output "path-effects.png"])
                  output))
  (render-path-effects filename)
  (printf "Wrote ~a\n" filename))
