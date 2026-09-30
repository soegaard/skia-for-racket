#lang racket/base
;; Safe operations on opaque, explicitly created external-resource handoffs.
;; Metal and Direct3D descriptor factories are in skia/unsafe/gpu-metal and
;; skia/unsafe/gpu-d3d12. The existing GL-specific API remains source compatible.
(require "private/gpu-external.rkt")
(provide gpu-external-texture? gpu-external-texture-info gpu-external-texture-close!
         gpu-import-image call-with-gpu-external-surface)
