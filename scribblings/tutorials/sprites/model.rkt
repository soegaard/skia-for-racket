#lang racket

;;;
;;; Sprites Model
;;;

;; Simulates reproducible bouncing balls without drawing or GPU resources.
;; This native-free tutorial model is shared by its window/controller and pure regression tests.


;; Plain Racket data. The simulation has no GPU resources.

;;;
;;; Imports and Exports
;;;

(provide (struct-out ball) (struct-out ball-world)
         scene-width scene-height make-ball-world reflect-axis step-balls!)

;;;
;;; Ball World State
;;;

; scene-width : exact-integer?
;   Specifies scene width in the drawing's local coordinate units.
(define scene-width 800)

; scene-height : exact-integer?
;   Specifies scene height in the drawing's local coordinate units.
(define scene-height 480)
(struct ball (x y vx vy angle spin cell scale) #:transparent)
;; x, y: real center coordinates in the fixed scene coordinate system.
;; vx, vy: real velocities in scene units per second.
;; angle, spin: real rotation in degrees and angular velocity in degrees per second.
;; cell: exact index from 0 through 7 into the ball atlas.
;; scale: positive real artwork scale; the collision radius is 24 times this value.
;; Records are immutable. The world replaces records after a step, preserving list order.
;; Initial centers fit the collision bounds including the scaled radius; no field owns a GPU
;; object.
(struct ball-world (balls ticks) #:mutable #:transparent)
;; balls: mutable ordered list of immutable ball records; order also determines atlas drawing
;; order.
;; ticks: mutable exact nonnegative count of completed simulation updates.
;; make-ball-world accepts 1 through 2000 balls, and stepping preserves that count.
;; The world contains only Racket data and does not retain atlas or renderer resources.

; make-ball-world : [exact-nonnegative-integer?] -> ball-world?
;   Creates a reproducible world with 1 through 2000 balls inside their collision bounds.
(define (make-ball-world [count 30])
  (unless (and (exact-positive-integer? count) (<= count 2000))
    (raise-argument-error 'make-ball-world "integer from 1 through 2000" count))
  ;; Keep an already-valid position unchanged, including its exactness.
  (define (fit-position position low high)
    (cond
      [(< position low) low]
      [(> position high) high]
      [else position]))
  ;; Reproducible arithmetic gives each ball a different position and velocity.
  (ball-world
   (for/list ([index (in-range count)])
     (define scale (+ 0.65 (* 0.1 (modulo index 7))))
     (define radius (* 24 scale))
     ;; Preserve the original layout where it already fits the collision envelope.
     (define x
       (fit-position (+ 60 (modulo (* index 137) 680))
                     (+ 18 radius) (- scene-width 18 radius)))
     (define y
       (fit-position (+ 104 (modulo (* index 89) 320))
                     (+ 78 radius) (- scene-height 18 radius)))
     (ball x y
           (* (if (even? index) 1 -1) (+ 72 (modulo (* index 31) 110)))
           (* (if (zero? (modulo index 3)) -1 1) (+ 55 (modulo (* index 47) 90)))
           (modulo (* index 37) 360)
           (- (modulo (* index 71) 150) 75)
           (modulo index 8)
           scale))
   0))

;;;
;;; Fixed-Step Motion and Reflection
;;;

;; Reflect the unfolded position into the interval. This also handles an update
;; that crosses more than one wall; clamping would lose that travel distance.


; reflect-axis : real? real? real? real? real? -> (values real? real?)
;   Reflects traveled distance into an interval, including crossings of multiple walls.
(define (reflect-axis position velocity low high seconds)
  (define span (- high low))
  (define travel (+ (- position low) (* velocity seconds)))
  (define cycle (- travel (* (* 2 span) (floor (/ travel (* 2 span))))))
  (cond
    [(zero? cycle) (values low (abs velocity))]
    [(= cycle span) (values high (- (abs velocity)))]
    [(< cycle span) (values (+ low cycle) velocity)]
    [else (values (- high (- cycle span)) (- velocity))]))

; step-balls! : ball-world? real? procedure? -> void?
;   Advances the ball list and simulation tick without allocating native drawing resources.
(define (step-balls! world seconds _held?)
  (set-ball-world-balls!
   world
   (for/list ([sprite (in-list (ball-world-balls world))])
     (define radius (* 24 (ball-scale sprite)))
     (define-values (x vx)
       (reflect-axis (ball-x sprite) (ball-vx sprite)
                     (+ 18 radius) (- scene-width 18 radius) seconds))
     (define-values (y vy)
       (reflect-axis (ball-y sprite) (ball-vy sprite)
                     (+ 78 radius) (- scene-height 18 radius) seconds))
     (struct-copy ball sprite [x x] [y y] [vx vx] [vy vy]
                  [angle (+ (ball-angle sprite) (* seconds (ball-spin sprite)))])))
  (set-ball-world-ticks! world (add1 (ball-world-ticks world))))
