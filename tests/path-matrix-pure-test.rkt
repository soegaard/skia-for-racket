#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe racket/math "../main.rkt" "../private/types.rkt")
(provide path-matrix-pure-tests)
(define (mapped m x y) (call-with-values (lambda () (matrix-map-point m x y)) list))
(define (close-point got expected)
  (for ([a (in-list got)] [b (in-list expected)]) (check-= a b 0.0001)))

(define path-matrix-pure-tests
  (test-suite
   "Affine matrix values and path/matrix validation"
   (test-case "identity is an immutable value, not a resource"
     (check-true (matrix? matrix-identity))
     (check-false (skia-resource? matrix-identity))
     (check-equal? (make-matrix) matrix-identity))
   (test-case "six-coefficient order is xx yx xy yy x0 y0"
     (define m (make-matrix 2 3 5 7 11 13))
     (check-equal? (matrix->vector m) '#(2.0 3.0 5.0 7.0 11.0 13.0))
     (check-equal? (mapped m 17 19) '(140.0 197.0)))
   (test-case "vector constructor copies; readback is immutable"
     (define v (vector 1 2 3 4 5 6))
     (define m (vector->matrix v))
     (vector-set! v 4 999)
     (check-equal? (matrix-x0 m) 5.0)
     (check-true (immutable? (matrix->vector m)))
     (check-exn exn:fail? (lambda () (vector-set! (matrix->vector m) 0 8))))
   (test-case "invalid matrix coefficients are rejected"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0 1e100 'x #f 1+2i))])
       (check-exn exn:fail:contract? (lambda () (make-matrix v)))))
   (test-case "vector arity and coefficient types are checked"
     (for ([v (in-list (list '#() '#(1 2) '(1 0 0 1 0 0) '#(1 0 0 1 0 no)))])
       (check-exn exn:fail:contract? (lambda () (vector->matrix v)))))
   (test-case "translation"
     (check-equal? (mapped (matrix-translate 10 -8) 2 3) '(12.0 -5.0)))
   (test-case "scaling includes reflection and singular collapse"
     (check-equal? (mapped (matrix-scale 3) 2 4) '(6.0 12.0))
     (check-equal? (mapped (matrix-scale -2 0) 2 4) '(-4.0 0.0)))
   (test-case "positive rotations agree with x-right y-down canvases"
     (check-equal? (mapped (matrix-rotate-degrees 90) 2 3) '(-3.0 2.0))
     (close-point (mapped (matrix-rotate (/ pi 2)) 2 3) '(-3 2))
     (check-equal? (matrix-rotate-degrees 360) matrix-identity))
   (test-case "negative degrees and exact quarter turns"
     (check-equal? (mapped (matrix-rotate-degrees -90) 2 3) '(3.0 -2.0))
     (check-equal? (mapped (matrix-rotate-degrees 180) 2 3) '(-2.0 -3.0)))
   (test-case "shear coefficients are factors, not angles"
     (check-equal? (mapped (matrix-skew 2 3) 4 5) '(14.0 17.0)))
   (test-case "composition applies rightmost transform first"
     (define t (matrix-translate 10 20))
     (define s (matrix-scale 2 3))
     (check-equal? (mapped (matrix-compose t s) 1 1) '(12.0 23.0))
     (check-equal? (mapped (matrix-compose s t) 1 1) '(22.0 63.0)))
   (test-case "zero and one argument composition"
     (check-equal? (matrix-compose) matrix-identity)
     (define m (make-matrix 2 3 5 7 11 13))
     (check-equal? (matrix-compose m) m))
   (test-case "inverse maps back through a nontrivial affine transform"
     (define m (make-matrix 2 1 -1 3 7 -2))
     (define inverse (matrix-invert m))
     (check-true (matrix? inverse))
     (define p (mapped m 10 -20))
     (close-point (mapped inverse (car p) (cadr p)) '(10 -20)))
   (test-case "singular inverse is false"
     (check-false (matrix-invert (matrix-scale 0 1)))
     (check-false (matrix-invert (make-matrix 1 2 2 4))))
   (test-case "unrepresentable inverse is false"
     (check-false (matrix-invert (make-matrix 1e-40 0 0 1))))
   (test-case "vectors ignore the translation"
     (check-equal? (call-with-values
                    (lambda () (matrix-map-vector (make-matrix 2 0 0 3 99 88) 4 5)) list)
                   '(8.0 15.0)))
   (test-case "rectangle mapping returns axis-aligned bounds"
     (check-equal? (call-with-values
                    (lambda () (matrix-map-rect (matrix-rotate-degrees 90) 2 3 4 5)) list)
                   '(-8.0 2.0 5.0 4.0)))
   (test-case "zero rectangles accepted, negative extents rejected"
     (check-equal? (call-with-values
                    (lambda () (matrix-map-rect matrix-identity 2 3 0 0)) list)
                   '(2.0 3.0 0.0 0.0))
     (check-exn exn:fail? (lambda () (matrix-map-rect matrix-identity 0 0 -1 3))))
   (test-case "arithmetic overflow does not produce native infinities"
     (check-exn exn:fail? (lambda () (matrix-compose (matrix-scale 1e30) (matrix-scale 1e30))))
     (check-exn exn:fail? (lambda () (matrix-map-point (matrix-scale 1e30) 1e30 0))))
   (test-case "coefficients are rounded to the C-float representation"
     (check-equal? (matrix-xx (make-matrix 1/10))
                   (floating-point-bytes->real (real->floating-point-bytes 1/10 4 #f) #f)))
   (test-case "wrong resources fail before native loading"
     (for ([thunk (in-list
                   (list (lambda () (path-segments 'not-path))
                         (lambda () (in-path-segments 'not-path))
                         (lambda () (path-contours 'not-path))
                         (lambda () (path->commands 'not-path))
                         (lambda () (path-transform 'not-path matrix-identity))
                         (lambda () (path-transform! 'not-path matrix-identity))
                         (lambda () (path-measure-matrix 'not-measure 0))
                         (lambda () (shader-with-local-matrix 'not-shader matrix-identity))))])
       (check-exn exn:fail:contract? thunk)))
   (test-case "canvas matrix arguments are checked"
     (check-exn exn:fail:contract? (lambda () (canvas-transform 'not-canvas)))
     (check-exn exn:fail:contract? (lambda () (canvas-set-transform! 'not-canvas 'not-matrix)))
     (check-exn exn:fail:contract? (lambda () (canvas-concat! 'not-canvas matrix-identity))))
   (test-case "M33 native layout has nine row-major floats"
     (check-equal? (ctype-sizeof _sk-matrix) 36)
     (define m (make-sk-matrix 1.0 2.0 3.0 4.0 5.0 6.0 0.0 0.0 1.0))
     (check-equal? (ptr-ref m _float 2) 3.0)
     (check-equal? (ptr-ref m _float 5) 6.0))
   (test-case "M44 storage is 64 bytes, translation at words 12 and 13"
     (check-equal? (ctype-sizeof _sk-m44) 64)
     (define m (make-sk-m44 1.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0
                            0.0 0.0 1.0 0.0 17.0 23.0 0.0 1.0))
     (check-equal? (ptr-ref m _float 12) 17.0)
     (check-equal? (ptr-ref m _float 13) 23.0))))
(module+ test (run-tests path-matrix-pure-tests))
