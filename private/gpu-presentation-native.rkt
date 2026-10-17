#lang racket/base

;;;
;;; Native GPU Presentation
;;;

;; Binds native flush and presentation-related operations lazily.
;; Connects presenter frame completion to backend-native submission.

;; Additional optional presentation ABI; resolving Metal symbols must not become
;; a requirement for CPU-only or OpenGL-only installations.
(require ffi/unsafe racket/promise "gpu-native-scope.rkt" "gpu-provider.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide presentation-native-check! presentation-native-inventory)
; library : promise?
;;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))
; bindings : list?
;;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())
; define-call : syntax transformer
;;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;;   inventory checks.
(define-syntax-rule (define-call name symbol type)
  (begin
    (provide name)
    (define p (delay/sync (get-ffi-obj 'symbol (force library) type)))
    (set! bindings (cons (cons 'symbol p) bindings))
    (define (name . args)
      (define f (force p))
      (call-with-gpu-native-scope (lambda () (apply f args))))))
; metal-backend-target/new : (_fun _int _int _pointer -> _pointer) (FFI)
;;   Calls the native gr_backendrendertarget_new_metal entry point using the declared FFI layout.
(define-call metal-backend-target/new gr_backendrendertarget_new_metal
  (_fun _int _int _pointer -> _pointer))
; presentation-target/delete : (_fun _pointer -> _void) (FFI)
;;   Calls the native gr_backendrendertarget_delete entry point using the declared FFI layout.
(define-call presentation-target/delete gr_backendrendertarget_delete (_fun _pointer -> _void))
; presentation-target/valid? : (_fun _pointer -> _stdbool) (FFI)
;;   Calls the native gr_backendrendertarget_is_valid entry point using the declared FFI layout.
(define-call presentation-target/valid? gr_backendrendertarget_is_valid (_fun _pointer -> _stdbool))
; presentation-target/backend : (_fun _pointer -> _int) (FFI)
;;   Calls the native gr_backendrendertarget_get_backend entry point using the declared FFI layout.
(define-call presentation-target/backend gr_backendrendertarget_get_backend (_fun _pointer -> _int))
; presentation-target/samples : (_fun _pointer -> _int) (FFI)
;;   Calls the native gr_backendrendertarget_get_samples entry point using the declared FFI layout.
(define-call presentation-target/samples gr_backendrendertarget_get_samples (_fun _pointer -> _int))
; presentation-target/wrap : (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer) (FFI)
;;   Calls the native sk_surface_new_backend_render_target entry point using the declared FFI
;;   layout.
(define-call presentation-target/wrap sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))
; presentation-native-check! : -> void?
;;   Requires the optional presentation entry points before creating or wrapping native frame
;;   targets.
(define (presentation-native-check!)
  (for ([b (in-list bindings)])
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'presentation-symbols "~a: ~a" (car b)
      (exn-message e)))])
      (force (cdr b))))
  (void))
; presentation-native-inventory : -> list?
;;   Reports presentation symbol availability without creating a window or proving driver support.
(define (presentation-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr b)) #t))))
