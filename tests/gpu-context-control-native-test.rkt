#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe racket/list
         "../gpu-context-options.rkt" "../private/gpu-context-options-native.rkt"
         "../private/gpu-native.rkt" (only-in "../private/native.rkt" skia-check!))
(provide gpu-context-control-native-tests gpu-context-control-native-test-count)
(define (field p type offset) (ptr-ref p type 'abs offset))
(define gpu-context-control-native-test-count 12)
(define gpu-context-control-native-tests
  (test-suite "GPU context control ABI and symbol resolution (no GPU execution)"
    (test-case "pinned native baseline resolves" (skia-check!))
    (test-case "reviewed 64-bit record layout"
      (check-equal? (context-options-abi)
        (hasheq 'size 24 'alignment 8 'pointer_bytes 8 'bool_bytes 1 'offsets '(0 4 8 16 17 20))))
    (test-case "default fields at independent offsets"
      (call-with-native-context-options 'test (make-gpu-context-options)
        (lambda (p)
          (check-false (field p _stdbool 0)) (check-equal? (field p _int32 4) 256)
          (check-equal? (field p _size 8) 8388608) (check-true (field p _stdbool 16))
          (check-false (field p _stdbool 17)) (check-equal? (field p _int32 20) -1))))
    (test-case "nondefault fields are not permuted"
      (call-with-native-context-options 'test
        (make-gpu-context-options #:avoid-stencil-buffers? #t #:runtime-program-cache-size 19
          #:glyph-cache-texture-maximum-bytes 1234567 #:allow-path-mask-caching? #f
          #:manual-mipmapping? #t #:buffer-map-threshold 4096)
        (lambda (p)
          (check-true (field p _stdbool 0)) (check-equal? (field p _int32 4) 19)
          (check-equal? (field p _size 8) 1234567) (check-false (field p _stdbool 16))
          (check-true (field p _stdbool 17)) (check-equal? (field p _int32 20) 4096))))
    (test-case "size_t is not narrowed"
      (call-with-native-context-options 'test (make-gpu-context-options #:glyph-cache-texture-maximum-bytes #xffffffffffffffff)
        (lambda (p) (check-equal? (field p _size 8) #xffffffffffffffff))))
    (test-case "mapping sentinel and zero"
      (for ([n '(-1 0 2147483647)])
        (call-with-native-context-options 'test (make-gpu-context-options #:buffer-map-threshold n)
          (lambda (p) (check-equal? (field p _int32 20) n)))))
    (test-case "record survives collection"
      (call-with-native-context-options 'test (make-gpu-context-options)
        (lambda (p) (collect-garbage) (collect-garbage) (check-equal? (field p _size 8) 8388608))))
    (test-case "omitted descriptor is native null"
      (check-false (call-with-native-context-options 'test #f values)))
    (test-case "multiple return values are preserved"
      (check-equal? (call-with-values (lambda () (call-with-native-context-options 'test #f (lambda (_) (values 1 2)))) list) '(1 2)))
    (test-case "invalid options do not call consumer"
      (define called? #f)
      (check-exn exn:fail:contract? (lambda () (call-with-native-context-options 'test 'wrong (lambda (_) (set! called? #t)))))
      (check-false called?))
    (test-case "consumer error is not swallowed"
      (check-exn #rx"sentinel" (lambda () (call-with-native-context-options 'test (make-gpu-context-options) (lambda (_) (error 'test "sentinel"))))))
    (test-case "all six symbols and legacy factories resolve"
      (for ([backend '(opengl metal direct3d)]
            [factory '("gr_direct_context_make_gl" "gr_direct_context_make_metal" "gr_direct_context_make_direct3d")])
        (define inventory (gpu-native-inventory backend))
        (for ([name (in-list (list factory (string-append factory "_with_options")
                                  "gr_direct_context_flush_surface" "gr_direct_context_flush_image"
                                  "gr_direct_context_release_resources_and_abandon_context"))])
          (define row (findf (lambda (r) (equal? (hash-ref r 'name) name)) inventory))
          (check-not-false row)
          (check-true (and row (hash-ref row 'available)))))) ))
(module+ main
  (define failures (run-tests gpu-context-control-native-tests))
  (printf "gpu-context-control-native: ~a cases, ~a failures\n" gpu-context-control-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
