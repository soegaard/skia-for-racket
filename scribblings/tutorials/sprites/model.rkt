#lang racket

;; Plain Racket data. The simulation has no GPU resources.
(provide (struct-out ball) (struct-out ball-world)
         scene-width scene-height make-ball-world reflect-axis step-balls!)

(define scene-width 800)
(define scene-height 480)
(struct ball (x y vx vy angle spin cell scale) #:transparent)
(struct ball-world (balls ticks) #:mutable #:transparent)

(define (make-ball-world [count 30])
  (unless (and (exact-positive-integer? count) (<= count 2000))
    (raise-argument-error 'make-ball-world "integer from 1 through 2000" count))
  ;; Reproducible arithmetic gives each ball a different position and velocity.
  (ball-world
   (for/list ([index (in-range count)])
     (ball (+ 60 (modulo (* index 137) 680))
           (+ 104 (modulo (* index 89) 320))
           (* (if (even? index) 1 -1) (+ 72 (modulo (* index 31) 110)))
           (* (if (zero? (modulo index 3)) -1 1) (+ 55 (modulo (* index 47) 90)))
           (modulo (* index 37) 360)
           (- (modulo (* index 71) 150) 75)
           (modulo index 8)
           (+ 0.65 (* 0.1 (modulo index 7)))))
   0))

;; Reflect the unfolded position into the interval. This also handles an update
;; that crosses more than one wall; clamping would lose that travel distance.
(define (reflect-axis position velocity low high seconds)
  (define span (- high low))
  (define travel (+ (- position low) (* velocity seconds)))
  (define cycle (- travel (* (* 2 span) (floor (/ travel (* 2 span))))))
  (cond
    [(zero? cycle) (values low (abs velocity))]
    [(= cycle span) (values high (- (abs velocity)))]
    [(< cycle span) (values (+ low cycle) velocity)]
    [else (values (- high (- cycle span)) (- velocity))]))

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
