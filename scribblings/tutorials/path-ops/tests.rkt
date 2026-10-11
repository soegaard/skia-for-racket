#lang racket

(require rackunit "badge.rkt" skia)

(module+ test
  (define parts (make-badge-parts))
  (define a (hash-ref parts 'disk))
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
  (test-case "drawing the cutout leaves the center transparent"
    (with-skia ([surface (make-surface 320 320)] [paint (make-paint #:color "#23796F")])
      (draw-path (surface-canvas surface) (hash-ref parts 'badge) paint)
      (define pixels (surface->rgba-bytes surface))
      (check-equal? (bytes-ref pixels (+ (* 4 (+ 160 (* 320 160))) 3)) 0))))
