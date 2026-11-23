#lang racket

;;;
;;; Path Ops Tests
;;;

;; Checks Path Ops tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit "badge.rkt" skia)

;;;
;;; Regression Checks
;;;

(module+ test

  ; parts : hash?
  ;   Keeps the named intermediate paths used to explain the badge construction.
  (define parts (make-badge-parts))

  ; a : path?
  ;   Selects the disk operand for path-operation regression tests.
  (define a (hash-ref parts 'disk))

  ; b : path?
  ;   Selects the cross operand for path-operation regression tests.
  (define b (hash-ref parts 'cross))
  (test-case "union, intersection, difference, and xor obey set membership"
    (define both (path-intersect a b))
    (define difference (path-difference a b))
    (define exclusive (path-xor a b))
    ;; Samples avoid the operand boundaries.
    (for* ([x '(25 80 113 160 207 240 295)] [y '(25 80 113 160 207 240 295)])
      (define inside-a (path-contains? a x y))
      (define inside-b (path-contains? b x y))
      (check-equal? (path-contains? (hash-ref parts 'joined) x y) (or inside-a inside-b))
      (check-equal? (path-contains? both x y) (and inside-a inside-b))
      (check-equal? (path-contains? difference x y) (and inside-a (not inside-b)))
      (check-equal? (path-contains? exclusive x y) (not (equal? inside-a inside-b)))))
  (test-case "the center is a hole, not a patch of background paint"
    (check-false (path-contains? (hash-ref parts 'badge) 160 160))
    (check-true (path-contains? (hash-ref parts 'badge) 160 80)))
  (test-case "the xor of nested circles is a rim"
    (define rim (hash-ref parts 'rim))
    (check-false (path-contains? rim 160 160))
    (check-true (path-contains? rim 274 160))
    (check-false (path-contains? rim 285 160)))
  (test-case "difference is ordered"
    (define reverse (path-difference (hash-ref parts 'hole) (hash-ref parts 'trimmed)))
    (check-false (path-contains? reverse 160 80))
    (check-true (path-contains? (hash-ref parts 'cutout) 160 80)))
  (test-case "simplification preserves filled membership"
    (define simple (path-simplify b))
    (for* ([x '(25 80 160 240 295)] [y '(25 80 160 240 295)])
      (check-equal? (path-contains? simple x y) (path-contains? b x y))))
  (test-case "a result is independent of the operand wrappers"
    (define left (circle-path 80))
    (define right (cross-path))
    (define result (path-union left right))
    (path-reset! left)
    (skia-close! right)
    (check-true (path-contains? result 160 160))
    (skia-close! result)
    (skia-close! left))
  (test-case "the same hole reveals either receiving background"
    (for ([background (list (rgb 23 54 101) (rgb 246 214 132))])
      (with-skia ([surface (make-surface 320 320 #:background background)])
        (define before (surface->rgba-bytes surface))
        (draw-shape (surface-canvas surface) (hash-ref parts 'badge))
        (define after (surface->rgba-bytes surface))
        (define offset (* 4 (+ 160 (* 320 160))))
        (check-equal? (subbytes before offset (+ offset 4))
                      (subbytes after offset (+ offset 4))))))
  (test-case "overlapping-circle xor keeps both outer sides but subtraction keeps only A"
    (with-skia ([left (make-path)] [right (make-path)])
      (path-add-circle! left 80 100 62)
      (path-add-circle! right 140 100 62)
      (with-skia ([difference (path-difference left right)]
                  [exclusive (path-xor left right)])
        (check-true (path-contains? difference 40 100))
        (check-false (path-contains? difference 180 100))
        (check-true (path-contains? exclusive 40 100))
        (check-true (path-contains? exclusive 180 100))
        (check-false (path-contains? difference 110 100))
        (check-false (path-contains? exclusive 110 100)))))
  (test-case "drawing the cutout leaves the center transparent"
    (with-skia ([surface (make-surface 320 320)] [paint (make-paint #:color "#23796F")])
      (draw-path (surface-canvas surface) (hash-ref parts 'badge) paint)
      (define pixels (surface->rgba-bytes surface))
      (check-equal? (bytes-ref pixels (+ (* 4 (+ 160 (* 320 160))) 3)) 0))))
