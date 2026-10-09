#lang racket/base
;; 0.78a: executable evidence for the EXISTING Racket color conversion contract.
;; No native color conversion, binary32 bit parity, color management or render
;; execution is asserted by these tests. No libSkiaSharp dependency is needed.
(require rackunit rackunit/text-ui "../color.rkt" "../color4f.rkt")
(provide release-scope-pure-tests release-scope-pure-test-count)
(define release-scope-pure-test-count 16)
(define (roundtrip c) (color->argb (color4f->rgba (color->color4f c))))
(define release-scope-pure-tests
  (test-suite "Release-scope Color4f equivalent (pure Racket)"
    (test-case "all red bytes roundtrip"
      (for ([n (in-range 256)]) (check-equal? (roundtrip (rgba n 23 117 191)) (color->argb (rgba n 23 117 191)))))
    (test-case "all green bytes roundtrip"
      (for ([n (in-range 256)]) (check-equal? (roundtrip (rgba 17 n 97 163)) (color->argb (rgba 17 n 97 163)))))
    (test-case "all blue bytes roundtrip"
      (for ([n (in-range 256)]) (check-equal? (roundtrip (rgba 53 79 n 211)) (color->argb (rgba 53 79 n 211)))))
    (test-case "all alpha bytes roundtrip without premultiplication"
      (for ([n (in-range 256)]) (check-equal? (roundtrip (rgba 199 73 41 n)) (color->argb (rgba 199 73 41 n)))))
    (test-case "packed ARGB order"
      (check-equal? (roundtrip #x80402010) #x80402010))
    (test-case "transparent RGB is preserved"
      (check-equal? (roundtrip #x00123456) #x00123456))
    (test-case "CSS string channel order remains different from packed integer"
      (check-equal? (roundtrip "#12345678") #x78123456))
    (test-case "named input color"
      (check-equal? (roundtrip 'red) #xffff0000))
    (test-case "channel normalization"
      (define c (color->color4f (rgba 0 255 128 64)))
      (check-= (color4f-red c) 0.0 0.0)
      (check-= (color4f-green c) 1.0 0.0)
      (check-= (color4f-blue c) (/ 128.0 255.0) 1e-15)
      (check-= (color4f-alpha c) (/ 64.0 255.0) 1e-15))
    (test-case "half channel quantizes using the explicit Racket contract"
      (check-equal? (color4f->rgba (make-color4f 1/2 0 1 1/2)) (rgba 128 0 255 128)))
    (test-case "extended RGB requires an explicit policy"
      (check-exn exn:fail? (lambda () (color4f->rgba (make-color4f -1/8 1/2 5/4)))))
    (test-case "explicit clipping is numerical quantization"
      (check-equal? (color4f->rgba (make-color4f -1/8 1/2 5/4 1/2) #:out-of-range 'clip)
                    (rgba 0 128 255 128)))
    (test-case "invalid clipping policy rejected"
      (check-exn exn:fail:contract? (lambda () (color4f->rgba (make-color4f 0 0 0) #:out-of-range 'invented))))
    (test-case "nonfinite channels rejected"
      (for ([x (in-list (list +inf.0 -inf.0 +nan.0))])
        (check-exn exn:fail:contract? (lambda () (make-color4f x 0 0)))))
    (test-case "alpha range remains guarded"
      (for ([a (in-list '(-1/10 11/10))])
        (check-exn exn:fail:contract? (lambda () (make-color4f 0 0 0 a)))))
    (test-case "detached vector is immutable"
      (define c (make-color4f 0.25 0.5 0.75 1.0))
      (check-true (immutable? (color4f->vector c)))
      (check-equal? (color4f->vector c) '#(0.25 0.5 0.75 1.0)))))
(module+ main
  (define failures (run-tests release-scope-pure-tests))
  (printf "release-scope-pure: ~a cases, ~a failures\n" release-scope-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
