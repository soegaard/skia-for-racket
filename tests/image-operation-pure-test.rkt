#lang racket/base
(require rackunit racket/list racket/vector racket/runtime-path setup/getinfo version/utils
         "../main.rkt" "../private/image-operation-util.rkt")
(provide image-operation-pure-tests)
(define-runtime-path package-root "..")
(define (bad proc) (check-exn exn:fail? proc))
(define image-operation-pure-tests
  (test-suite
   "Direct image operations (pure)"
   (test-case "actual package version uses Racket's canonical predicate"
     (define i (get-info/full package-root))
     (check-true (valid-version? (i 'version)))
     (check-false (valid-version? "0.72.0")))
   (test-case "rectangles detach mutable vectors"
     (define input (vector -3 2 7 9))
     (define r (operation-rectangle 'test input))
     (vector-set! input 0 400)
     (check-equal? r '#(-3 2 7 9)) (check-true (immutable? r)))
   (test-case "list rectangles are accepted"
     (check-equal? (operation-rectangle 'test '(0 1 2 3)) '#(0 1 2 3)))
   (test-case "rectangle arity is exact"
     (for ([v (in-list '(#() (0 0 1) (0 0 1 1 1) bad #f))])
       (bad (lambda () (operation-rectangle 'test v)))))
   (test-case "rectangle coordinates must be exact integers"
     (for ([v (in-list (list '(0.0 0 1 1) '(0 1/2 1 1) (list 0 +nan.0 1 1)))])
       (bad (lambda () (operation-rectangle 'test v)))))
   (test-case "empty rectangles reject"
     (for ([v (in-list '((0 0 0 1) (0 0 1 0) (0 0 -1 1)))])
       (bad (lambda () (operation-rectangle 'test v)))))
   (test-case "oversized dimensions reject"
     (bad (lambda () (operation-rectangle 'test '(0 0 32769 1)))))
   (test-case "signed right-edge overflow rejects"
     (bad (lambda () (operation-rectangle 'test '(2147483647 0 1 1)))))
   (test-case "signed top-edge underflow rejects"
     (bad (lambda () (operation-rectangle 'test '(0 -2147483649 1 1)))))
   (test-case "default subset covers the full image"
     (check-equal? (operation-subset 'test #f 16 12) '#(0 0 16 12)))
   (test-case "negative subset origin rejects"
     (bad (lambda () (operation-subset 'test '(-1 0 2 2) 16 12))))
   (test-case "subset cannot extend beyond the image"
     (bad (lambda () (operation-subset 'test '(15 0 2 2) 16 12))))
   (test-case "edge-aligned subset succeeds"
     (check-equal? (operation-subset 'test '(15 11 1 1) 16 12) '#(15 11 1 1)))
   (test-case "filter budget includes a conservative full-width sample"
     (check-equal? (operation-budget 'test 3 2) 96))
   (test-case "filter budget obeys the current byte limit"
     (parameterize ([current-skia-byte-limit 95]) (bad (lambda () (operation-budget 'test 3 2)))))
   (test-case "zero allocation geometry rejects"
     (bad (lambda () (operation-budget 'test 0 2))))
   (test-case "native result uses subset dimensions and geometric offset"
     (define-values (r p) (operation-result-geometry 'test 32 32 '#(7 8 5 3) '#(12 9) '#(12 9 5 3)))
     (check-equal? r '#(7 8 5 3)) (check-equal? p '#(12 9)))
   (test-case "result subset cannot escape the backing image"
     (bad (lambda () (operation-result-geometry 'test 32 32 '#(30 0 5 3) '#(0 0) '#(0 0 20 20)))))
   (test-case "result offset cannot escape the clip"
     (bad (lambda () (operation-result-geometry 'test 32 32 '#(0 0 5 3) '#(15 9) '#(12 9 5 3)))))
   (test-case "native offsets have two signed integers"
     (bad (lambda () (operation-result-geometry 'test 32 32 '#(0 0 5 3) '#(0.0 0) '#(0 0 20 20)))))
   (test-case "negative geometric offsets remain valid"
     (define-values (r p) (operation-result-geometry 'test 10 10 '#(0 0 5 5) '#(-2 -3) '#(-4 -4 20 20)))
     (check-equal? p '#(-2 -3)))
   (test-case "F32 cannot implicitly narrow to F16 or integer"
     (check-true (operation-precision-compatible? 16 16))
     (check-false (operation-precision-compatible? 16 15))
     (check-false (operation-precision-compatible? 16 4)))
   (test-case "F16 can widen but cannot implicitly become integer"
     (check-true (operation-precision-compatible? 15 16))
     (check-true (operation-precision-compatible? 15 15))
     (check-false (operation-precision-compatible? 15 6)))
   (test-case "integer image results may use native integer channel ordering"
     (check-true (operation-precision-compatible? 4 6)))
   (test-case "image metadata queries reject non-images without loading native code"
     (for ([p (in-list (list image-unique-id image-alpha-only? image-lazy-generated?
                             image-texture-backed? image-valid? image-pixels-available?))])
       (bad (lambda () (p #f)))))
   (test-case "materialization checks the image type"
     (bad (lambda () (image->raster-image 'bad)))
     (bad (lambda () (image->non-texture-image 'bad))))
   (test-case "image reads and scales check resource types"
     (bad (lambda () (image-read-pixmap! #f #f)))
     (bad (lambda () (image-scale-pixmap! #f #f))))
   (test-case "new image buffer constructor checks resource types"
     (bad (lambda () (image->raster-buffer #f))))
   (test-case "filter application requires a real image"
     (bad (lambda () (image-apply-filter #f #f #:clip '(0 0 16 12)))))
   (test-case "raw shaders check the source image"
     (bad (lambda () (make-raw-image-shader #f))))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests image-operation-pure-tests)) (error 'image-operations "pure tests failed")))
