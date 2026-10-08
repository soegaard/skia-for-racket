#lang racket/base
(require rackunit rackunit/text-ui racket/file
         "../main.rkt" "codec-query-fixtures.rkt" "codec-fixtures.rkt")
(provide codec-query-native-tests codec-query-native-test-count)
(define (with-codec format proc)
  (with-skia ([codec (codec-from-bytes (query-fixture-bytes format))]) (proc codec)))
(define (dimensions codec scale)
  (call-with-values (lambda () (codec-scaled-dimensions codec scale)) list))
(define (decoded codec)
  (with-skia ([image (codec->image codec #:normalize-origin? #f)]) (image->rgba-bytes image)))
(define (other-thread-error thunk)
  (define answer (make-channel))
  (define worker
    (thread (lambda () (channel-put answer (with-handlers ([exn:fail? values]) (thunk) #f)))))
  (define result (sync/timeout 10 answer))
  (unless result (kill-thread worker))
  (check-pred exn:fail? result))
(define codec-query-native-tests
  (test-suite "0.76a native codec size and subset negotiation"
    (test-case "all formats report original size at scale one"
      (for ([format '(png jpeg webp)]) (with-codec format (lambda (c) (check-equal? (dimensions c 1) '(16 12))))))
    (test-case "upscale queries clamp to original size"
      (for ([format '(png jpeg webp)]) (with-codec format (lambda (c) (check-equal? (dimensions c 8) '(16 12))))))
    (test-case "JPEG half-size is native 8 by 6" (with-codec 'jpeg (lambda (c) (check-equal? (dimensions c 1/2) '(8 6)))))
    (test-case "JPEG quarter-size is native 4 by 3" (with-codec 'jpeg (lambda (c) (check-equal? (dimensions c 1/4) '(4 3)))))
    (test-case "JPEG eighth-size rounds rows up" (with-codec 'jpeg (lambda (c) (check-equal? (dimensions c 1/8) '(2 2)))))
    (test-case "JPEG tiny request returns native minimum not a fabricated size" (with-codec 'jpeg (lambda (c) (check-equal? (dimensions c 0.01) '(2 2)))))
    (test-case "PNG without native scaling returns original dimensions" (with-codec 'png (lambda (c) (check-equal? (dimensions c 1/2) '(16 12)))))
    (test-case "JPEG query uses encoded dimensions before EXIF rotation"
      (with-skia ([c (codec-from-bytes (jpeg-with-origin (query-fixture-bytes 'jpeg) 6))])
        (check-equal? (dimensions c 1/2) '(8 6))
        (with-skia ([image (codec->image c)]) (check-equal? (list (image-width image) (image-height image)) '(12 16)))))
    (test-case "PNG subset unsupported is false" (with-codec 'png (lambda (c) (check-false (codec-supported-subset c 1 3 6 5)))))
    (test-case "JPEG subset unsupported is false" (with-codec 'jpeg (lambda (c) (check-false (codec-supported-subset c 1 3 6 5)))))
    (test-case "WebP even subset stays exact" (with-codec 'webp (lambda (c) (check-equal? (codec-supported-subset c 2 4 6 4) '#(2 4 6 4)))))
    (test-case "WebP odd origin expands left and top only" (with-codec 'webp (lambda (c) (check-equal? (codec-supported-subset c 1 3 6 5) '#(0 2 7 6)))))
    (test-case "WebP full image is a supported subset" (with-codec 'webp (lambda (c) (check-equal? (codec-supported-subset c 0 0 16 12) '#(0 0 16 12)))))
    (test-case "WebP last pixel keeps native exclusive bounds" (with-codec 'webp (lambda (c) (check-equal? (codec-supported-subset c 15 11 1 1) '#(14 10 2 2)))))
    (test-case "repeated queries do not update original size"
      (with-codec 'webp (lambda (c)
        (for ([i (in-range 10)]) (check-equal? (codec-supported-subset c 1 3 6 5) '#(0 2 7 6)))
        (check-equal? (dimensions c 1) '(16 12)))))
    (test-case "subset result survives codec closure"
      (with-codec 'webp (lambda (c)
        (define result (codec-supported-subset c 1 3 6 5))
        (skia-close! c) (collect-garbage)
        (check-true (immutable? result)) (check-equal? result '#(0 2 7 6)))))
    (test-case "PNG query does not alter subsequent full decoding"
      (with-codec 'png (lambda (c)
        (define before (decoded c)) (dimensions c 1/2) (codec-supported-subset c 1 3 6 5)
        (check-equal? (decoded c) before) (check-equal? before (query-fixture-pixels)))))
    (test-case "WebP negotiated rectangle does not crop the codec"
      (with-codec 'webp (lambda (c)
        (define before (decoded c)) (codec-supported-subset c 1 3 6 5)
        (check-equal? (decoded c) before) (check-equal? before (query-fixture-pixels)))))
    (test-case "closed codec rejects both queries"
      (with-codec 'jpeg (lambda (c)
        (skia-close! c)
        (check-exn exn:fail? (lambda () (dimensions c 1)))
        (check-exn exn:fail? (lambda () (codec-supported-subset c 0 0 1 1))))))
    (test-case "both queries enforce owner-thread affinity"
      (with-codec 'webp (lambda (c)
        (other-thread-error (lambda () (dimensions c 1)))
        (other-thread-error (lambda () (codec-supported-subset c 0 0 1 1))))))
    (test-case "invalid subsets reject even when format does not support subsets"
      (with-codec 'png (lambda (c)
        (for ([rect '((-1 0 1 1) (0 0 0 1) (16 0 1 1) (0 11 1 2) (0 0 1.0 1))])
          (check-exn exn:fail:contract? (lambda () (apply codec-supported-subset c rect))))
        (check-equal? (dimensions c 1) '(16 12)))))
    (test-case "invalid scales do not damage the codec"
      (with-codec 'jpeg (lambda (c)
        (for ([scale (list 0 -1 1e-100 +nan.0 +inf.0)])
          (check-exn exn:fail:contract? (lambda () (dimensions c scale))))
        (check-equal? (dimensions c 1/2) '(8 6)) (check-equal? (bytes-length (decoded c)) (* 16 12 4)))))
    (test-case "native-stream caller cursor is unchanged"
      (with-skia ([s (make-memory-input-stream (query-fixture-bytes 'webp))])
        (input-stream-seek! s 7)
        (with-skia ([c (codec-from-stream s)])
          (check-equal? (codec-supported-subset c 1 3 6 5) '#(0 2 7 6))
          (check-equal? (input-stream-position s) 7)
          (skia-close! s) (collect-garbage) (check-equal? (dimensions c 1) '(16 12)))))
    (test-case "file-stream codec queries survive source wrapper closure"
      (define path (make-temporary-file "skia-codec-query-~a.jpg"))
      (dynamic-wind void
        (lambda ()
          (call-with-output-file path (lambda (out) (write-bytes (query-fixture-bytes 'jpeg) out)) #:exists 'truncate #:mode 'binary)
          (with-skia ([s (make-file-input-stream path)] [c (codec-from-stream s)])
            (skia-close! s) (collect-garbage)
            (check-equal? (dimensions c 1/2) '(8 6))))
        (lambda () (delete-file path))))
    (test-case "queries do not charge a full pixel allocation"
      (with-codec 'webp (lambda (c)
        (parameterize ([current-skia-byte-limit 1])
          (check-equal? (dimensions c 1) '(16 12))
          (check-equal? (codec-supported-subset c 1 3 6 5) '#(0 2 7 6))))))
    (test-case "one-pixel codec remains nonempty"
      (for ([format '(png jpeg webp)])
        (with-skia ([c (codec-from-bytes (query-fixture-bytes format 1 1))])
          (check-equal? (dimensions c 0.125) '(1 1))
          (check-equal? (codec-supported-subset c 0 0 1 1) (and (eq? format 'webp) '#(0 0 1 1))))))))
(define codec-query-native-test-count 26)
(module+ main
  (skia-check!)
  (define failures (run-tests codec-query-native-tests))
  (printf "codec-query-native: ~a cases, ~a failures\n" codec-query-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
