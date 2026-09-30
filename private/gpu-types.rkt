#lang racket/base
(require ffi/unsafe (only-in "gpu-backends.rkt" gpu-backend-native-id))
(provide (all-defined-out) gpu-backend-native-id)
;; Inventory only: the first probe uses Skia-owned targets, not imported FBOs.
;; Layouts match include/c/sk_types.h at mono/skia 40f75dc0051d14... (m119).
(define-cstruct _gr-gl-framebuffer-info ([id _uint32] [format _uint32] [protected? _stdbool]))
(define-cstruct _gr-gl-texture-info ([target _uint32] [id _uint32] [format _uint32] [protected? _stdbool]))
(define-cstruct _gr-mtl-texture-info ([texture _pointer]))
(define gr-opengl (gpu-backend-native-id 'opengl))
(define gr-metal (gpu-backend-native-id 'metal))
(define gr-direct3d (gpu-backend-native-id 'direct3d))
(define gr-top-left 0)
(define gr-bottom-left 1)

;; Compare real native identity with the owning domain, not a fixed GL tag.
;; gpu-backend-native-id is re-exported from the source-only registry.
