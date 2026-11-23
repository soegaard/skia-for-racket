#lang racket/base

;;;
;;; Native Direct3D Interoperation
;;;

;; Binds native texture wrapping and synchronization entry points lazily.
;; Provides the Skia half of Direct3D resource interoperation.

(require (only-in "gpu-surface-native.rkt" checked-backend-resource/native))
;; Optional, lazy m119 C symbols. Not added to the CPU native registry.
(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-dxgi-types.rkt" "gpu-native-scope.rkt")
(provide interop-native-check! interop-native-inventory)

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bind : syntax transformer
;   Defines a lazy Direct3D interoperation call with native scope entry and checked backend
;   descriptor construction.
(define-syntax-rule (bind name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (cons 'name promise) bindings))
    (define (name . args) (call-with-gpu-native-scope (lambda () (checked-backend-resource/native
      'name args (lambda () (apply (force promise) args))))))))

; gr_backendtexture_new_direct3d : (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer) (FFI)
;   Calls the native gr_backendtexture_new_direct3d entry point using the declared FFI layout.
(bind gr_backendtexture_new_direct3d (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer))

; gr_backendtexture_delete : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendtexture_delete entry point using the declared FFI layout.
(bind gr_backendtexture_delete (_fun _pointer -> _void))

; gr_backendtexture_is_valid : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendtexture_is_valid entry point using the declared FFI layout.
(bind gr_backendtexture_is_valid (_fun _pointer -> _stdbool))

; gr_backendtexture_get_backend : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendtexture_get_backend entry point using the declared FFI layout.
(bind gr_backendtexture_get_backend (_fun _pointer -> _int))

; sk_image_new_from_texture : (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer ->
;   _pointer) (FFI)
;   Calls the native sk_image_new_from_texture entry point using the declared FFI layout.
(bind sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))

; interop-native-inventory : -> list?
;   Returns declaration-ordered Direct3D interoperation symbol availability and detached resolution
;   errors.
(define (interop-native-inventory)
  (for/list ([entry (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (hasheq 'name (symbol->string (car entry)) 'available #f
      'error (exn-message e)))])
      (force (cdr entry)) (hasheq 'name (symbol->string (car entry)) 'available #t))))

; interop-native-check! : -> void?
;   Rejects a missing Direct3D interoperation binding before an external texture handoff starts.
(define (interop-native-check!)
  (for ([row (in-list (interop-native-inventory))])
    (unless (hash-ref row 'available) (error 'd3d12-interop "unavailable native binding: ~a" (hash-ref
      row 'name))))
  (void))
