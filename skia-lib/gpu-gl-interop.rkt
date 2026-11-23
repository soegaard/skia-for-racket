#lang racket/base

;;;
;;; OpenGL Resource Interoperability
;;;

;; Exposes the supported OpenGL resource-sharing operations.
;; This public facade provides a stable import path for the private OpenGL interoperation
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Advanced explicit interoperability. GL names belong to the caller and are
;; meaningful only in the supplied context. No adoption or shared-context use.
(require "private/gpu-gl-interop.rkt")
(provide call-with-gpu-external-gl call-with-gpu-gl-framebuffer gpu-copy-gl-texture)
