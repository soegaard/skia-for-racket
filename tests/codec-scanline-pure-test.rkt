#lang racket/base
(require rackunit rackunit/text-ui "../main.rkt"
         (only-in "../private/codec-scanline-util.rkt"
                  scanline-options scanline-count scanline-index scanline-order-name
                  scanline-row scanline-batch-layout scanline-read-state raise-scanline-result))
(provide codec-scanline-pure-tests codec-scanline-pure-test-count)
(define codec-scanline-pure-test-count 32)
(define (layout order height position request decoded)
  (call-with-values (lambda () (scanline-batch-layout 'test order height position request decoded)) list))
(define codec-scanline-pure-tests
  (test-suite "0.76b pure scanline contracts"
   (test-case "positive scales round to C float"
     (define-values (scale info) (scanline-options 'test 1/2 'rgba-8888 'unpremul 'srgb))
     (check-= scale 0.5 0)
     (check-equal? (image-info-color-space info) 'srgb))
   (test-case "invalid scales rejected"
     (for ([v (in-list (list 0 -1 +nan.0 +inf.0 -inf.0 1e-300 'half))])
       (check-exn exn:fail? (lambda () (scanline-options 'test v 'rgba-8888 'unpremul 'srgb)))))
   (test-case "unknown format rejected"
     (check-exn exn:fail? (lambda () (scanline-options 'test 1 'not-a-format 'premul #f))))
   (test-case "opaque-only alpha mismatch rejected"
     (check-exn exn:fail? (lambda () (scanline-options 'test 1 'rgb-565 'unpremul #f))))
   (test-case "float description remains detached"
     (define-values (_ info) (scanline-options 'test 1 'rgba-f16 'premul 'linear-srgb))
     (check-equal? (image-info-bytes-per-pixel info) 8)
     (check-equal? (image-info-color-space info) 'linear-srgb))
   (test-case "invalid alpha rejected"
     (check-exn exn:fail? (lambda () (scanline-options 'test 1 'rgba-8888 'unknown #f))))
   (test-case "live color space cannot masquerade as descriptor"
     (check-exn exn:fail? (lambda () (scanline-options 'test 1 'rgba-8888 'premul 'display-p3))))
   (test-case "positive row count bounded"
     (check-equal? (scanline-count 'test 2 2) 2)
     (for ([n '(0 -1 3 1.0 #f)])
       (check-exn exn:fail? (lambda () (scanline-count 'test n 2)))))
   (test-case "zero skip is explicit"
     (check-equal? (scanline-count 'test 0 0 #:zero? #t) 0)
     (check-exn exn:fail? (lambda () (scanline-count 'test 1 0 #:zero? #t))))
   (test-case "row indices reject height and negative values"
     (for ([n '(-1 5 2.0 #f)]) (check-exn exn:fail? (lambda () (scanline-index 'test n 5)))))
   (test-case "native ordering enums are checked"
     (check-equal? (scanline-order-name 'test 0) 'top-down)
     (check-equal? (scanline-order-name 'test 1) 'bottom-up)
     (check-exn exn:fail? (lambda () (scanline-order-name 'test 2))))
   (test-case "top-down mapping"
     (check-equal? (for/list ([i (in-range 5)]) (scanline-row 'test 'top-down 5 i)) '(0 1 2 3 4)))
   (test-case "bottom-up mapping"
     (check-equal? (for/list ([i (in-range 5)]) (scanline-row 'test 'bottom-up 5 i)) '(4 3 2 1 0)))
   (test-case "top-down complete batch"
     (check-equal? (layout 'top-down 8 2 3 3) '(0 2)))
   (test-case "bottom-up complete batch"
     (check-equal? (layout 'bottom-up 8 2 3 3) '(0 3)))
   (test-case "top-down partial excludes native fill"
     (check-equal? (layout 'top-down 8 2 3 1) '(0 2)))
   (test-case "bottom-up partial strips leading fill"
     (check-equal? (layout 'bottom-up 8 2 3 1) '(2 5)))
   (test-case "zero decoded rows have no logical first row"
     (check-equal? (layout 'top-down 8 2 3 0) '(0 #f))
     (check-equal? (layout 'bottom-up 8 2 3 0) '(3 #f)))
   (test-case "invalid native counts rejected"
     (for ([got '(-1 4 1.0 #f)])
       (check-exn exn:fail? (lambda () (layout 'top-down 8 2 3 got)))))
   (test-case "batch does not cross end of image"
     (check-exn exn:fail? (lambda () (layout 'bottom-up 8 7 2 1))))
   (test-case "incomplete dominates exhaustion"
     (check-equal? (scanline-read-state 5 2 3 1) 'incomplete))
   (test-case "complete and ready transitions"
     (check-equal? (scanline-read-state 5 2 3 3) 'complete)
     (check-equal? (scanline-read-state 5 0 2 2) 'ready))
   (test-case "padded batch layout is bounded"
     (define-values (rb minimum size) (image-info-storage-layout (make-image-info 7 2) #:row-bytes 32))
     (check-equal? (list rb minimum size) '(32 60 64)))
   (test-case "misaligned and short strides rejected"
     (for ([rb '(27 29 -1 28.0)])
       (check-exn exn:fail? (lambda () (image-info-storage-layout (make-image-info 7 2) #:row-bytes rb)))))
   (test-case "batch allocation obeys current byte limit"
     (parameterize ([current-skia-byte-limit 63])
       (check-exn exn:fail? (lambda () (image-info-storage-layout (make-image-info 7 2) #:row-bytes 32)))))
   (test-case "unsupported native result remains distinct"
     (check-exn (lambda (e) (and (exn:fail:codec-scanline? e)
                                (eq? (exn:fail:codec-scanline-result e) 'unimplemented)
                                (= (exn:fail:codec-scanline-native-code e) 9)))
                (lambda () (raise-scanline-result 'test 9))))
   (test-case "invalid-conversion native result remains distinct"
     (check-exn (lambda (e) (and (exn:fail:codec-scanline? e)
                                (eq? (exn:fail:codec-scanline-result e) 'invalid-conversion)))
                (lambda () (raise-scanline-result 'test 3))))
   (test-case "unknown native result remains an error"
     (check-exn (lambda (e) (and (exn:fail:codec-scanline? e)
                                (eq? (exn:fail:codec-scanline-result e) 'unknown-result)))
                (lambda () (raise-scanline-result 'test 100))))
   (test-case "invalid source rejected without loading native library"
     (check-exn exn:fail? (lambda () (codec-scanline-from-bytes #f)))
     (check-exn exn:fail? (lambda () (codec-scanline-from-stream #f))))
   (test-case "options validated before reading buffered port"
     (define in (open-input-bytes #"abc"))
     (check-exn exn:fail? (lambda () (codec-scanline-from-port/buffered in #:scale 0 #:close? #t)))
     (check-false (port-closed? in)) (check-equal? (read-byte in) 97))
   (test-case "all session operations validate type"
     (for ([op (in-list (list codec-scanline-state codec-scanline-info codec-scanline-source-info
                              codec-scanline-order codec-scanline-position codec-scanline-next-row
                              codec-scanline-read!))])
       (check-exn exn:fail? (lambda () (op #f)))))
   (test-case "batch operations validate type"
     (check-false (scanline-batch? #f))
     (check-exn exn:fail? (lambda () (scanline-batch-complete? #f)))
     (check-exn exn:fail? (lambda () (scanline-batch->raster-buffer #f))))))
(module+ main
  (define failures (run-tests codec-scanline-pure-tests))
  (printf "codec-scanline-pure: ~a cases, ~a failures\n" codec-scanline-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
