#lang racket/base

;; Pure R2 acceptance: imports only the public affine module, never native Skia.
(require rackunit racket/list skia/matrix)

(define (results thunk) (call-with-values thunk list))

(module+ test
  (test-case "six-coefficient order, rounding, and detached input"
    (define coefficients (vector 2 0 0 3 10 20))
    (define matrix (vector->matrix coefficients))
    (vector-set! coefficients 0 99)
    (check-equal? (matrix->vector matrix) #(2.0 0.0 0.0 3.0 10.0 20.0))
    (check-true (immutable? (matrix->vector matrix)))
    (check-false (matrix? coefficients))
    (check-equal? (matrix-xx (make-matrix 1/10))
                  (floating-point-bytes->real (real->floating-point-bytes 1/10 4 #f) #f))
    (check-exn exn:fail:contract? (lambda () (vector->matrix #(1 0 0 1 0)))))
  (test-case "composition order and zero-argument identity"
    (define translation (matrix-translate 10 20))
    (define scaling (matrix-scale 2))
    (check-equal? (matrix-compose) matrix-identity)
    (check-equal? (results (lambda ()
                            (matrix-map-point (matrix-compose translation scaling) 3 4)))
                  '(16.0 28.0))
    (check-equal? (results (lambda ()
                            (matrix-map-point (matrix-compose scaling translation) 3 4)))
                  '(26.0 48.0)))
  (test-case "points include translation; vectors do not"
    (define translation (matrix-translate 10 20))
    (check-equal? (results (lambda () (matrix-map-point translation 3 4))) '(13.0 24.0))
    (check-equal? (results (lambda () (matrix-map-vector translation 3 4))) '(3.0 4.0)))
  (test-case "quarter turns and axis-aligned bounds"
    (check-equal? (matrix-rotate-degrees 360) matrix-identity)
    (check-equal? (matrix-rotate-degrees -90) (matrix-rotate-degrees 270))
    (check-equal? (results (lambda () (matrix-map-point (matrix-rotate-degrees 90) 3 2)))
                  '(-2.0 3.0))
    (check-equal? (results (lambda () (matrix-map-rect (matrix-rotate-degrees 90) 0 0 20 10)))
                  '(-10.0 0.0 10.0 20.0))
    (check-exn exn:fail:contract?
               (lambda () (matrix-map-rect matrix-identity 0 0 -1 1))))
  (test-case "singular and unrepresentable inverses"
    (check-false (matrix-invert (matrix-scale 0)))
    (check-false (matrix-invert (matrix-scale 1e-40)))
    (check-equal? (matrix-invert (matrix-translate 10 20)) (matrix-translate -10 -20))
    (check-equal? (matrix-compose (matrix-scale 2) (matrix-invert (matrix-scale 2)))
                  matrix-identity))
  (test-case "finite float domain"
    (for ([bad (in-list (list +inf.0 -inf.0 +nan.0 1e100))])
      (check-exn exn:fail:contract? (lambda () (make-matrix bad))))))
