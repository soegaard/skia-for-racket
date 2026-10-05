#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../private/geometry-completion-util.rkt" "../private/check.rkt"
         "../private/types.rkt" "../matrix.rkt" "../output-policy.rkt"
         (only-in (submod "../private/audit-trace.rkt" testing)
                  uses put-slot! features after-native!))
(provide geometry-completion-pure-tests)
(define (bad f) (check-exn exn:fail:contract? f))
(define geometry-completion-pure-tests
  (test-suite
   "0.67 pure geometry domains and paint provenance"
   (test-case "finite scalar rejects NaN and infinities"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0 1e100))])
       (bad (lambda () (geometry-float 'test v)))))
   (test-case "positive means positive after C-float rounding"
     (bad (lambda () (geometry-positive 'test 1e-100)))
     (check-equal? (geometry-positive 'test 2) 2.0))
   (test-case "nonnegative accepts zero but not negatives"
     (check-equal? (geometry-nonnegative 'test 0) 0.0)
     (bad (lambda () (geometry-nonnegative 'test -1))))
   (test-case "rect start indices are bounded without modulo"
     (for ([i (in-range 4)]) (check-equal? (geometry-start-index 'test i 4) i))
     (for ([i (in-list '(-1 4 1.0 #f))]) (bad (lambda () (geometry-start-index 'test i 4)))))
   (test-case "rrect has eight possible starts"
     (check-equal? (geometry-start-index 'test 7 8) 7)
     (bad (lambda () (geometry-start-index 'test 8 8))))
   (test-case "point list snapshots a mutable input"
     (define v (vector (vector 1 2) (vector 3 4)))
     (define out (geometry-point-list 'test v))
     (vector-set! (vector-ref v 0) 0 99)
     (check-equal? out '((1.0 2.0) (3.0 4.0))))
   (test-case "point shape and count checks"
     (bad (lambda () (geometry-point-list 'test '((0 0 1)))))
     (bad (lambda () (geometry-point-list 'test '((0 0)) 2))))
   (test-case "point buffer budget precedes construction"
     (parameterize ([current-skia-byte-limit 7])
       (bad (lambda () (geometry-point-list 'test '((0 0)))))))
   (test-case "singular affine matrix is allowed for path geometry"
     (define m (geometry-matrix 'test (make-matrix 0 0 0 1 0 0)))
     (check-equal? (sk-matrix-xx m) 0.0)
     (check-equal? (sk-matrix-p2 m) 1.0))
   (test-case "matrix uses row-major nine-float layout"
     (define m (geometry-matrix 'test (make-matrix 1 2 3 4 5 6)))
     (check-equal? (list (sk-matrix-xx m) (sk-matrix-xy m) (sk-matrix-x0 m)
                         (sk-matrix-yx m) (sk-matrix-yy m) (sk-matrix-y0 m))
                   '(1.0 3.0 5.0 2.0 4.0 6.0)))
   (test-case "matrix input type checked"
     (bad (lambda () (geometry-matrix 'test '(1 0 0 1 0 0)))))
   (test-case "conic capacity is two times quadratic count plus one"
     (define-values (ps w capacity) (geometry-conic-parameters 'test '(0 0) '(1 1) '(2 0) 1 3))
     (check-equal? capacity 17) (check-equal? w 1.0) (check-equal? (length ps) 3))
   (test-case "conic subdivision and weights are explicit domains"
     (for ([power (in-list '(-1 6 1.0 #f))])
       (bad (lambda () (geometry-conic-parameters 'test '(0 0) '(1 1) '(2 0) 1 power))))
     (for ([w (in-list '(0 -1 1e-100))])
       (bad (lambda () (geometry-conic-parameters 'test '(0 0) '(1 1) '(2 0) w 2)))))
   (test-case "conic buffer obeys byte limit"
     (parameterize ([current-skia-byte-limit 32])
       (bad (lambda () (geometry-conic-parameters 'test '(0 0) '(1 1) '(2 0) 1 5)))))
   (test-case "operation sequence is ordered and copied"
     (check-equal? (geometry-operation-list 'test '#((union a) (difference b)))
                   '((union a) (difference b))))
   (test-case "empty operation sequence is representable"
     (check-equal? (geometry-operation-list 'test '()) '()))
   (test-case "unknown operations cannot reach native code"
     (bad (lambda () (geometry-operation-list 'test '((replace a)))))
     (bad (lambda () (geometry-operation-list 'test '((union a extra))))))
   (test-case "operation count is bounded before path references"
     (parameterize ([current-path-operation-limit 1])
       (bad (lambda () (geometry-operation-list 'test '((union a) (union b)))))))
   (test-case "invalid operation limit rejected"
     (for ([v (in-list '(0 -1 #t 1.0 2147483648))])
       (bad (lambda () (current-path-operation-limit v)))))
   (test-case "span endpoints and row stay inside region coordinate range"
     (check-equal? (call-with-values (lambda () (geometry-span-range 'test 2 0 10)) list) '(2 0 10))
     (bad (lambda () (geometry-span-range 'test 0 3 2)))
     (bad (lambda () (geometry-span-range 'test 2147483647 0 1))))
   (test-case "empty span interval is allowed"
     (check-equal? (call-with-values (lambda () (geometry-span-range 'test 0 2 2)) list) '(0 2 2)))
   (test-case "dither is explicit conservative document policy"
     (for ([b (in-list '(pdf svg))])
       (check-eq? (output-capability-status (output-capability-for b 'dither)) 'needs-raster)))
   (test-case "dither setter and reset update detached provenance"
     (define h (gensym 'paint)) (define ptr (gensym 'native))
     (parameterize ([uses (list (cons h ptr))])
       (put-slot! h 'shader '(linear-gradient))
       (after-native! 'sk_paint_set_dither (list ptr #t))
       (check-not-false (memq 'dither (features h)))
       (after-native! 'sk_paint_set_dither (list ptr #f))
       (check-false (memq 'dither (features h)))
       (check-not-false (memq 'linear-gradient (features h)))
       (after-native! 'sk_paint_reset (list ptr))
       (check-equal? (features h) '())))))
(module+ main (exit (if (zero? (run-tests geometry-completion-pure-tests)) 0 1)))
