#lang racket/base

;;;
;;; Floating-Point Color Conversion
;;;

;; Converts detached floating-point colors to native RGBA records and back.
;; Supplies the Color4f bridge used by high-precision drawing operations.

(require "../color4f.rkt" (submod "../color4f.rkt" internals)
         "core.rkt" "types.rkt" "lifetime.rkt" "image-info-native.rkt"
         (submod "core.rkt" color-internals))
(provide color4f-native native->color4f call-with-float-source-space)
; color4f-native : symbol? color4f? -> sk-color4f?
;;   Checks a detached floating-point color before copying its RGBA components into the native
;;   record.
(define (color4f-native who color)
  (checked-color4f who color)
  (make-sk-color4f (color4f-red color) (color4f-green color)
                   (color4f-blue color) (color4f-alpha color)))
; native->color4f : sk-color4f? -> color4f?
;;   Copies native RGBA components into a detached checked floating-point color value.
(define (native->color4f value)
  (make-color4f (sk-color4f-r value) (sk-color4f-g value)
               (sk-color4f-b value) (sk-color4f-a value)))
; call-with-float-source-space : symbol? any/c procedure? -> any
;;   Requires an explicit source color-space descriptor and retains its native interpretation for
;;   the callback.
(define (call-with-float-source-space who descriptor proc)
  ;; Color factories require a named/copied source interpretation, not #f and
  ;; not a live resource whose lifetime the caller might end halfway through.
  (when (not descriptor) (error who "an explicit source color-space descriptor is required"))
  (define space (descriptor->color-space descriptor))
  (call-with-skia-resource space
    (lambda (_)
      (call-with-owned who (list (color-space-h who space)) proc))))
