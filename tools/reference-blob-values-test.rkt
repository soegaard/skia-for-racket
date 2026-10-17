#lang racket/base

;;;
;;; Reference Blob Values Test
;;;

;; Checks copied atlas transforms, anchor placement, rotation direction, and zero-scale geometry.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Pure public transform values: no font lookup, native allocation, or GPU context.
(require rackunit skia/geometry-primitives)


;;;
;;; Diagnostic Operations
;;;

; map-point : atlas-transform? real? real? -> (values real? real?)
;   Applies scale/rotation and translation coefficients to an anchor for transformed-blob
;   assertions.
(define (map-point transform x y)
  (define cs (atlas-transform-coefficients transform))
  (values (+ (* (vector-ref cs 0) x) (- (* (vector-ref cs 1) y)) (vector-ref cs 2))
          (+ (* (vector-ref cs 1) x) (* (vector-ref cs 0) y) (vector-ref cs 3))))

(module+ test
  (test-case "atlas values copy anchors and expose immutable coefficients"
    (define anchor (vector 3 4))
    (define transform (make-atlas-transform 10 20 #:scale 2 #:anchor anchor))
    (check-true (atlas-transform? transform))
    (check-false (atlas-transform? '#(2 0 4 12)))
    (check-true (immutable? (atlas-transform-coefficients transform)))
    (vector-set! anchor 0 999)
    (check-equal? (atlas-transform-coefficients transform) '#(2.0 0.0 4.0 12.0))
    (check-equal? (call-with-values (lambda () (map-point transform 3 4)) list) '(10.0 20.0)))
  (test-case "positive rotation is clockwise in downward-positive coordinates"
    (define transform (make-atlas-transform 10 20 #:rotation 90))
    (define-values (x y) (map-point transform 2 0))
    (check-= x 10 0.000001)
    (check-= y 22 0.000001))
  (test-case "zero scale is accepted and collapses all points"
    (define transform (make-atlas-transform 7 11 #:scale 0 #:anchor '(5 9)))
    (check-equal? (call-with-values (lambda () (map-point transform 120 340)) list)
                  '(7.0 11.0)))
  (test-case "invalid scale, coordinates, and anchor shape are rejected"
    (check-exn exn:fail? (lambda () (make-atlas-transform 0 0 #:scale -1)))
    (check-exn exn:fail? (lambda () (make-atlas-transform +inf.0 0)))
    (check-exn exn:fail? (lambda () (make-atlas-transform 0 0 #:rotation +nan.0)))
    (check-exn exn:fail? (lambda () (make-atlas-transform 0 0 #:anchor '(0))))))
