#lang racket/base
(require "check.rkt" "../image-info.rkt" "../surface-properties.rkt")
(provide gpu-format-request gpu-format-label gpu-format-name
         gpu-staging-key gpu-config-value? gpu-cache-budget!)
(define names
  (hasheq 'rgba-8888 "RGBA8888" 'bgra-8888 "BGRA8888" 'rgb-888x "RGB888x"
          'alpha-8 "Alpha8" 'gray-8 "Gray8" 'rgb-565 "RGB565"
          'rgba-1010102 "RGBA1010102" 'rgba-f16 "RGBAF16" 'rgba-f32 "RGBAF32"))
(define (gpu-format-label color)
  (hash-ref names color (lambda () (raise-argument-error 'gpu-format-label "reviewed GPU pixel format" color))))
(define (gpu-format-name label)
  (or (for/first ([(k v) (in-hash names)] #:when (equal? v label)) k)
      (raise-argument-error 'gpu-format-name "reviewed GPU color label" label)))
(define (gpu-format-request who width height color alpha samples properties)
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error who "GPU targets must be nonempty" "width" width "height" height))
  (unless (memq alpha '(premul opaque))
    (raise-argument-error who "'premul or 'opaque GPU alpha type (unpremul is not a render target)" alpha))
  (unless (and (exact-nonnegative-integer? samples) (<= samples 64))
    (raise-argument-error who "exact requested sample count from 0 through 64" samples))
  (unless (surface-properties? properties)
    (raise-argument-error who "surface-properties?" properties))
  (define info (make-image-info width height #:color-type color #:alpha-type alpha))
  (image-info-storage-layout info) ; format-aware byte budget, including F32
  info)
(define (gpu-staging-key who width height color space samples properties)
  ;; Staging alpha must represent the clear and nested transparent groups.
  (unless (memq color '(rgba-8888 bgra-8888 rgba-f16 rgba-f32))
    (raise-argument-error who "RGBA8888, BGRA8888, F16 or F32 staging format" color))
  (gpu-format-request who width height color 'premul samples properties)
  (define info (make-image-info width height #:color-type color #:color-space space))
  ;; make-image-info copies ICC bytes. Never key by a closeable wrapper/address.
  (vector-immutable color 'premul (image-info-color-space info) samples
                    (surface-properties-flags properties)
                    (surface-properties-pixel-geometry properties)))
(define (gpu-config-value? v)
  (or (not v)
      (and (vector? v) (immutable? v) (= (vector-length v) 6)
           (memq (vector-ref v 0) '(rgba-8888 bgra-8888 rgba-f16 rgba-f32))
           (memq (vector-ref v 1) '(premul opaque))
           (color-space-descriptor? (vector-ref v 2))
           (exact-nonnegative-integer? (vector-ref v 3)) (<= (vector-ref v 3) 64)
           (exact-nonnegative-integer? (vector-ref v 4)) (<= (vector-ref v 4) 7)
           (memq (vector-ref v 5) '(unknown rgb-h bgr-h rgb-v bgr-v))
           #t)))
(define (gpu-cache-budget! who configuration width height)
  (when configuration
    (unless (gpu-config-value? configuration)
      (raise-argument-error who "detached GPU target configuration" configuration))
    (define info (make-image-info width height #:color-type (vector-ref configuration 0)
                                  #:alpha-type (vector-ref configuration 1)
                                  #:color-space (vector-ref configuration 2)))
    (image-info-storage-layout info))
  (void))
