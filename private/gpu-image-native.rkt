#lang racket/base

;;;
;;; Native GPU Image Operations
;;;

;; Binds image upload, texture conversion, and readback operations lazily.
;; Implements the native side of GPU image ownership and transfer.

(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-provider.rkt" "gpu-native-scope.rkt")
(provide gpu-image-native-check! gpu-image-native-inventory)
;; Pinned m119 C shim; intentionally not added to the CPU-required symbol set.
;; None of these calls invokes application release callbacks. Construction is
;; synchronous and kept atomic with reference registration by new-gpu-owned.
; library : promise?
;;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))
; bindings : list?
;;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())
; define-image-native : syntax transformer
;;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;;   inventory checks.
(define-syntax-rule (define-image-native name native-name type)
  (begin
    (provide name)
    (define delayed (delay/sync (get-ffi-obj 'native-name (force library) type)))
    (set! bindings (cons (cons 'native-name delayed) bindings))
    (define (name . args)
      (define call (force delayed))
      (call-with-gpu-native-scope (lambda () (apply call args))))))
; texture-image/native : (_fun _pointer _pointer _stdbool _stdbool -> _pointer) (FFI)
;;   Calls the native sk_image_make_texture_image entry point using the declared FFI layout.
(define-image-native texture-image/native sk_image_make_texture_image
  (_fun _pointer _pointer _stdbool _stdbool -> _pointer))
; snapshot/native : (_fun _pointer -> _pointer) (FFI)
;;   Calls the native sk_surface_new_image_snapshot entry point using the declared FFI layout.
(define-image-native snapshot/native sk_surface_new_image_snapshot
  (_fun _pointer -> _pointer))
; subset/native : (_fun _pointer _pointer _pointer -> _pointer) (FFI)
;;   Calls the native sk_image_make_subset entry point using the declared FFI layout.
(define-image-native subset/native sk_image_make_subset
  (_fun _pointer _pointer _pointer -> _pointer))
; texture-backed?/native : (_fun _pointer -> _stdbool) (FFI)
;;   Calls the native sk_image_is_texture_backed entry point using the declared FFI layout.
(define-image-native texture-backed?/native sk_image_is_texture_backed
  (_fun _pointer -> _stdbool))
; valid-image?/native : (_fun _pointer _pointer -> _stdbool) (FFI)
;;   Calls the native sk_image_is_valid entry point using the declared FFI layout.
(define-image-native valid-image?/native sk_image_is_valid
  (_fun _pointer _pointer -> _stdbool))
; image-id/native : (_fun _pointer -> _uint32) (FFI)
;;   Calls the native sk_image_get_unique_id entry point using the declared FFI layout.
(define-image-native image-id/native sk_image_get_unique_id
  (_fun _pointer -> _uint32))
; image-unref/native : (_fun _pointer -> _void) (FFI)
;;   Calls the native sk_image_unref entry point using the declared FFI layout.
(define-image-native image-unref/native sk_image_unref
  (_fun _pointer -> _void))
; gpu-image-native-inventory : -> list?
;;   Reports optional GPU-image symbol availability without performing image creation or transfer.
(define (gpu-image-native-inventory)
  (for/list ([entry (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car entry))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr entry)) #t))))
; gpu-image-native-check! : -> void?
;;   Requires the complete GPU-image binding set before native image operations begin.
(define (gpu-image-native-check!)
  (for ([entry (in-list (reverse bindings))])
    (with-handlers ([exn:fail?
                     (lambda (e) (gpu-unavailable 'gpu-image-symbol
                                  "~a: ~a" (car entry) (exn-message e)))])
      (force (cdr entry))))
  (void))

;; 0.72: explicit same-context filtering, not part of CPU-required symbols.
; filter-image/native : (_fun _pointer _pointer _pointer _pointer _pointer _pointer _pointer ->
;   _pointer) (FFI)
;;   Calls the native sk_image_make_with_filter entry point using the declared FFI layout.
(define-image-native filter-image/native sk_image_make_with_filter
  (_fun _pointer _pointer _pointer _pointer _pointer _pointer _pointer -> _pointer))
