#lang racket/base
(require rackunit "../main.rkt" "../private/surface-property-native.rkt")
(provide gpu-format-native-tests)
(define gpu-format-native-tests
  (test-suite "Surface properties (native; no GPU required)"
    (test-case "native properties preserve all reviewed flag and geometry combinations"
      (for* ([geometry '(unknown rgb-h bgr-h rgb-v bgr-v)] [flags (in-range 8)])
        (define p (make-surface-properties #:pixel-geometry geometry
                     #:device-independent-fonts? (bitwise-bit-set? flags 0)
                     #:dynamic-msaa? (bitwise-bit-set? flags 1)
                     #:always-dither? (bitwise-bit-set? flags 2)))
        (call-with-native-surface-properties 'test p
          (lambda (ptr) (check-equal? p (surface-properties/native 'test ptr))))))
    (test-case "native temporary cleanup survives an exception"
      (check-exn #rx"intentional"
        (lambda () (call-with-native-surface-properties 'test (make-surface-properties)
                     (lambda (_) (error 'test "intentional")))))
      (call-with-native-surface-properties 'test (make-surface-properties)
        (lambda (ptr) (check-equal? (surface-properties-flags (surface-properties/native 'test ptr)) 0))))
    (test-case "surface query is detached and does not delete borrowed properties"
      (with-skia ([s (make-surface 8 6)])
        (define a (surface-properties-of s)) (define b (surface-properties-of s))
        (check-equal? a b) (check-equal? a (make-surface-properties))
        (skia-close! s) (check-equal? (surface-properties-pixel-geometry a) 'unknown)))
    (test-case "closed surfaces reject property access"
      (with-skia ([s (make-surface 8 6)])
        (skia-close! s) (check-exn exn:fail? (lambda () (surface-properties-of s)))))
    (test-case "property access enforces execution ownership"
      (with-skia ([s (make-surface 8 6)])
        (define ch (make-channel))
        (define t (thread (lambda ()
          (channel-put ch (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                            (surface-properties-of s) 'unexpected)))))
        (check-eq? (channel-get ch) 'rejected) (thread-wait t)))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests gpu-format-native-tests)) (error 'gpu-formats "native tests failed")))
