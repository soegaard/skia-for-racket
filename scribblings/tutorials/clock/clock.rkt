#lang racket

;;;
;;; Clock
;;;

;; Draws a clock by composing local coordinate systems and canvas transforms.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

;;;
;;; Drawing Data and Helpers
;;;

; size : exact-integer?
;;   Specifies size in the drawing's local coordinate units.
(define size 600)
; center : real?
;;   Places the clock's origin at the midpoint of its square drawing area.
(define center (/ size 2))
; face-radius : exact-integer?
;;   Specifies face radius in the drawing's local coordinate units.
(define face-radius 220)

; background-color : string?
;;   Specifies the background color color used by this drawing.
(define background-color "#E9EDF2")
; face-color : string?
;;   Specifies the face color color used by this drawing.
(define face-color "#F6F1E7")
; ink-color : string?
;;   Specifies the ink color color used by this drawing.
(define ink-color "#293241")
; second-color : string?
;;   Specifies the second color color used by this drawing.
(define second-color "#C94F3D")

; draw-clock-face : canvas? -> void?
;;   Draws the clock face component in the current canvas coordinate system.
(define (draw-clock-face canvas)
  (define fill (make-paint #:color face-color))
  (define rim (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 5))
  (draw-circle canvas 0 0 face-radius fill)
  (draw-circle canvas 0 0 face-radius rim))

; draw-hour-tick : canvas? paint? -> void?
;;   Draws the hour tick component in the current canvas coordinate system.
(define (draw-hour-tick canvas paint)
  (draw-line canvas 0 -184 0 -210 paint))

; draw-minute-tick : canvas? paint? -> void?
;;   Draws the minute tick component in the current canvas coordinate system.
(define (draw-minute-tick canvas paint)
  (draw-line canvas 0 -198 0 -210 paint))

; draw-ticks : canvas? -> void?
;;   Draws the ticks component in the current canvas coordinate system.
(define (draw-ticks canvas)
  (define hour-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 6
    #:cap 'round))
  (define minute-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 2
    #:cap 'round))
  (for ([minute (in-range 60)])
    (with-canvas-state canvas
      (canvas-rotate! canvas (* minute 6))
      (if (zero? (remainder minute 5))
          (draw-hour-tick canvas hour-paint)
          (draw-minute-tick canvas minute-paint)))))

; draw-hand : canvas? real? real? paint? -> void?
;;   Draws the hand component in the current canvas coordinate system.
(define (draw-hand canvas length tail paint)
  (draw-line canvas 0 tail 0 (- length) paint))

; draw-hands : canvas? real? real? real? -> void?
;;   Draws the hands component in the current canvas coordinate system.
(define (draw-hands canvas hour minute second)
  (define hour-angle
    (+ (* (modulo hour 12) 30)
       (* minute 1/2)
       (/ second 120)))
  (define minute-angle
    (+ (* minute 6)
       (/ second 10)))
  (define second-angle (* second 6))
  (define hour-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 11
    #:cap 'round))
  (define minute-paint (make-paint #:color ink-color
    #:style 'stroke
    #:stroke-width 7
    #:cap 'round))
  (define second-paint (make-paint #:color second-color
    #:style 'stroke
    #:stroke-width 3
    #:cap 'round))
  (with-canvas-state canvas
    (canvas-rotate! canvas hour-angle)
    (draw-hand canvas 120 16 hour-paint))
  (with-canvas-state canvas
    (canvas-rotate! canvas minute-angle)
    (draw-hand canvas 165 20 minute-paint))
  (with-canvas-state canvas
    (canvas-rotate! canvas second-angle)
    (draw-hand canvas 185 28 second-paint)))

; draw-center-pin : canvas? -> void?
;;   Draws the center pin component in the current canvas coordinate system.
(define (draw-center-pin canvas)
  (define outer (make-paint #:color ink-color))
  (define inner (make-paint #:color second-color))
  (draw-circle canvas 0 0 11 outer)
  (draw-circle canvas 0 0 5 inner))

; draw-clock-at-origin : canvas? real? real? real? -> void?
;;   Draws the clock at origin component in the current canvas coordinate system.
(define (draw-clock-at-origin canvas hour minute second)
  (draw-clock-face canvas)
  (draw-ticks canvas)
  (draw-hands canvas hour minute second)
  (draw-center-pin canvas))

; draw-clock-at : canvas? real? real? real? real? real? real? -> void?
;;   Draws the clock at component in the current canvas coordinate system.
(define (draw-clock-at canvas x y scale hour minute second)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-clock-at-origin canvas hour minute second)))

; draw-clock : canvas? real? real? real? -> void?
;;   Draws the clock component in the current canvas coordinate system.
(define (draw-clock canvas hour minute second)
  (draw-clock-at canvas center center 1 hour minute second))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; surface : surface?
  ;;   Owns the raster drawing target used to produce the example's output.
  (define surface (make-surface size size
    #:background background-color))
  (draw-clock (surface-canvas surface) 10 10 30)
  (save-png surface "clock.png" #:exists 'replace))
