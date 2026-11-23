#lang racket/base

;;;
;;; GPU Format Native Test
;;;

;; Covers surface properties (native; no GPU required).
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;
(require rackunit "../main.rkt" "../private/surface-property-native.rkt"
         (only-in (submod "../private/core.rkt" gpu-surface-internals) canvas-owner))
(provide gpu-format-native-tests)

;;;
;;; Regression Suite
;;;

; gpu-format-native-tests : test-suite?
;   Collects the regression cases for surface properties (native; no GPU required).
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
        (lambda (ptr)
          (check-equal? (surface-properties-flags (surface-properties/native 'test ptr)) 0))))
    (test-case "surface query is detached and does not delete borrowed properties"
      (with-skia ([s (make-surface 8 6)])
        (define a (surface-properties-of s)) (define b (surface-properties-of s))
        (check-equal? a b) (check-equal? a (make-surface-properties))
        (skia-close! s) (check-equal? (surface-properties-pixel-geometry a) 'unknown))
      (for ([geometry '(unknown rgb-h bgr-h rgb-v bgr-v)])
        (define properties
          (make-surface-properties #:pixel-geometry geometry
                                   #:device-independent-fonts? #t #:always-dither? #t))
        (define info (make-image-info 8 6))
        (with-skia ([s (make-surface 8 6 #:surface-properties properties)]
                    [typed (make-surface-from-info info #:surface-properties properties)]
                    [buffer (make-raster-buffer-from-info info #:row-bytes 40)])
          (check-equal? (surface-properties-of s) properties)
          (check-equal? (surface-properties-of typed) properties)
          (define called? #f)
          (check-exn exn:fail:contract?
            (lambda ()
              (call-with-raster-buffer-canvas buffer (lambda (_) (set! called? #t))
                #:surface-properties #f)))
          (check-false called?)
          (check-exn exn:fail:contract?
            (lambda () (make-surface 8 6 #:surface-properties #f)))
          (check-exn exn:fail:contract?
            (lambda () (make-surface-from-info info #:surface-properties #f)))
          (define saved #f)
          (check-exn #rx"intentional"
            (lambda ()
              (call-with-raster-buffer-canvas buffer
                (lambda (c)
                  (set! saved c)
                  (check-equal? (surface-properties-of (canvas-owner 'test c)) properties)
                  (canvas-clear! c 'red)
                  (error 'test "intentional"))
                #:surface-properties properties)))
          (check-true (skia-closed? saved))
          (call-with-raster-buffer-pixmap buffer
            (lambda (v) (check-equal? (pixmap-pixel v 0 0) (rgb 255 0 0))))
          (check-equal?
           (call-with-values
            (lambda ()
              (call-with-raster-buffer-canvas buffer
                (lambda (c)
                  (check-equal? (surface-properties-of (canvas-owner 'test c))
                                (make-surface-properties))
                  (values 1 2)))) list)
           '(1 2)))))
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
