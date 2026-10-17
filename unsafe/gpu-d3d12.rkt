#lang racket/base

;;;
;;; Unsafe Direct3D Resource Ingress
;;;

;; Exposes the native Direct3D resource-sharing entry points.
;; This explicitly unsafe public facade is the boundary where callers must satisfy the documented
;; external-object and synchronization contracts.

;;;
;;; Imports and Exports
;;;

;; UNSAFE: inputs must be valid live COM pointers of the stated interface
;; types. QueryInterface cannot make an arbitrary/freed pointer safe.
(require "../private/gpu-d3d12-interop.rkt")
(provide make-d3d12-external-texture call-with-gpu-d3d12-device)
