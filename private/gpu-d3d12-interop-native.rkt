#lang racket/base
;; Optional, lazy m119 C symbols. Not added to the CPU native registry.
(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-dxgi-types.rkt" "gpu-native-scope.rkt")
(provide interop-native-check! interop-native-inventory)
(define bindings '())
(define library (delay/sync (skia-native-library-handle)))
(define-syntax-rule (bind name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (cons 'name promise) bindings))
    (define (name . args) (call-with-gpu-native-scope (lambda () (apply (force promise) args))))))
(bind gr_backendtexture_new_direct3d (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer))
(bind gr_backendtexture_delete (_fun _pointer -> _void))
(bind gr_backendtexture_is_valid (_fun _pointer -> _stdbool))
(bind gr_backendtexture_get_backend (_fun _pointer -> _int))
(bind sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))
(define (interop-native-inventory)
  (for/list ([entry (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (hasheq 'name (symbol->string (car entry)) 'available #f 'error (exn-message e)))])
      (force (cdr entry)) (hasheq 'name (symbol->string (car entry)) 'available #t))))
(define (interop-native-check!)
  (for ([row (in-list (interop-native-inventory))])
    (unless (hash-ref row 'available) (error 'd3d12-interop "unavailable native binding: ~a" (hash-ref row 'name))))
  (void))
