#lang racket/base

;;;
;;; Native OpenGL Interoperation
;;;

;; Binds backend texture and render-target operations lazily.
;; Provides the Skia FFI bridge for imported GL resources.

(require (only-in "gpu-surface-native.rkt" checked-backend-resource/native))
(require ffi/unsafe racket/promise "gpu-provider.rkt" "gpu-native-scope.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide gl-interop-native-check! gl-interop-native-inventory)
;; Separate, lazy, borrowed-only inventory. NO adopted-texture constructor.

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; define-interop-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-interop-native safe native type)
  (begin
    (provide safe)
    (define pending (delay/sync (get-ffi-obj 'native (force library) type)))
    (set! bindings (cons (list 'native pending) bindings))
    (define (safe . args)
      (call-with-gpu-native-scope (lambda () (checked-backend-resource/native 'native args (lambda ()
        (apply (force pending) args))))))))

; borrowed-texture-descriptor/native : (_fun _int _int _stdbool _pointer -> _pointer) (FFI)
;   Calls the native gr_backendtexture_new_gl entry point using the declared FFI layout.
(define-interop-native borrowed-texture-descriptor/native gr_backendtexture_new_gl
  (_fun _int _int _stdbool _pointer -> _pointer))

; delete-texture-descriptor/native : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendtexture_delete entry point using the declared FFI layout.
(define-interop-native delete-texture-descriptor/native gr_backendtexture_delete
  (_fun _pointer -> _void))

; borrowed-texture-image/native : (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer
;   -> _pointer) (FFI)
;   Calls the native sk_image_new_from_texture entry point using the declared FFI layout.
(define-interop-native borrowed-texture-image/native sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))

; gl-interop-native-inventory : -> list?
;   Reports optional GL interoperation symbol availability in declaration order without creating a
;   context.
(define (gl-interop-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cadr b)) #t))))

; gl-interop-native-check! : -> void?
;   Resolves every required GL interoperation symbol and reports missing bindings as GPU
;   unavailability.
(define (gl-interop-native-check!)
  (for ([b (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'gl-interop-symbol "~a: ~a" (car b)
      (exn-message e)))])
      (force (cadr b))))
  (void))
