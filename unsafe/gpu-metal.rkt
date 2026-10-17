#lang racket/base

;;;
;;; Unsafe Metal Resource Ingress
;;;

;; Exposes the native Metal resource-sharing entry points.
;; This explicitly unsafe public facade is the boundary where callers must satisfy the documented
;; external-object and synchronization contracts.

;;;
;;; Imports and Exports
;;;

;; UNSAFE: these inputs must be live Objective-C protocol objects. A protocol
;; check cannot make an arbitrary address, freed object or forged pointer safe.
(require "../private/gpu-metal-interop.rkt")
(provide make-metal-external-texture call-with-gpu-metal-device)
