#lang racket

(require skia)

(define size 600)
(define center (/ size 2))
(define face-radius 220)

(define background-color "#E9EDF2")
(define face-color "#F6F1E7")
(define ink-color "#293241")
(define second-color "#C94F3D")

(define (draw-clock-face canvas)
  (with-skia ([fill (make-paint #:color face-color)]
              [rim (make-paint #:color ink-color
                               #:style 'stroke
                               #:stroke-width 5)])
    (draw-circle canvas 0 0 face-radius fill)
    (draw-circle canvas 0 0 face-radius rim)))

(define (draw-hour-tick canvas paint)
  (draw-line canvas 0 -184 0 -210 paint))

(define (draw-minute-tick canvas paint)
  (draw-line canvas 0 -198 0 -210 paint))

(define (draw-ticks canvas)
  (with-skia ([hour-paint (make-paint #:color ink-color
                                      #:style 'stroke
                                      #:stroke-width 6
                                      #:cap 'round)]
              [minute-paint (make-paint #:color ink-color
                                        #:style 'stroke
                                        #:stroke-width 2
                                        #:cap 'round)])
    (for ([minute (in-range 60)])
      (with-canvas-state canvas
        (canvas-rotate! canvas (* minute 6))
        (if (zero? (remainder minute 5))
            (draw-hour-tick canvas hour-paint)
            (draw-minute-tick canvas minute-paint))))))

(define (draw-hand canvas length tail paint)
  (draw-line canvas 0 tail 0 (- length) paint))

(define (draw-hands canvas hour minute second)
  (define hour-angle
    (+ (* (modulo hour 12) 30)
       (* minute 1/2)
       (/ second 120)))
  (define minute-angle
    (+ (* minute 6)
       (/ second 10)))
  (define second-angle (* second 6))
  (with-skia ([hour-paint (make-paint #:color ink-color
                                      #:style 'stroke
                                      #:stroke-width 11
                                      #:cap 'round)]
              [minute-paint (make-paint #:color ink-color
                                        #:style 'stroke
                                        #:stroke-width 7
                                        #:cap 'round)]
              [second-paint (make-paint #:color second-color
                                        #:style 'stroke
                                        #:stroke-width 3
                                        #:cap 'round)])
    (with-canvas-state canvas
      (canvas-rotate! canvas hour-angle)
      (draw-hand canvas 120 16 hour-paint))
    (with-canvas-state canvas
      (canvas-rotate! canvas minute-angle)
      (draw-hand canvas 165 20 minute-paint))
    (with-canvas-state canvas
      (canvas-rotate! canvas second-angle)
      (draw-hand canvas 185 28 second-paint))))

(define (draw-center-pin canvas)
  (with-skia ([outer (make-paint #:color ink-color)]
              [inner (make-paint #:color second-color)])
    (draw-circle canvas 0 0 11 outer)
    (draw-circle canvas 0 0 5 inner)))

(define (draw-clock-at-origin canvas hour minute second)
  (draw-clock-face canvas)
  (draw-ticks canvas)
  (draw-hands canvas hour minute second)
  (draw-center-pin canvas))

(define (draw-clock-at canvas x y scale hour minute second)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-clock-at-origin canvas hour minute second)))

(define (draw-clock canvas hour minute second)
  (draw-clock-at canvas center center 1 hour minute second))

(module+ main
  (with-skia ([surface (make-surface size size
                                    #:background background-color)])
    (draw-clock (surface-canvas surface) 10 10 30)
    (save-png surface "clock.png" #:exists 'replace)))
