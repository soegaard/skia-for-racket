#lang racket/base
;; Safe operations on opaque, explicitly created external-resource handoffs.
;; The initial descriptor factory is in skia/unsafe/gpu-d3d12. Existing
;; skia/gpu-gl-interop remains source compatible; Metal factories come later.
(require "private/gpu-external.rkt")
(provide gpu-external-texture? gpu-external-texture-info gpu-external-texture-close!
         gpu-import-image call-with-gpu-external-surface)
