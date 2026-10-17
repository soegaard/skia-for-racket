#lang racket/base

;;;
;;; Reference I/O Pure Test
;;;

;; Checks storage sizing, bounded buffering, codec negotiation, scanline placement, and incremental
;; states.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Public value checks and explicitly private state-model tests. No native call.
(require rackunit racket/list skia
         (prefix-in buffer: "../private/stream-buffer.rkt")
         (prefix-in query: "../private/codec-query-util.rkt")
         (prefix-in scan: "../private/codec-scanline-util.rkt")
         (prefix-in inc: "../private/codec-incremental-util.rkt")
         (prefix-in input: "../private/codec-incremental-input.rkt"))

(module+ test
  (test-case "pixel descriptions accept empty dimensions without allocating pixels"
    (define info (make-image-info 0 4))
    (check-true (image-info? info))
    (check-false (skia-resource? info))
    (check-equal? (image-info-width info) 0)
    (check-equal? (call-with-values (lambda () (image-info-storage-layout info)) list)
                  '(0 0 0))
    (check-exn exn:fail? (lambda () (make-image-info 32769 1))))

  (test-case "storage rules distinguish alpha-bearing and opaque formats"
    (check-exn exn:fail? (lambda () (make-image-info 1 1 #:color-type 'rgb-565)))
    (check-exn exn:fail?
               (lambda () (make-image-info 1 1 #:color-type 'alpha-8 #:alpha-type 'unpremul)))
    (check-exn exn:fail?
               (lambda () (make-image-info 1 1 #:color-type 'alpha-8 #:color-space 'srgb)))
    (define info (make-image-info 2 1 #:color-type 'rgb-565 #:alpha-type 'opaque))
    (check-equal? (image-info-bytes-per-pixel info) 2)
    (check-equal? (image-info-channel-bits info) '#(5 6 5))
    (check-equal? (image-info-byte-order info)
                  (if (system-big-endian?) 'big-endian 'little-endian)))

  (test-case "ICC descriptions copy mutable bytes but do not certify native support"
    ;; Deliberately header-only: this test makes no claim that Skia accepts it.
    (define profile (make-bytes 128))
    (bytes-copy! profile 0 (integer->integer-bytes 128 4 #f #t))
    (bytes-copy! profile 36 #"acsp")
    (check-false (color-space-descriptor? profile))
    (define info (make-image-info 1 1 #:color-space profile))
    (define copied (image-info-color-space info))
    (check-true (immutable? copied))
    (check-true (color-space-descriptor? copied))
    (bytes-set! profile 36 0)
    (check-equal? (subbytes copied 36 40) #"acsp")
    (check-exn exn:fail? (lambda () (make-image-info 1 1 #:color-space profile))))

  (test-case "stride minimum omits final padding while allocation includes it"
    (define info (make-image-info 3 2))
    (check-equal? (call-with-values
                   (lambda () (image-info-storage-layout info #:row-bytes 16)) list)
                  '(16 28 32))
    (check-exn exn:fail? (lambda () (image-info-storage-layout info #:row-bytes 13)))
    (parameterize ([current-skia-byte-limit 31])
      (check-equal? (image-info-min-row-bytes info) 12)
      (check-exn exn:fail? (lambda () (image-info-storage-layout info #:row-bytes 16)))))

  (test-case "format-level operation support does not initialize native Skia"
    (define info (make-image-info 2 2 #:alpha-type 'unpremul))
    (check-false (image-info-supports? info 'raster-canvas))
    (check-false (image-info-supports? info 'gpu-readback))
    (check-true (image-info-supports? info 'storage))
    (define changed (image-info-with-dimensions info 4 5))
    (check-equal? (image-info-alpha-type changed) 'unpremul)
    (check-equal? (image-info-height changed) 5)
    (check-exn exn:fail? (lambda () (image-info-supports? info 'unknown))))

  (test-case "stream byte limits and slices are checked before native entry"
    (parameterize ([current-skia-byte-limit 8])
      (check-equal? (buffer:stream-byte-limit 'test 8) 8)
      (check-exn exn:fail? (lambda () (buffer:stream-byte-limit 'test 9)))
      (check-exn exn:fail? (lambda () (buffer:stream-byte-limit 'test 0))))
    (check-equal? (call-with-values
                   (lambda () (buffer:stream-slice 'test #"abc" 1 #f)) list) '(1 3))
    (check-exn exn:fail? (lambda () (buffer:stream-slice 'test #"abc" 2 1))))

  (test-case "buffered input probes at most one byte beyond its limit"
    (define input (open-input-bytes #"abcdef"))
    (dynamic-wind void
      (lambda ()
        (check-exn exn:fail? (lambda () (buffer:read-port-buffered 'test input 3 #f #f)))
        (check-equal? (read-bytes 2 input) #"ef"))
      (lambda () (close-input-port input)))
    (define exact (open-input-bytes #"abc"))
    (check-equal? (buffer:read-port-buffered 'test exact 3 #t #f) #"abc")
    (check-true (port-closed? exact)))

  (test-case "buffered cancellation closes only after taking scoped ownership"
    (define input (open-input-bytes #"abc"))
    (check-exn exn:fail?
               (lambda () (buffer:read-port-buffered 'test input 8 #t always-evt)))
    (check-true (port-closed? input))
    (define unowned (open-input-bytes #"abc"))
    (dynamic-wind void
      (lambda ()
        (check-exn exn:fail?
                   (lambda () (buffer:read-port-buffered 'test unowned 0 #t #f)))
        (check-false (port-closed? unowned))
        (check-equal? (file-position unowned) 0))
      (lambda () (close-input-port unowned))))

  (test-case "codec scale uses rounded binary32 and subset endpoints are bounded"
    (check-exn exn:fail? (lambda () (query:codec-query-scale 'test 1e-100)))
    (check-equal? (query:codec-query-scale 'test 1) 1.0)
    (define rect (query:codec-query-rect 'test 1 2 3 4))
    (check-equal? rect '#(1 2 4 6))
    (check-not-exn (lambda () (query:codec-query-check-bounds 'test rect 4 6)))
    (check-exn exn:fail? (lambda () (query:codec-query-check-bounds 'test rect 3 6))))

  (test-case "short bottom-up batches select decoded rows and not fill rows"
    (check-equal? (call-with-values
                   (lambda () (scan:scanline-batch-layout 'test 'bottom-up 10 2 5 3)) list)
                  '(2 5))
    (check-equal? (call-with-values
                   (lambda () (scan:scanline-batch-layout 'test 'top-down 10 2 5 0)) list)
                  '(0 #f))
    (check-equal? (scan:scanline-read-state 10 2 5 3) 'incomplete)
    (check-equal? (scan:scanline-read-state 10 2 8 8) 'complete))

  (test-case "scanline completion is per request and empty batches have no rows"
    (define batch (scan:make-scanline-batch (make-image-info 2 0) 8 #f 3 0 #""))
    (check-false (scanline-batch-complete? batch))
    (check-equal? (scanline-batch-decoded-count batch) 0)
    (check-false (scanline-batch-first-row batch))
    (check-exn exn:fail? (lambda () (scan:scanline-count 'test 0 3))))

  (test-case "incremental states distinguish more input from final truncation"
    (check-equal? (inc:incremental-result-state 1 #f) 'needs-input)
    (check-equal? (inc:incremental-result-state 1 #t) 'incomplete)
    (check-equal? (inc:incremental-result-state 0 #t) 'complete)
    (check-equal? (inc:incremental-result-state 9 #t) 'failed)
    (check-false (inc:incremental-terminal? 'needs-input))
    (check-true (inc:incremental-terminal? 'incomplete)))

  (test-case "nonfinal PNG input becomes visible only through complete chunks"
    (define input (input:make-incremental-input 128))
    (define signature #"\211PNG\r\n\32\n")
    ;; Framing test only; these CRC bytes are not a valid PNG checksum.
    (define chunk (bytes-append (integer->integer-bytes 0 4 #f #t) #"IEND" #"\0\0\0\0"))
    (check-equal? (input:incremental-input-append! input signature #f) 8)
    (check-equal? (input:incremental-input-visible input) 8)
    (input:incremental-input-append! input (subbytes chunk 0 7) #f)
    (check-equal? (input:incremental-input-visible input) 8)
    (input:incremental-input-append! input (subbytes chunk 7) #f)
    (check-equal? (input:incremental-input-visible input) 20))

  (test-case "incremental quota rejection preserves copied prefix and final flag"
    (define input (input:make-incremental-input 4))
    (define bytes (bytes-copy #"abc"))
    (input:incremental-input-append! input bytes #f)
    (bytes-fill! bytes 0)
    (check-exn exn:fail?
               (lambda () (input:incremental-input-append! input #"de" #t)))
    (check-equal? (input:incremental-input-size input) 3)
    (check-false (input:incremental-input-final? input))
    (check-equal? (input:incremental-input-slice input 0 3) #"abc")
    (check-equal? (input:incremental-input-visible input) 0)
    (input:incremental-input-append! input #"" #t)
    (check-equal? (input:incremental-input-visible input) 3)
    (check-exn exn:fail?
               (lambda () (input:incremental-input-append! input #"" #f)))))
