#lang racket/base

;;;
;;; Native Metal Interoperation
;;;

;; Binds Skia Metal texture wrapping and flush operations lazily.
;; Provides the native Skia bridge for external Metal resources.

(require (only-in "gpu-surface-native.rkt" checked-backend-resource/native))
(require ffi/unsafe racket/promise "gpu-types.rkt" "gpu-provider.rkt" "gpu-native-scope.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide metal-interop-native-check! metal-interop-native-inventory)

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; define-interop-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-interop-native name type)
  (begin
    (provide name)
    (define p (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (cons 'name p) bindings))
    (define (name . args)
      (define f (force p))
      (call-with-gpu-native-scope (lambda () (checked-backend-resource/native 'name args (lambda ()
        (apply f args))))))))

; gr_backendtexture_new_metal : (_fun _int _int _stdbool _gr-mtl-texture-info-pointer -> _pointer)
;   (FFI)
;   Calls the native gr_backendtexture_new_metal entry point using the declared FFI layout.
(define-interop-native gr_backendtexture_new_metal
  (_fun _int _int _stdbool _gr-mtl-texture-info-pointer -> _pointer))

; gr_backendtexture_delete : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendtexture_delete entry point using the declared FFI layout.
(define-interop-native gr_backendtexture_delete (_fun _pointer -> _void))

; gr_backendtexture_is_valid : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendtexture_is_valid entry point using the declared FFI layout.
(define-interop-native gr_backendtexture_is_valid (_fun _pointer -> _stdbool))

; gr_backendtexture_get_backend : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendtexture_get_backend entry point using the declared FFI layout.
(define-interop-native gr_backendtexture_get_backend (_fun _pointer -> _int))

; sk_image_new_from_texture : (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer ->
;   _pointer) (FFI)
;   Calls the native sk_image_new_from_texture entry point using the declared FFI layout.
(define-interop-native sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))

; sk_surface_new_backend_texture : (_fun _pointer _pointer _int _int _int _pointer _pointer ->
;   _pointer) (FFI)
;   Calls the native sk_surface_new_backend_texture entry point using the declared FFI layout.
(define-interop-native sk_surface_new_backend_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer -> _pointer))

; metal-interop-native-inventory : -> list?
;   Returns declaration-ordered Metal interoperation symbol availability and detached resolution
;   failures.
(define (metal-interop-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (hasheq 'name (symbol->string (car b))
                                                 'available #f 'error (exn-message e)))])
      (force (cdr b)) (hasheq 'name (symbol->string (car b)) 'available #t))))

; metal-interop-native-check! : -> void?
;   Rejects incomplete optional Metal interoperation support before resource handoff.
(define (metal-interop-native-check!)
  (unless (for/and ([b (in-list (metal-interop-native-inventory))]) (hash-ref b 'available))
    (gpu-unavailable 'metal-interop-symbols "missing optional Metal interop symbols"))
  (void))
