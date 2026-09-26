#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe
         "../main.rkt" "../private/filter-util.rkt" "../private/types.rkt")
(provide filter-graph-pure-tests)
(define (bad thunk) (check-exn exn:fail:contract? thunk))
(define filter-graph-pure-tests
  (test-suite
   "Filter graphs: validation without native loading"
   (test-case "filter rectangle uses xywh, not ltrb"
     (define r (filter-rectangle 'test '(2 3 4 5)))
     (check-equal? (list (sk-rect-left r) (sk-rect-top r) (sk-rect-right r) (sk-rect-bottom r))
                   '(2.0 3.0 6.0 8.0)))
   (test-case "vector rectangles and empty crop"
     (check-true (sk-rect? (filter-rectangle 'test '#(-2 -3 0 5))))
     (check-false (optional-filter-crop 'test #f)))
   (test-case "rectangle shape and negative extents rejected"
     (for ([v (in-list '(bad (1 2 3) (0 0 -1 2) #(0 0 2 -1)))])
       (bad (lambda () (filter-rectangle 'test v)))))
   (test-case "nonfinite crop coordinates rejected"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0))])
       (bad (lambda () (filter-rectangle 'test (list v 0 1 1))))))
   (test-case "unrepresentable right edge rejected"
     (bad (lambda () (filter-rectangle 'test '(3e38 0 3e38 1))))
     (bad (lambda () (filter-rectangle 'test '(1e20 0 1 1)))))
   (test-case "source geometry requires positive sizes"
     (bad (lambda () (filter-rectangle 'test '(0 0 0 1) #:positive? #t))))
   (test-case "kernel accepts flat row-major list and default offset"
     (define-values (size offset coefficients) (filter-kernel 'test 3 2 '(0 1 2 3 4 5) #f))
     (check-equal? (list (sk-isize-width size) (sk-isize-height size)) '(3 2))
     (check-equal? (list (sk-ipoint-x offset) (sk-ipoint-y offset)) '(1 1))
     (check-equal? coefficients '(0.0 1.0 2.0 3.0 4.0 5.0)))
   (test-case "kernel copies mutable vector"
     (define v (vector 1 2))
     (define-values (_size _offset coefficients) (filter-kernel 'test 2 1 v '#(0 0)))
     (vector-set! v 0 99)
     (check-equal? coefficients '(1.0 2.0)))
   (test-case "kernel dimensions have pinned upper bound"
     (for ([n (in-list '(0 -1 2049 1.5))])
       (bad (lambda () (filter-kernel 'test n 1 '(1) #f)))))
   (test-case "kernel count must exactly match dimensions"
     (bad (lambda () (filter-kernel 'test 2 2 '(1 2 3) #f)))
     (bad (lambda () (filter-kernel 'test 1 1 '#(1 2) #f))))
   (test-case "kernel offsets are exact in-range indices"
     (for ([v (in-list '((2 0) (-1 0) (0 1) (0.0 0) bad))])
       (bad (lambda () (filter-kernel 'test 2 1 '(1 0) v)))))
   (test-case "kernel rejects nonfinite coefficients"
     (bad (lambda () (filter-kernel 'test 1 1 (list +nan.0) #f))))
   (test-case "kernel size charged before copying"
     (parameterize ([current-skia-byte-limit 8])
       (check-exn #rx"byte-limit" (lambda () (filter-kernel 'test 3 3 (make-vector 9 0) #f)))))
   (test-case "channel names map to the pinned enum"
     (check-equal? (map (lambda (x) (filter-channel 'test x)) '(red green blue alpha)) '(0 1 2 3))
     (bad (lambda () (filter-channel 'test 'r))))
   (test-case "convolution tiling requires an explicit crop"
     (bad (lambda () (make-matrix-convolution-image-filter 1 1 '(1) #:tile-mode 'repeat)))
     (check-equal? (filter-tile-mode 'test 'clamp #t #:require-crop? #t) 0))
   (test-case "mirror rejected for convolution and blur"
     (bad (lambda () (make-matrix-convolution-image-filter 1 1 '(1) #:tile-mode 'mirror #:crop '(0 0 1 1))))
     (bad (lambda () (make-blur-image-filter 1 1 #:tile-mode 'mirror))))
   (test-case "crop validation applies to legacy constructors"
     (bad (lambda () (make-blur-image-filter 1 1 #:crop '(1 2))))
     (bad (lambda () (make-drop-shadow-image-filter 1 1 1 1 'red #:crop '(1 2))))
     (bad (lambda () (make-drop-shadow-only-image-filter 1 1 1 1 'red #:crop '(1 2))))
     (bad (lambda () (make-color-filter-image-filter #f #:crop '(1 2))))
     (bad (lambda () (make-compose-image-filter #f #f #:crop '(1 2)))))
   (test-case "merge is nonempty and inputs have correct types"
     (bad (lambda () (make-merge-image-filter '())))
     (bad (lambda () (make-merge-image-filter '#(wrong)))))
   (test-case "merge pointer-array size is bounded"
     (parameterize ([current-skia-byte-limit 8])
       (check-exn #rx"byte-limit" (lambda () (filter-input-list 'test '(#f #f))))))
   (test-case "binary graph validation precedes native loading"
     (bad (lambda () (make-blend-image-filter 'not-a-mode #f #f)))
     (bad (lambda () (make-arithmetic-image-filter +inf.0 1 1 0 #f #f)))
     (bad (lambda () (make-arithmetic-image-filter 0 1 0 0 #f #f #:enforce-premul? 1))))
   (test-case "morphology radii must be nonnegative"
     (bad (lambda () (make-dilate-image-filter -1 1)))
     (bad (lambda () (make-erode-image-filter 1 +nan.0))))
   (test-case "displacement and source nodes reject invalid inputs"
     (bad (lambda () (make-displacement-map-image-filter 'red 'alpha 4 #t #f)))
     (bad (lambda () (make-image-source-filter #f)))
     (bad (lambda () (make-picture-image-filter #f)))
     (bad (lambda () (make-shader-image-filter #f))))
   (test-case "filter matrices reject singular transforms"
     (bad (lambda () (make-matrix-transform-image-filter (matrix-scale 0 1))))
     (bad (lambda () (make-matrix-transform-image-filter 'wrong))))
   (test-case "tile and magnifier validate positive geometry"
     (bad (lambda () (make-tile-image-filter '(0 0 0 2) '(0 0 4 4))))
     (bad (lambda () (make-magnifier-image-filter '(0 0 4 4) 0.5)))
     (bad (lambda () (make-magnifier-image-filter '(0 0 4 4) 2 #:inset -1))))
   (test-case "point3 accepts vector and rejects zero light direction"
     (check-equal? (sk-point3-z (filter-point3 'test '#(1 2 3))) 3.0)
     (bad (lambda () (filter-point3 'test '(0 0 0) #:direction? #t))))
   (test-case "lighting validates coefficients and surface scale"
     (bad (lambda () (make-distant-lit-diffuse-image-filter '(0 0 1) 'white #:coefficient -1)))
     (bad (lambda () (make-point-lit-diffuse-image-filter '(0 0 10) 'white #:surface-scale +inf.0))))
   (test-case "specular shininess is mandatory numeric within range"
     (for ([v (in-list '(#f 0 129))])
       (bad (lambda () (make-distant-lit-specular-image-filter '(0 0 1) 'white #:shininess v)))))
   (test-case "spotlight geometry and cone validation"
     (bad (lambda () (make-spot-lit-diffuse-image-filter '(0 0 1) '(0 0 1) 'white)))
     (bad (lambda () (make-spot-lit-specular-image-filter '(0 0 10) '(0 0 0) 'white #:cutoff-angle 91)))
     (bad (lambda () (make-spot-lit-diffuse-image-filter '(0 0 10) '(0 0 0) 'white #:exponent -1))))
   (test-case "C filter records have complete expected sizes"
     (check-equal? (ctype-sizeof _sk-isize) 8)
     (check-equal? (ctype-sizeof _sk-ipoint) 8)
     (check-equal? (ctype-sizeof _sk-point3) 12))
   (test-case "convolution alpha flag and gain validation"
     (bad (lambda () (make-matrix-convolution-image-filter 1 1 '(1) #:convolve-alpha? 1)))
     (bad (lambda () (make-matrix-convolution-image-filter 1 1 '(1) #:gain +nan.0))))))
(module+ test (run-tests filter-graph-pure-tests))
