#lang racket/base
(require "../surface-properties.rkt" (submod "../surface-properties.rkt" internals)
         "native.rkt" "core.rkt" "lifetime.rkt"
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" image-operation-internals))
(provide call-with-native-surface-properties surface-properties/native surface-properties-of)
(define (call-with-native-surface-properties who p proc)
  (unless (surface-properties? p) (raise-argument-error who "surface-properties?" p))
  (skia-check!)
  (call-with-native-temporary who 'surface-properties
    (lambda () (sk_surfaceprops_new (surface-properties-flags p) (properties->geometry-code p)))
    sk_surfaceprops_delete proc))
(define (surface-properties/native who ptr)
  (unless ptr (error who "native surface has no properties"))
  ;; sk_surface_get_props is borrowed; only the temporary/new properties are deleted.
  (properties-from-native who (sk_surfaceprops_get_flags ptr)
                               (sk_surfaceprops_get_pixel_geometry ptr)))
(define (surface-properties-of surface)
  (define who 'surface-properties-of)
  (call-with-owned who (list (surface-h who surface))
    (lambda (sp) (surface-properties/native who (sk_surface_get_props sp)))))
