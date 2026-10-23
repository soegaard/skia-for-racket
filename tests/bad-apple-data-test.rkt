#lang racket/base

;;;
;;; Bad Apple!! Prepared Data Tests
;;;

(require file/gzip
         json
         racket/file
         rackunit
         rackunit/text-ui
         "../examples/bad-apple/data.rkt")

(provide bad-apple-data-tests)

(define (fixture frames #:count [count (length frames)] #:fill-rule [fill-rule "winding"])
  (hasheq 'schema "skia-bad-apple-paths"
          'version 1
          'source (hasheq 'repository "fixture/repository"
                          'commit "abcdef"
                          'path "frames.js"
                          'sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                          'first_source_index 1)
          'fps_numerator 30
          'fps_denominator 1
          'frame_count count
          'view_box '(0 0 480 360)
          'source_to_view_box '(0.1 0 0 -0.1 0 360)
          'fill_rule fill-rule
          'frames frames))

(define bad-apple-data-tests
  (test-suite
   "Bad Apple prepared data"
   (test-case "valid fixture preserves blank and multipart frames"
     (define asset
       (bad-apple-asset-from-jsexpr
        (fixture '(("M0 0L4800 0L4800 3600L0 3600Z" "M100 100L200 100Z") () ("M0 0Z")))))
     (check-equal? (bad-apple-asset-frame-count asset) 3)
     (check-equal? (vector-length (vector-ref (bad-apple-asset-frames asset) 0)) 2)
     (check-equal? (vector-length (vector-ref (bad-apple-asset-frames asset) 1)) 0)
     (check-equal? (bad-apple-frame-rate asset) 30)
     (check-equal? (bad-apple-duration-seconds asset) 1/10))
   (test-case "declared count must agree with frame array"
     (check-exn #rx"declared frame count"
                (lambda () (bad-apple-asset-from-jsexpr (fixture '(()) #:count 2)))))
   (test-case "only winding source data is admitted"
     (check-exn #rx"winding"
                (lambda ()
                  (bad-apple-asset-from-jsexpr (fixture '(()) #:fill-rule "even-odd")))))
   (test-case "source transform must be finite"
     (define jsexpr (fixture '(()) ))
     (check-exn #rx"invalid value"
                (lambda ()
                  (bad-apple-asset-from-jsexpr
                   (hash-set jsexpr 'source_to_view_box '(0.1 0 0 +inf.0 0 360))))))
   (test-case "gzip loader validates and returns immutable ordinary data"
     (define path (make-temporary-file "bad-apple-data-~a.json.gz"))
     (dynamic-wind
       void
       (lambda ()
         (define json-output (open-output-bytes))
         (write-json (fixture '(("M0 0Z") ())) json-output)
         (call-with-output-file path #:exists 'truncate
           (lambda (output)
             (gzip-through-ports (open-input-bytes (get-output-bytes json-output)) output #f 0)))
         (define asset (read-bad-apple-asset path))
         (check-true (immutable? (bad-apple-asset-frames asset)))
         (check-equal? (vector-length (bad-apple-asset-frames asset)) 2))
       (lambda () (delete-file path))))))

(define (run-bad-apple-data-tests) (run-tests bad-apple-data-tests))
(module+ main (run-bad-apple-data-tests))
(module+ test (run-bad-apple-data-tests))
