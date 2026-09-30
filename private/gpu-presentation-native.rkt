#lang racket/base
;; Additional optional presentation ABI; resolving Metal symbols must not become
;; a requirement for CPU-only or OpenGL-only installations.
(require ffi/unsafe racket/promise "gpu-native-scope.rkt" "gpu-provider.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide presentation-native-check! presentation-native-inventory)
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-call name symbol type)
  (begin
    (provide name)
    (define p (delay/sync (get-ffi-obj 'symbol (force library) type)))
    (set! bindings (cons (cons 'symbol p) bindings))
    (define (name . args)
      (define f (force p))
      (call-with-gpu-native-scope (lambda () (apply f args))))))
(define-call metal-backend-target/new gr_backendrendertarget_new_metal
  (_fun _int _int _pointer -> _pointer))
(define-call presentation-target/delete gr_backendrendertarget_delete (_fun _pointer -> _void))
(define-call presentation-target/valid? gr_backendrendertarget_is_valid (_fun _pointer -> _stdbool))
(define-call presentation-target/backend gr_backendrendertarget_get_backend (_fun _pointer -> _int))
(define-call presentation-target/samples gr_backendrendertarget_get_samples (_fun _pointer -> _int))
(define-call presentation-target/wrap sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))
(define (presentation-native-check!)
  (for ([b (in-list bindings)])
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'presentation-symbols "~a: ~a" (car b) (exn-message e)))])
      (force (cdr b))))
  (void))
(define (presentation-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr b)) #t))))
