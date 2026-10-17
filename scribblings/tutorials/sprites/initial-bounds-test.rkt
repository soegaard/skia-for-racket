#lang racket/base

;;;
;;; Initial Bounds Test
;;;

;; Checks Sprites tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit (only-in racket/list take) "model.rkt")

;;;
;;; Regression Checks
;;;

(module+ test
  ;; Every smaller initial world is a prefix of the 2000-ball world.

  ; maximum-world : ball-world?
  ;   Builds the largest supported initial ball world for bounds checks.
  (define maximum-world (make-ball-world 2000))

  ; all-balls : list?
  ;   Retains the maximum world's ordered ball list to check all shorter prefixes.
  (define all-balls (ball-world-balls maximum-world))
  ;; The default layout keeps its original exact coordinates.
  (for ([sprite (in-list (take all-balls 30))] [index (in-naturals)])
    (check-equal? (ball-x sprite) (+ 60 (modulo (* index 137) 680)))
    (check-equal? (ball-y sprite) (+ 104 (modulo (* index 89) 320))))
  (for ([count (in-range 1 2001)])
    (define world (make-ball-world count))
    (check-equal? (ball-world-ticks world) 0)
    (check-equal? (ball-world-balls world) (take all-balls count)))
  (for ([count '(30 321 1000 2000)])
    (define world (make-ball-world count))
    (for ([sprite (in-list (ball-world-balls world))])
      (define radius (* 24 (ball-scale sprite)))
      (check-true (<= (+ 18 radius) (ball-x sprite) (- scene-width 18 radius)))
      (check-true (<= (+ 78 radius) (ball-y sprite) (- scene-height 18 radius))))))
