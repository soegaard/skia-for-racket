#lang racket/base

;;;
;;; Native Surface Properties
;;;

;; Converts surface-property descriptions and scopes temporary native records.
;; Supports consistent pixel geometry and flags across surface constructors.

(require "../surface-properties.rkt" (submod "../surface-properties.rkt" internals)
         "native.rkt" "core.rkt" "lifetime.rkt"
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" image-operation-internals))
(provide call-with-native-surface-properties surface-properties/native surface-properties-of)
; call-with-native-surface-properties : symbol? surface-properties? procedure? -> any
;;   Creates a temporary native properties object and deletes it after the callback on every exit.
(define (call-with-native-surface-properties who p proc)
  (unless (surface-properties? p) (raise-argument-error who "surface-properties?" p))
  (skia-check!)
  (call-with-native-temporary who 'surface-properties
    (lambda () (sk_surfaceprops_new (surface-properties-flags p) (properties->geometry-code p)))
    sk_surfaceprops_delete proc))
; surface-properties/native : symbol? cpointer? -> surface-properties?
;;   Copies flags and pixel geometry from a borrowed native properties pointer without deleting it.
(define (surface-properties/native who ptr)
  (unless ptr (error who "native surface has no properties"))
  ;; sk_surface_get_props is borrowed; only the temporary/new properties are deleted.
  (properties-from-native who (sk_surfaceprops_get_flags ptr)
                               (sk_surfaceprops_get_pixel_geometry ptr)))
; surface-properties-of : surface? -> surface-properties?
;;   Returns a detached copy of a live surface's native properties.
(define (surface-properties-of surface)
  (define who 'surface-properties-of)
  (call-with-owned who (list (surface-h who surface))
    (lambda (sp) (surface-properties/native who (sk_surface_get_props sp)))))
