#lang racket/base

;;;
;;; GPU Resource Interoperability
;;;

;; Re-exports common GPU interoperability operations and guarded transfer support.
;; This public facade separates supported resource-sharing imports from private backend and lifetime
;; implementation modules.

;;;
;;; Imports and Exports
;;;

;; Safe operations on opaque, explicitly created external-resource handoffs.
;; Metal and Direct3D descriptor factories are in skia/unsafe/gpu-metal and
;; skia/unsafe/gpu-d3d12. The existing GL-specific API remains source compatible.
(require "private/gpu-external.rkt")
(provide gpu-external-texture? gpu-external-texture-info gpu-external-texture-close!
         gpu-import-image call-with-gpu-external-surface)
