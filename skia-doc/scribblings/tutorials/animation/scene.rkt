#lang racket

;;;
;;; Animation Scene
;;;

;; Draws orbiting lights from explicit time and dimensions, independently of window events.
;; This shared tutorial drawing is used by the runnable program, documentation figures, and
;; checks.


;;;
;;; Imports and Exports
;;;

(require skia)

(provide scene-width scene-height
         scene-background orbit-position draw-scene)

;;;
;;; Scene Palette and Drawing Resources
;;;

; scene-width : exact-integer?
;   Specifies scene width in the drawing's local coordinate units.
(define scene-width 760)

; scene-height : exact-integer?
;   Specifies scene height in the drawing's local coordinate units.
(define scene-height 440)

; scene-background : string?
;   Specifies the scene background color used by this drawing.
(define scene-background "#0A172A")

;; These paints are ordinary Skia resources, reused across all animation frames.

; grid-paint : paint?
;   Retains the grid paint for repeated drawing calls.
(define grid-paint
  (make-paint #:color "#162D43" #:style 'stroke #:stroke-width 1))

; wide-orbit-paint : paint?
;   Retains the wide orbit paint for repeated drawing calls.
(define wide-orbit-paint
  (make-paint #:color "#436780" #:style 'stroke #:stroke-width 1.6))

; tall-orbit-paint : paint?
;   Retains the tall orbit paint for repeated drawing calls.
(define tall-orbit-paint
  (make-paint #:color "#31536C" #:style 'stroke #:stroke-width 1.5))

; highlight-paint : paint?
;   Retains the highlight paint for repeated drawing calls.
(define highlight-paint (make-paint #:color "#F7FCFF"))

; title-paint : paint?
;   Retains the title paint for repeated drawing calls.
(define title-paint (make-paint #:color "#E7F2FB"))

; subtitle-paint : paint?
;   Retains the subtitle paint for repeated drawing calls.
(define subtitle-paint (make-paint #:color "#9AB9D0"))

; title-font : font?
;   Selects the title font used by the scene.
(define title-font (make-font #:size 23))

; detail-font : font?
;   Selects the detail font used by the scene.
(define detail-font (make-font #:size 13))

; disc-paints : real? real? real? -> list?
;   Creates the layered paints used to draw a glowing colored disc.
(define (disc-paints red green blue)
  (list (make-paint #:color (rgba red green blue 34))
        (make-paint #:color (rgba red green blue 77))
        (make-paint #:color (rgba red green blue 255))))

; center-paints : list?
;   Keeps the layered paint set for the central glowing disc.
(define center-paints (disc-paints 243 182 95))

; blue-paints : list?
;   Keeps the layered paint set for the blue orbiting disc.
(define blue-paints (disc-paints 65 200 233))

; violet-paints : list?
;   Keeps the layered paint set for the violet orbiting disc.
(define violet-paints (disc-paints 177 138 232))

;;;
;;; Orbit Geometry and Drawing
;;;

; orbit-position : real? real? real? real? real? -> (values real? real?)
;   Returns x and y on the selected ellipse at the supplied angle.
(define (orbit-position center-x center-y radius-x radius-y angle)
  (values (+ center-x (* radius-x (cos angle)))
          (+ center-y (* radius-y (sin angle)))))

; draw-background : canvas? real? real? -> void?
;   Draws the background component in the current canvas coordinate system.
(define (draw-background canvas width height)
  (canvas-clear! canvas scene-background)
  (for ([x (in-range 28 width 44)])
    (draw-line canvas x 0 x height grid-paint))
  (for ([y (in-range 24 height 44)])
    (draw-line canvas 0 y width y grid-paint)))

; draw-orbits : canvas? real? real? real? -> void?
;   Draws the orbits component in the current canvas coordinate system.
(define (draw-orbits canvas x y scale)
  (draw-oval canvas
             (- x (* 245 scale)) (- y (* 117 scale))
             (* 490 scale) (* 234 scale)
             wide-orbit-paint)
  (draw-oval canvas
             (- x (* 132 scale)) (- y (* 175 scale))
             (* 264 scale) (* 350 scale)
             tall-orbit-paint))

; draw-disc : canvas? real? real? real? any/c -> void?
;   Draws the disc component in the current canvas coordinate system.
(define (draw-disc canvas x y radius paints)
  (draw-circle canvas x y (* 2 radius) (first paints))
  (draw-circle canvas x y (* 1.4 radius) (second paints))
  (draw-circle canvas x y radius (third paints))
  (draw-circle canvas x y (* 0.30 radius) highlight-paint))

; draw-scene : canvas? real? real? real? -> void?
;   Draws the scene component in the current canvas coordinate system.
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

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)

  ; (x0 y0) : (values real? real?)
  ;   Receives the initial orbit position for the arithmetic regression check.
  (define-values (x0 y0) (orbit-position 100 200 40 25 0))
  (check-= x0 140 1e-10)
  (check-= y0 200 1e-10)

  ; (x1 y1) : (values real? real?)
  ;   Receives the comparison orbit position for the arithmetic regression check.
  (define-values (x1 y1) (orbit-position 100 200 40 25 (/ pi 2)))
  (check-= x1 100 1e-10)
  (check-= y1 225 1e-10))
