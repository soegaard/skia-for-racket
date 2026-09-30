#lang racket/base
(require ffi/unsafe racket/promise "gpu-provider.rkt" "gpu-native-scope.rkt"
         (only-in "native.rkt" skia-native-library-handle))
(provide gl-interop-native-check! gl-interop-native-inventory)
;; Separate, lazy, borrowed-only inventory. NO adopted-texture constructor.
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-interop-native safe native type)
  (begin
    (provide safe)
    (define pending (delay/sync (get-ffi-obj 'native (force library) type)))
    (set! bindings (cons (list 'native pending) bindings))
    (define (safe . args)
      (call-with-gpu-native-scope (lambda () (apply (force pending) args))))))
(define-interop-native borrowed-texture-descriptor/native gr_backendtexture_new_gl
  (_fun _int _int _stdbool _pointer -> _pointer))
(define-interop-native delete-texture-descriptor/native gr_backendtexture_delete
  (_fun _pointer -> _void))
(define-interop-native borrowed-texture-image/native sk_image_new_from_texture
  (_fun _pointer _pointer _int _int _int _pointer _pointer _pointer -> _pointer))
(define (gl-interop-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cadr b)) #t))))
(define (gl-interop-native-check!)
  (for ([b (in-list (reverse bindings))])
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'gl-interop-symbol "~a: ~a" (car b) (exn-message e)))])
      (force (cadr b))))
  (void))
