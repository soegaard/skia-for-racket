#lang racket/base
(require (only-in "gpu-surface-native.rkt" checked-backend-resource/native))
(require ffi/unsafe racket/promise "gpu-types.rkt" "gpu-provider.rkt" "gpu-native-scope.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide metal-interop-native-check! metal-interop-native-inventory)
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-interop-native name type)
  (begin
    (provide name)
    (define p (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (cons 'name p) bindings))
    (define (name . args)
      (define f (force p))
      (call-with-gpu-native-scope (lambda () (checked-backend-resource/native 'name args (lambda () (apply f args))))))))
(define-interop-native gr_backendtexture_new_metal
  (_fun _int _int _stdbool _gr-mtl-texture-info-pointer -> _pointer))
(define-interop-native gr_backendtexture_delete (_fun _pointer -> _void))
(define-interop-native gr_backendtexture_is_valid (_fun _pointer -> _stdbool))
(define-interop-native gr_backendtexture_get_backend (_fun _pointer -> _int))
(define-interop-native sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))
(define-interop-native sk_surface_new_backend_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer -> _pointer))
(define (metal-interop-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (hasheq 'name (symbol->string (car b))
                                                 'available #f 'error (exn-message e)))])
      (force (cdr b)) (hasheq 'name (symbol->string (car b)) 'available #t))))
(define (metal-interop-native-check!)
  (unless (for/and ([b (in-list (metal-interop-native-inventory))]) (hash-ref b 'available))
    (gpu-unavailable 'metal-interop-symbols "missing optional Metal interop symbols"))
  (void))
