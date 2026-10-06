#lang racket/base
(require "../color4f.rkt" (submod "../color4f.rkt" internals)
         "core.rkt" "types.rkt" "lifetime.rkt" "image-info-native.rkt"
         (submod "core.rkt" color-internals))
(provide color4f-native native->color4f call-with-float-source-space)
(define (color4f-native who color)
  (checked-color4f who color)
  (make-sk-color4f (color4f-red color) (color4f-green color)
                   (color4f-blue color) (color4f-alpha color)))
(define (native->color4f value)
  (make-color4f (sk-color4f-r value) (sk-color4f-g value)
               (sk-color4f-b value) (sk-color4f-a value)))
(define (call-with-float-source-space who descriptor proc)
  ;; Color factories require a named/copied source interpretation, not #f and
  ;; not a live resource whose lifetime the caller might end halfway through.
  (when (not descriptor) (error who "an explicit source color-space descriptor is required"))
  (define space (descriptor->color-space descriptor))
  (call-with-skia-resource space
    (lambda (_)
      (call-with-owned who (list (color-space-h who space)) proc))))
