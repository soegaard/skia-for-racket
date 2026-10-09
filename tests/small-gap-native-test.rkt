#lang racket/base
;; Public-API numerical and native no-draw execution. Never substitute a mock
;; or count the presence of a source declaration as execution evidence.
(require racket/list rackunit rackunit/text-ui ffi/unsafe
         "../main.rkt" (only-in "../private/types.rkt" _sk-xyz))
(provide small-gap-native-tests small-gap-native-test-count)
(define I '#(1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0))
(define A '#(1 2 3 0 1 4 5 6 0))
(define D '#(2 0 0 0 3 0 0 0 4))
(define (near actual expected [epsilon 5e-6])
  (check-true (and (vector? actual) (= (vector-length actual) 9)))
  (when (and (vector? actual) (= (vector-length actual) 9))
    (for ([x (in-vector actual)] [y (in-vector expected)])
      (check-= x y (* epsilon (max 1 (abs y)))))))
;; Independent elementary oracle, not a call to the implementation under test.
(define (product a b)
  (for/vector ([index (in-range 9)])
    (define row (quotient index 3)) (define col (remainder index 3))
    (for/sum ([k (in-range 3)])
      (* (vector-ref a (+ (* row 3) k)) (vector-ref b (+ (* k 3) col))))))
(define small-gap-native-test-count 24)
(define small-gap-native-tests
  (test-suite "small-gap native acceptance"
    (test-case "existing native XYZ layout is 36 bytes" (check-equal? (ctype-sizeof _sk-xyz) 36))
    (test-case "left and right identity"
      (near (xyz-d50-concat I A) A) (near (xyz-d50-concat A I) A))
    (test-case "composition order is a times b, not b times a"
      (check-equal? (xyz-d50-concat A D) '#(2.0 6.0 12.0 0.0 3.0 16.0 10.0 18.0 0.0))
      (check-equal? (xyz-d50-concat D A) '#(2.0 4.0 6.0 0.0 3.0 12.0 20.0 24.0 0.0)))
    (test-case "dense nonsymmetric product agrees with independent oracle"
      (define b '#(2 -1 3 4 0 1 -2 5 7))
      (near (xyz-d50-concat A b) (product A b)))
    (test-case "list inputs yield immutable flat output"
      (define out (xyz-d50-concat (vector->list A) (vector->list D)))
      (check-true (immutable? out)) (check-equal? (vector-length out) 9)
      (check-exn exn:fail:contract? (lambda () (vector-set! out 0 7))))
    (test-case "inputs are not mutated and results do not alias them"
      (define a (list->vector (vector->list A)))
      (define b (list->vector (vector->list D)))
      (define out (xyz-d50-concat a b))
      (check-equal? a A) (check-equal? b D)
      (vector-set! a 0 99) (vector-set! b 0 99)
      (check-equal? out '#(2.0 6.0 12.0 0.0 3.0 16.0 10.0 18.0 0.0)))
    (test-case "singular matrix multiplication is permitted"
      (check-equal? (xyz-d50-concat (make-vector 9 0) A)
                    '#(0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)))
    (test-case "multiplication overflow is not published as a value"
      (check-exn #rx"nonfinite" (lambda () (xyz-d50-concat
        '#(1e30 0 0 0 1 0 0 0 1) '#(1e30 0 0 0 1 0 0 0 1)))))
    (test-case "identity inverse" (near (xyz-d50-invert I) I))
    (test-case "known inverse has correct row-major placement"
      (near (xyz-d50-invert A) '#(-24 18 5 20 -15 -4 -5 4 1)))
    (test-case "both inverse products approach identity"
      (define inverse (xyz-d50-invert A))
      (near (xyz-d50-concat A inverse) I) (near (xyz-d50-concat inverse A) I))
    (test-case "inverse result is detached and immutable"
      (define input (list->vector (vector->list A)))
      (define inverse (xyz-d50-invert input))
      (check-equal? input A) (check-true (immutable? inverse))
      (vector-set! input 0 99) (collect-garbage)
      (near inverse '#(-24 18 5 20 -15 -4 -5 4 1)))
    (test-case "zero and dependent rows produce false"
      (check-false (xyz-d50-invert (make-vector 9 0)))
      (check-false (xyz-d50-invert '#(1 2 3 2 4 6 0 0 1))))
    (test-case "singular after binary32 rounding produces false"
      (check-false (xyz-d50-invert (vector 1 1 0 1 (+ 1 (expt 2 -25)) 0 0 0 1))))
    (test-case "underflowed input and unrepresentable inverse produce false"
      (check-false (xyz-d50-invert '#(1e-50 0 0 0 1 0 0 0 1)))
      (check-false (xyz-d50-invert '#(1e-40 0 0 0 1 0 0 0 1))))
    (test-case "named gamut matrices compose with their inverses"
      (for ([name (in-list '(srgb adobe-rgb display-p3 rec2020 xyz))])
        (define gamut (named-xyz-d50 name))
        (define inverse (xyz-d50-invert gamut))
        (near (xyz-d50-concat inverse gamut) I)
        (near (xyz-d50-concat gamut inverse) I)))
    (test-case "linear-gamut basis conversion round trips"
      (define srgb (named-xyz-d50 'srgb))
      (define p3 (named-xyz-d50 'display-p3))
      (define forward (xyz-d50-concat (xyz-d50-invert p3) srgb))
      (define reverse (xyz-d50-concat (xyz-d50-invert srgb) p3))
      (near forward (product (xyz-d50-invert p3) srgb))
      (near (xyz-d50-concat reverse forward) I))
    (test-case "composed gamut feeds the existing RGB color-space API"
      (define srgb (named-xyz-d50 'srgb))
      (with-skia ([space (make-rgb-color-space 'linear (xyz-d50-concat I srgb))])
        (near (color-space-xyz-d50 space) srgb)))
    (test-case "color-space closure cannot expire a detached matrix"
      (define detached
        (with-skia ([space (make-rgb-color-space 'linear 'srgb)])
          (color-space-xyz-d50 space)))
      (collect-garbage)
      (near (xyz-d50-concat detached (xyz-d50-invert detached)) I))
    (test-case "no-draw canvas has explicit non-surface backend"
      (call-with-nodraw-canvas 32 24
        (lambda (c)
          (check-true (canvas? c)) (check-false (surface? c))
          (check-eq? (canvas-execution-backend c) 'nodraw)
          (check-exn exn:fail:contract? (lambda () (surface->rgba-bytes c)))
          (check-exn exn:fail:contract? (lambda () (surface->png-bytes c))))))
    (test-case "no-draw authoring preserves scoped canvas state"
      (call-with-nodraw-canvas 32 24
        (lambda (c)
          (define before (canvas-save-count c))
          (with-canvas-state c
            (canvas-translate! c 4 5)
            (check-equal? (canvas-save-count c) (add1 before))
            (canvas-clear! c (rgb 17 34 51))
            (with-skia ([p (make-paint #:color (rgb 229 41 53))])
              (draw-rect c 2 3 11 7 p)))
          (check-equal? (canvas-save-count c) before))))
    (test-case "no-draw scope preserves multiple values"
      (check-equal? (call-with-values
        (lambda () (call-with-nodraw-canvas 2 3 (lambda (_) (values 'done 7)))) list)
        '(done 7)))
    (test-case "escaped no-draw canvas expires after normal return"
      (define c (call-with-nodraw-canvas 32 24 values))
      (check-true (skia-closed? c))
      (check-exn exn:fail? (lambda () (canvas-clear! c (rgb 0 0 0)))))
    (test-case "exception cleanup expires the no-draw borrow"
      (define escaped #f)
      (check-exn #rx"intentional-body-error"
        (lambda () (call-with-nodraw-canvas 32 24
          (lambda (c) (set! escaped c) (error 'test "intentional-body-error")))))
      (check-true (skia-closed? escaped))
      (check-exn exn:fail? (lambda () (canvas-save! escaped)))
      (call-with-nodraw-canvas 1 1 (lambda (c) (check-equal? (canvas-save-count c) 1))))))
(module+ main
  (skia-check!)
  (define failures (run-tests small-gap-native-tests))
  (printf "small-gap-native: ~a cases, ~a failures\n" small-gap-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
(module+ test
  (skia-check!)
  (check-equal? (run-tests small-gap-native-tests) 0))
