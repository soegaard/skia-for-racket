#lang racket/base
(require "../image-info.rkt" (submod "../image-info.rkt" internals)
         "core.rkt" "native.rkt" "types.rkt" "lifetime.rkt"
         (submod "core.rkt" color-internals))
(provide color-space->descriptor descriptor->color-space
         call-with-image-info-native borrowed-color-space->descriptor)
(define (descriptor->color-space descriptor)
  (define d (copy-descriptor 'descriptor->color-space descriptor))
  (case d
    [(#f) #f]
    [(srgb) (make-srgb-color-space)]
    [(linear-srgb) (make-linear-srgb-color-space)]
    [else (color-space-from-icc-bytes d)]))
(define (color-space->descriptor space)
  (unless (color-space? space) (raise-argument-error 'color-space->descriptor "color-space?" space))
  (cond
    [(color-space-srgb? space) 'srgb]
    [else
     (with-skia ([linear (make-linear-srgb-color-space)])
       (if (color-space=? space linear) 'linear-srgb
           (copy-descriptor 'color-space->descriptor (color-space->icc-bytes space))))]))
(define (borrowed-color-space->descriptor who pointer)
  (and pointer
       (with-skia ([space (wrap-owned-color-space who
                            (lambda () (sk_colorspace_ref pointer) pointer))])
         (color-space->descriptor space))))
(define (call-with-image-info-native who info proc)
  (check-info who info)
  (define space (descriptor->color-space (image-info-color-space info)))
  (dynamic-wind void
    (lambda ()
      (call-with-owned who (if space (list (color-space-h who space)) '())
        (lambda pointers
          (define cp (and space (car pointers)))
          (define native
            (make-sk-image-info cp (image-info-width info) (image-info-height info)
                                (vector-ref (format-data who (image-info-color-type info)) 0)
                                (case (image-info-alpha-type info) [(opaque) 1] [(premul) 2] [(unpremul) 3])))
          (proc native cp))))
    (lambda () (when space (skia-close! space)))))
