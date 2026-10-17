#lang racket/base

;;;
;;; GPU Texture Native Layouts
;;;

;; Defines GL framebuffer, GL texture, and Metal texture information records.
;; Keeps texture wrapping aligned with the pinned Ganesh ABI.

(require ffi/unsafe (only-in "gpu-backends.rkt" gpu-backend-native-id))
(provide (all-defined-out) gpu-backend-native-id)
;; Inventory only: the first probe uses Skia-owned targets, not imported FBOs.
;; Layouts match include/c/sk_types.h at mono/skia 40f75dc0051d14... (m119).
(define-cstruct _gr-gl-framebuffer-info ([id _uint32] [format _uint32] [protected? _stdbool]))
;; Fields:
;;   id: unsigned OpenGL framebuffer object name. format: native GL internal-format enum.
;;   protected?: C boolean. The GL object remains application-owned and must stay valid for the
;;   wrapping scope.

(define-cstruct _gr-gl-texture-info ([target _uint32] [id _uint32] [format _uint32] [protected?
  _stdbool]))
;; Fields:
;;   target: GL texture-target enum. id: unsigned texture object name. format: native internal
;;   format. protected?: C boolean. Order matches the native Ganesh texture description; the texture
;;   is borrowed, not transferred.

(define-cstruct _gr-mtl-texture-info ([texture _pointer]))
;; Fields:
;;   texture: borrowed Objective-C MTLTexture pointer. The external owner/session retains the object
;;   for the complete Skia wrapping scope.

; gr-opengl : exact-nonnegative-integer?
;;   Selects the reviewed native Ganesh backend identifier for OpenGL.
(define gr-opengl (gpu-backend-native-id 'opengl))
; gr-metal : exact-nonnegative-integer?
;;   Selects the reviewed native Ganesh backend identifier for Metal.
(define gr-metal (gpu-backend-native-id 'metal))
; gr-direct3d : exact-nonnegative-integer?
;;   Selects the reviewed native Ganesh backend identifier for Direct3D 12.
(define gr-direct3d (gpu-backend-native-id 'direct3d))
; gr-top-left : exact-nonnegative-integer?
;;   Identifies top-left surface origin in the native Ganesh origin enumeration.
(define gr-top-left 0)
; gr-bottom-left : exact-nonnegative-integer?
;;   Identifies bottom-left surface origin in the native Ganesh origin enumeration.
(define gr-bottom-left 1)

;; Compare real native identity with the owning domain, not a fixed GL tag.
;; gpu-backend-native-id is re-exported from the source-only registry.
