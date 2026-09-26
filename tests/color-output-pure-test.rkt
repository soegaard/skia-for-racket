#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe "../main.rkt"
         "../private/color-output-util.rkt" "../private/types.rkt"
         "color-output-fixtures.rkt")
(provide color-output-pure-tests)
(define identity-xyz '#(1 0 0 0 1 0 0 0 1))
(define linear (make-transfer-function 1 1 0 0 0 0 0))
(define (u32! bs at n) (bytes-copy! bs at (integer->integer-bytes n 4 #f #t)))
(define (reject mutation)
  (define p (fixture-icc)) (mutation p)
  (check-exn exn:fail? (lambda () (checked-encoding-profile 'test p))))

(define color-output-pure-tests
  (test-suite
   "Color output: pure values and validation"
   (test-case "transfer value is immutable and detached"
     (check-true (transfer-function? linear))
     (check-true (immutable? (transfer-function-coefficients linear)))
     (check-equal? (vector-length (transfer-function-coefficients linear)) 7))
   (test-case "gamma evaluation"
     (check-= (transfer-function-evaluate (make-transfer-function 2 1 0 0 0 0 0) 0.5) 0.25 1e-9))
   (test-case "piecewise evaluation uses c and e in their proper roles"
     (define tf (make-transfer-function 2 1 0 0.1 0.5 0.2 0.3))
     (check-= (transfer-function-evaluate tf 0.25) 0.325 1e-6)
     (check-= (transfer-function-evaluate tf 0.75) 0.7625 1e-6))
   (test-case "nonpositive gamma is rejected"
     (for ([g '(0 -1)]) (check-exn exn:fail? (lambda () (make-transfer-function g 1 0 0 0 0 0)))))
   (test-case "negative scale slope and breakpoint are rejected"
     (for ([args '((1 -1 0 0 0 0 0) (1 1 0 -1 0 0 0) (1 1 0 0 -1 0 0))])
       (check-exn exn:fail? (lambda () (apply make-transfer-function args)))))
   (test-case "underflowed gamma is rejected after float conversion"
     (check-exn exn:fail? (lambda () (make-transfer-function 1e-60 1 0 0 0 0 0))))
   (test-case "infinities NaN and huge exact coefficients are rejected"
     (for ([v (list +inf.0 +nan.0 (expt 10 500))])
       (check-exn exn:fail? (lambda () (make-transfer-function 1 1 v 0 0 0 0)))))
   (test-case "evaluation validates its argument"
     (for ([x (list -1 +nan.0 +inf.0 'x)])
       (check-exn exn:fail? (lambda () (transfer-function-evaluate linear x)))))
   (test-case "evaluation validates transfer type"
     (check-exn exn:fail? (lambda () (transfer-function-evaluate #f 0.5))))
   (test-case "unknown transfer name does not load Skia"
     (check-exn exn:fail? (lambda () (named-transfer-function 'pq))))
   (test-case "unknown gamut does not load Skia"
     (check-exn exn:fail? (lambda () (named-xyz-d50 'unknown))))
   (test-case "matrix length is checked before native construction"
     (check-exn exn:fail? (lambda () (make-rgb-color-space linear '(1 2 3)))))
   (test-case "singular gamut is rejected"
     (check-exn exn:fail? (lambda () (make-rgb-color-space linear (make-vector 9 0)))))
   (test-case "XYZ matrix snapshot is immutable"
     (define v (vector 1 0 0 0 1 0 0 0 1))
     (define got (checked-xyz-d50 'test v))
     (vector-set! v 0 9)
     (check-= (vector-ref got 0) 1 0)
     (check-true (immutable? got)))
   (test-case "invalid primary coordinates are rejected before loading"
     (for ([bad '((0.2 0) (-0.1 0.2) (0.9 0.9) (1))])
       (check-exn exn:fail? (lambda () (primaries->xyz-d50 bad '(0.3 0.6) '(0.15 0.06) '(0.3127 0.3290))))))
   (test-case "automatic ICC mode remains false"
     (check-false (checked-encoding-profile 'test #f)))
   (test-case "synthetic profile directory passes"
     (check-true (bytes? (checked-encoding-profile 'test (fixture-icc)))))
   (test-case "ICC declared size and signature checked"
     (reject (lambda (b) (u32! b 0 132)))
     (reject (lambda (b) (bytes-copy! b 36 #"nope"))))
   (test-case "ICC tag table cannot run outside the bytes"
     (reject (lambda (b) (u32! b 128 #xffffffff))))
   (test-case "non-RGB and non-XYZ overrides rejected"
     (reject (lambda (b) (bytes-copy! b 16 #"CMYK")))
     (reject (lambda (b) (bytes-copy! b 20 #"Lab "))))
   (test-case "missing required curve rejected"
     (reject (lambda (b) (bytes-copy! b (+ 132 (* 12 5)) #"desc"))))
   (test-case "tag ranges and alignment checked"
     (reject (lambda (b) (u32! b 136 #xffff)))
     (reject (lambda (b) (u32! b 136 1)))
     (reject (lambda (b) (u32! b 140 #xffffffff))))
   (test-case "duplicate tags rejected"
     (reject (lambda (b) (bytes-copy! b 144 #"rXYZ"))))
   (test-case "LUT and HDR tags rejected before native profile writer"
     (for ([tag '(#"A2B0" #"B2A0" #"D2B0" #"cicp")])
       (reject (lambda (b) (bytes-copy! b 132 tag)))))
   (test-case "invalid XYZ tag type rejected"
     (reject (lambda (b) (bytes-copy! b (icc-u32 b 136) #"mAB "))))
   (test-case "ICC input copy survives mutation"
     (define p (fixture-icc))
     (define got (checked-encoding-profile 'test p))
     (bytes-set! p 36 0)
     (check-true (immutable? got))
     (check-equal? (subbytes got 36 40) #"acsp"))
   (test-case "ICC descriptions require a profile"
     (check-exn exn:fail? (lambda () (icc-description-bytes 'test #f "Name"))))
   (test-case "ICC descriptions are printable ASCII"
     (for ([s '("" "x\0y" "caf\u00e9")])
       (check-exn exn:fail? (lambda () (icc-description-bytes 'test #t s))))
     (check-equal? (icc-description-bytes 'test #t "RGB") #"RGB\0"))
   (test-case "metadata byte limits checked before native calls"
     (parameterize ([current-skia-byte-limit 4])
       (check-exn exn:fail? (lambda () (checked-encoding-profile 'test (fixture-icc))))
       (check-exn exn:fail? (lambda () (icc-description-bytes 'test #t "1234")))))
   (test-case "encoder descriptions not silently ignored"
     (check-exn exn:fail? (lambda () (image->png-bytes #f #:icc-description "Bad")))
     (check-exn exn:fail? (lambda () (image->jpeg-bytes #f #:icc-profile #"bad")))
     (check-exn exn:fail? (lambda () (image->webp-bytes #f #:color-space 'bad))))
   (test-case "PDF-A flag is a boolean"
     (check-exn exn:fail? (lambda () (make-pdf-document #:pdfa? 1))))
   (test-case "SVG rejects PDF-A request before callback"
     (define called? #f)
     (define page (make-output-page 10 10 (lambda (_) (set! called? #t))))
     (check-exn exn:fail? (lambda () (output->bytes page 'svg #:pdfa? #t)))
     (check-false called?))
   (test-case "new native layout sizes and field order"
     (check-equal? (ctype-sizeof _sk-transfer) 28)
     (check-equal? (ctype-sizeof _sk-xyz) 36)
     (check-equal? (ctype-sizeof _sk-primaries) 32)
     (define t (make-sk-transfer 1.0 2.0 3.0 4.0 5.0 6.0 7.0))
     (check-equal? (for/list ([i (in-range 7)]) (ptr-ref t _float i)) '(1.0 2.0 3.0 4.0 5.0 6.0 7.0)))
   (test-case "new color operations reject bad handles"
     (check-exn exn:fail? (lambda () (color-space-transfer-function #f)))
     (check-exn exn:fail? (lambda () (color-space-xyz-d50 #f)))
     (check-exn exn:fail? (lambda () (image-convert-color-space #f #f))))))
(module+ test (run-tests color-output-pure-tests))
