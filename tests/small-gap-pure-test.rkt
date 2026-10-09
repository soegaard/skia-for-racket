#lang racket/base
;; No native library is loaded: every public call here fails at its input gate.
(require rackunit rackunit/text-ui
         "../main.rkt"
         (only-in "../private/color-output-util.rkt" color-sequence))
(provide small-gap-pure-tests small-gap-pure-test-count)
(define I '(1 0 0 0 1 0 0 0 1))
(define (bad-input v)
  (check-exn exn:fail:contract? (lambda () (xyz-d50-invert v)))
  (check-exn exn:fail:contract? (lambda () (xyz-d50-concat v I)))
  (check-exn exn:fail:contract? (lambda () (xyz-d50-concat I v))))
(define (replace-first value) (cons value (cdr I)))
(define small-gap-pure-test-count 20)
(define small-gap-pure-tests
  (test-suite "small-gap pure contracts"
    (test-case "public helpers have exact ordinary arity"
      (check-equal? (procedure-arity xyz-d50-concat) 2)
      (check-equal? (procedure-arity xyz-d50-invert) 1))
    (test-case "helpers accept no keywords"
      (for ([proc (in-list (list xyz-d50-concat xyz-d50-invert))])
        (define-values (required allowed) (procedure-keywords proc))
        (check-equal? required '()) (check-equal? allowed '())))
    (test-case "empty matrices are not identities" (bad-input '()))
    (test-case "eight coefficients fail" (bad-input '(1 0 0 0 1 0 0 0)))
    (test-case "ten coefficients fail" (bad-input '(1 0 0 0 1 0 0 0 1 0)))
    (test-case "homogeneous 4 by 4 matrices are not XYZ matrices"
      (bad-input '#(1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1)))
    (test-case "nested rows are not a flat representation"
      (bad-input '((1 0 0) (0 1 0) (0 0 1))))
    (test-case "improper lists fail" (bad-input '(1 0 0 0 1 0 0 0 . 1)))
    (test-case "named gamut is not an implicit argument convention" (bad-input 'srgb))
    (test-case "strings and bytes fail" (bad-input "identity") (bad-input #"identity"))
    (test-case "booleans fail" (bad-input #f) (bad-input (replace-first #t)))
    (test-case "non-real coefficients fail" (bad-input (replace-first 1+2i)))
    (test-case "NaN is rejected before native loading" (bad-input (replace-first +nan.0)))
    (test-case "infinities are rejected before native loading"
      (bad-input (replace-first +inf.0)) (bad-input (replace-first -inf.0)))
    (test-case "finite but unrepresentable coefficients fail"
      (bad-input (replace-first 1e100)) (bad-input (replace-first -1e100)))
    (test-case "boundary copies mutable vectors"
      (define input (list->vector I))
      (define copy (color-sequence 'test input 9 "XYZ coefficients"))
      (vector-set! input 0 99)
      (check-true (immutable? copy)) (check-equal? (vector-ref copy 0) 1.0))
    (test-case "boundary uses native binary32 rounding"
      (define v (color-sequence 'test (replace-first (+ 1 (expt 2 -25))) 9 "XYZ coefficients"))
      (check-equal? (vector-ref v 0) 1.0))
    (test-case "arithmetic validation does not pre-reject singular matrices"
      (check-equal? (color-sequence 'test (make-vector 9 0) 9 "XYZ coefficients")
                    '#(0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)))
    (test-case "no-draw zero and invalid dimensions fail before native loading"
      (for ([pair (in-list '((0 1) (1 0) (0 0) (-1 1) (1 -1) (1/2 1) (1 1.0)
                             (32769 1) (2147483648 1)))])
        (check-exn exn:fail? (lambda () (call-with-nodraw-canvas (car pair) (cadr pair) void))))
      (parameterize ([current-skia-byte-limit 1])
        (check-exn exn:fail? (lambda () (call-with-nodraw-canvas 1 1 void)))))
    (test-case "no-draw callback contract is checked before native loading"
      (check-exn exn:fail:contract? (lambda () (call-with-nodraw-canvas 3 4 #f)))
      (check-exn exn:fail:contract? (lambda () (call-with-nodraw-canvas 3 4 (lambda () (void)))))
      (check-exn exn:fail:contract?
        (lambda () (call-with-nodraw-canvas 3 4 (lambda (c #:required k) (void))))))))
(module+ main
  (define failures (run-tests small-gap-pure-tests))
  (printf "small-gap-pure: ~a cases, ~a failures\n" small-gap-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
(module+ test
  (check-equal? (run-tests small-gap-pure-tests) 0))
