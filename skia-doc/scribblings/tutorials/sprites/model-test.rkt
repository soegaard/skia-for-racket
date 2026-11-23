#lang racket

;;;
;;; Sprites Model Test
;;;

;; Checks Sprites tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.

;;;
;;; Imports and Exports
;;;

(require rackunit "model.rkt" "../support/sprite-math.rkt")

;;;
;;; Regression Checks
;;;

(module+ test
  (test-case "initial simulation is reproducible"
    (check-equal? (make-ball-world 30) (make-ball-world 30)))
  (test-case "count is checked"
    (for ([count '(0 -1 2001 1.5 #f)])
      (check-exn exn:fail? (lambda () (make-ball-world count)))))
  (test-case "reflection keeps the overshoot"
    (check-equal? (call-with-values (lambda () (reflect-axis 9 4 0 10 1)) list) '(7 -4)))
  (test-case "reflection can cross several walls"
    (check-equal? (call-with-values (lambda () (reflect-axis 1 47 0 10 1)) list) '(8 47))
    (check-equal? (call-with-values (lambda () (reflect-axis 1 -47 0 10 1)) list) '(6 47)))
  (test-case "an exact wall hit points inward"
    (check-equal? (call-with-values (lambda () (reflect-axis 9 1 0 10 1)) list) '(10 -1))
    (check-equal? (call-with-values (lambda () (reflect-axis 1 -1 0 10 1)) list) '(0 1)))
  (test-case "movement never changes a sprite's atlas cell"
    (define world (make-ball-world 100))
    (define cells (map ball-cell (ball-world-balls world)))
    (step-balls! world 0.1 (lambda (_) #f))
    (check-equal? cells (map ball-cell (ball-world-balls world))))
  (test-case "all ball bounds survive a long run"
    (define world (make-ball-world 30))
    (for ([_ (in-range 1200)]) (step-balls! world fixed-step void))
    (for ([sprite (in-list (ball-world-balls world))])
      (define radius (* 24 (ball-scale sprite)))
      (check-true (<= (+ 18 radius) (ball-x sprite) (- scene-width 18 radius)))
      (check-true (<= (+ 78 radius) (ball-y sprite) (- scene-height 18 radius)))))
  (test-case "fixed input produces fixed simulation state"
    (define a (make-ball-world))
    (define b (make-ball-world))
    (for ([_ (in-range 120)])
      (step-balls! a fixed-step void)
      (step-balls! b fixed-step void))
    (check-equal? a b)))
