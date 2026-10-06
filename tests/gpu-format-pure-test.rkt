#lang racket/base
(require rackunit "../surface-properties.rkt" (submod "../surface-properties.rkt" internals)
         "../image-info.rkt" "../private/check.rkt" "../private/gpu-format-util.rkt"
         "../private/gpu-frame-target-cache.rkt")
(provide gpu-format-pure-tests)
(define (key [color 'rgba-8888] [space #f] [samples 0] [p (make-surface-properties)])
  (gpu-staging-key 'test 8 6 color space samples p))
(define (with-cache proc)
  (define cache (make-frame-target-cache))
  (define made 0) (define retired '())
  (define (create) (set! made (add1 made)) made)
  (define (dispose v) (set! retired (cons v retired)))
  (define (use k [w 8] [h 6])
    (call-with-frame-target cache w h create dispose values #:configuration k))
  (dynamic-wind void (lambda () (proc cache use (lambda () made) (lambda () retired)))
                (lambda () (close-frame-target-cache! cache))))
(define gpu-format-pure-tests
  (test-suite "GPU format and surface property contracts (pure)"
    (test-case "default properties retain unknown geometry and zero flags"
      (define p (make-surface-properties))
      (check-eq? (surface-properties-pixel-geometry p) 'unknown)
      (check-equal? (surface-properties-flags p) 0)
      (check-equal? (properties->geometry-code p) 0))
    (test-case "all reviewed flags and geometries roundtrip as values"
      (for* ([g '(unknown rgb-h bgr-h rgb-v bgr-v)] [bits (in-range 8)])
        (define p (make-surface-properties #:pixel-geometry g
                     #:device-independent-fonts? (bitwise-bit-set? bits 0)
                     #:dynamic-msaa? (bitwise-bit-set? bits 1)
                     #:always-dither? (bitwise-bit-set? bits 2)))
        (check-equal? (properties-from-native 'test bits (properties->geometry-code p)) p)))
    (test-case "unknown native fields reject instead of losing bits"
      (check-exn exn:fail? (lambda () (properties-from-native 'test 8 0)))
      (check-exn exn:fail? (lambda () (properties-from-native 'test 0 5))))
    (test-case "geometry must be a reviewed symbol"
      (for ([v '(rgb horizontal 0 "unknown" #f)])
        (check-exn exn:fail? (lambda () (make-surface-properties #:pixel-geometry v)))))
    (test-case "flags are actual booleans"
      (check-exn exn:fail? (lambda () (make-surface-properties #:always-dither? 1)))
      (check-exn exn:fail? (lambda () (make-surface-properties #:dynamic-msaa? 'yes))))
    (test-case "property summaries are detached"
      (define h (surface-properties->jsexpr (make-surface-properties #:always-dither? #t)))
      (check-true (immutable? h)) (check-equal? (hash-ref h 'flags) 4))
    (test-case "format labels are reversible for all reviewed storage"
      (for ([c (in-vector pixel-formats)]) (check-eq? (gpu-format-name (gpu-format-label c)) c)))
    (test-case "unknown color formats reject"
      (check-exn exn:fail? (lambda () (gpu-format-label 'argb-4444)))
      (check-exn exn:fail? (lambda () (gpu-format-name "invented"))))
    (test-case "GPU size and alpha validation precede construction"
      (for ([a '(unpremul unknown #f)])
        (check-exn exn:fail? (lambda () (gpu-format-request 'test 8 6 'rgba-8888 a 0 (make-surface-properties)))))
      (for ([w '(0 -1 32769 2.5)])
        (check-exn exn:fail? (lambda () (gpu-format-request 'test w 6 'rgba-8888 'premul 0 (make-surface-properties))))))
    (test-case "non-alpha formats require opaque requests"
      (for ([c '(rgb-888x rgb-565 gray-8)])
        (check-exn exn:fail? (lambda () (gpu-format-request 'test 8 6 c 'premul 0 (make-surface-properties))))
        (check-true (image-info? (gpu-format-request 'test 8 6 c 'opaque 0 (make-surface-properties))))))
    (test-case "sample requests have a bounded exact representation"
      (for ([v '(-1 65 4.0 #t)])
        (check-exn exn:fail? (lambda () (key 'rgba-8888 #f v)))))
    (test-case "float targets charge their actual storage size"
      (parameterize ([current-skia-byte-limit 200])
        (check-true (image-info? (gpu-format-request 'test 8 6 'rgba-8888 'premul 0 (make-surface-properties))))
        (check-exn exn:fail? (lambda () (key 'rgba-f16)))
        (check-exn exn:fail? (lambda () (key 'rgba-f32)))))
    (test-case "staging only accepts full-color premultiplied formats"
      (for ([c '(rgb-565 gray-8 alpha-8 rgba-1010102)])
        (check-exn exn:fail? (lambda () (key c)))))
    (test-case "staging keys are structural, not wrapper identity"
      (check-equal? (key) (key))
      (check-equal? (key 'rgba-f16 'srgb 4 (make-surface-properties #:dynamic-msaa? #t))
                    (key 'rgba-f16 'srgb 4 (make-surface-properties #:dynamic-msaa? #t))))
    (test-case "ICC descriptors are copied into immutable keys"
      (define icc (make-bytes 128))
      (bytes-copy! icc 0 (integer->integer-bytes 128 4 #f #t))
      (bytes-copy! icc 36 #"acsp")
      (define k (key 'rgba-8888 icc))
      (bytes-set! icc 50 1)
      (check-equal? (bytes-ref (vector-ref k 2) 50) 0)
      (check-true (immutable? (vector-ref k 2))))
    (test-case "cache rejects mutable keys"
      (with-cache (lambda (cache use made retired)
        (check-exn exn:fail? (lambda () (use (vector 'mutable))))
        (check-equal? (made) 0))))
    (test-case "identical key reuses one staging target"
      (with-cache (lambda (cache use made retired)
        (check-equal? (use (key)) (use (key)))
        (check-equal? (made) 1) (check-equal? (retired) '()))))
    (test-case "same-size format changes retire before replacing"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use (key 'rgba-f16))
        (check-equal? (made) 2) (check-equal? (retired) '(1)))))
    (test-case "color interpretation changes retire even without a resize"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use (key 'rgba-8888 'srgb)) (use (key 'rgba-8888 'linear-srgb))
        (check-equal? (made) 3) (check-equal? (length (retired)) 2))))
    (test-case "sample requests change the compatibility key"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use (key 'rgba-8888 #f 4))
        (check-equal? (made) 2))))
    (test-case "properties change the compatibility key"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use (key 'rgba-8888 #f 0 (make-surface-properties #:pixel-geometry 'rgb-h)))
        (check-equal? (made) 2))))
    (test-case "alpha type participates even in private configured callers"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use '#(rgba-8888 opaque #f 0 0 unknown)) (check-equal? (made) 2))))
    (test-case "returning to a previous size is not a multi-entry pool"
      (with-cache (lambda (cache use made retired)
        (use (key)) (use (key) 9 7) (use (key))
        (check-equal? (made) 3) (check-equal? (length (retired)) 2))))
    (test-case "allocation limits are rechecked for configured hits"
      (with-cache (lambda (cache use made retired)
        (define cached-key (key 'rgba-f32))
        (use cached-key)
        (parameterize ([current-skia-byte-limit 200])
          (check-exn exn:fail? (lambda () (use cached-key))))
        (check-equal? (made) 1))))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests gpu-format-pure-tests)) (error 'gpu-formats "pure tests failed")))
