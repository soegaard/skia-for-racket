#lang racket

(require skia)

(provide scene-width scene-height
         scene-background orbit-position draw-scene)

(define scene-width 760)
(define scene-height 440)
(define scene-background "#0A172A")

;; These paints are ordinary Skia resources, reused across all animation frames.
(define grid-paint
  (make-paint #:color "#162D43" #:style 'stroke #:stroke-width 1))
(define wide-orbit-paint
  (make-paint #:color "#436780" #:style 'stroke #:stroke-width 1.6))
(define tall-orbit-paint
  (make-paint #:color "#31536C" #:style 'stroke #:stroke-width 1.5))
(define highlight-paint (make-paint #:color "#F7FCFF"))
(define title-paint (make-paint #:color "#E7F2FB"))
(define subtitle-paint (make-paint #:color "#9AB9D0"))
(define title-font (make-font #:size 23))
(define detail-font (make-font #:size 13))

(define (disc-paints red green blue)
  (list (make-paint #:color (rgba red green blue 34))
        (make-paint #:color (rgba red green blue 77))
        (make-paint #:color (rgba red green blue 255))))

(define center-paints (disc-paints 243 182 95))
(define blue-paints (disc-paints 65 200 233))
(define violet-paints (disc-paints 177 138 232))

(define (orbit-position center-x center-y radius-x radius-y angle)
  (values (+ center-x (* radius-x (cos angle)))
          (+ center-y (* radius-y (sin angle)))))

(define (draw-background canvas width height)
  (canvas-clear! canvas scene-background)
  (for ([x (in-range 28 width 44)])
    (draw-line canvas x 0 x height grid-paint))
  (for ([y (in-range 24 height 44)])
    (draw-line canvas 0 y width y grid-paint)))

(define (draw-orbits canvas x y scale)
  (draw-oval canvas
             (- x (* 245 scale)) (- y (* 117 scale))
             (* 490 scale) (* 234 scale)
             wide-orbit-paint)
  (draw-oval canvas
             (- x (* 132 scale)) (- y (* 175 scale))
             (* 264 scale) (* 350 scale)
             tall-orbit-paint))

(define (draw-disc canvas x y radius paints)
  (draw-circle canvas x y (* 2 radius) (first paints))
  (draw-circle canvas x y (* 1.4 radius) (second paints))
  (draw-circle canvas x y radius (third paints))
  (draw-circle canvas x y (* 0.30 radius) highlight-paint))

(define (draw-scene canvas seconds width height)
  (define scale (min (/ width scene-width)
                     (/ height scene-height)))
  (define center-x (/ width 2.0))
  (define center-y (/ height 2.0))
  (define-values (blue-x blue-y)
    (orbit-position center-x center-y
                    (* 245 scale) (* 117 scale)
                    (* 0.85 seconds)))
  (define-values (violet-x violet-y)
    (orbit-position center-x center-y
                    (* 132 scale) (* 175 scale)
                    (+ 1.4 (* -1.15 seconds))))

  (draw-background canvas width height)
  (draw-orbits canvas center-x center-y scale)
  (draw-disc canvas center-x center-y (* 32 scale) center-paints)
  (draw-disc canvas blue-x blue-y (* 20 scale) blue-paints)
  (draw-disc canvas violet-x violet-y (* 16 scale) violet-paints)

  (draw-simple-text canvas "ORBITING LIGHTS" 30 45 title-font title-paint)
  (draw-simple-text canvas "Two orbits. One drawing function." 31 80
                    detail-font subtitle-paint)
  (draw-simple-text canvas "SKIA / ANIMATION STUDY" 30 (- height 22)
                    detail-font subtitle-paint))

(module+ test
  (require rackunit)
  (define-values (x0 y0) (orbit-position 100 200 40 25 0))
  (check-= x0 140 1e-10)
  (check-= y0 200 1e-10)
  (define-values (x1 y1) (orbit-position 100 200 40 25 (/ pi 2)))
  (check-= x1 100 1e-10)
  (check-= y1 225 1e-10))
