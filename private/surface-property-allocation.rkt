#lang racket/base

;;;
;;; Temporary Native Surface Properties
;;;

;; Allocates surface properties for the duration of a native constructor call.
;; Shares property conversion between CPU and GPU constructors without depending on core resources.

(require "../surface-properties.rkt"
         (submod "../surface-properties.rkt" internals)
         "native.rkt" "lifetime.rkt")
(provide call-with-native-surface-properties)

; call-with-native-surface-properties : symbol? surface-properties? procedure? -> any
;   Creates temporary native properties and deletes them after the callback on every exit.
(define (call-with-native-surface-properties who properties proc)
  (unless (surface-properties? properties)
    (raise-argument-error who "surface-properties?" properties))
  (skia-check!)
  (define handle
    (new-owned who 'surface-properties
      (lambda ()
        (sk_surfaceprops_new (surface-properties-flags properties)
                            (properties->geometry-code properties)))
      sk_surfaceprops_delete))
  (call-with-scoped-resource handle
    (lambda (h) (owned-close! who h))
    (lambda (h) (call-with-owned who (list h) proc))))
