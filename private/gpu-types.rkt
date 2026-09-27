#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))
;; Inventory only: the first probe uses Skia-owned targets, not imported FBOs.
;; Layouts match include/c/sk_types.h at mono/skia 40f75dc0051d14... (m119).
(define-cstruct _gr-gl-framebuffer-info ([id _uint32] [format _uint32] [protected? _stdbool]))
(define-cstruct _gr-gl-texture-info ([target _uint32] [id _uint32] [format _uint32] [protected? _stdbool]))
(define-cstruct _gr-mtl-texture-info ([texture _pointer]))
(define gr-opengl 0)
(define gr-metal 2)
(define gr-top-left 0)
(define gr-bottom-left 1)
