#lang racket/base
(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-path)
         "gpu-provider.rkt" "gpu-native-scope.rkt")
(provide gpu-image-native-check! gpu-image-native-inventory)
;; Pinned m119 C shim; intentionally not added to the CPU-required symbol set.
;; None of these calls invokes application release callbacks. Construction is
;; synchronous and kept atomic with reference registration by new-gpu-owned.
(define library (delay/sync (ffi-lib (skia-native-library-path))))
(define bindings '())
(define-syntax-rule (define-image-native name native-name type)
  (begin
    (provide name)
    (define delayed (delay/sync (get-ffi-obj 'native-name (force library) type)))
    (set! bindings (cons (cons 'native-name delayed) bindings))
    (define (name . args)
      (define call (force delayed))
      (call-with-gpu-native-scope (lambda () (apply call args))))))
(define-image-native texture-image/native sk_image_make_texture_image
  (_fun _pointer _pointer _stdbool _stdbool -> _pointer))
(define-image-native snapshot/native sk_surface_new_image_snapshot
  (_fun _pointer -> _pointer))
(define-image-native subset/native sk_image_make_subset
  (_fun _pointer _pointer _pointer -> _pointer))
(define-image-native texture-backed?/native sk_image_is_texture_backed
  (_fun _pointer -> _stdbool))
(define-image-native valid-image?/native sk_image_is_valid
  (_fun _pointer _pointer -> _stdbool))
(define-image-native image-id/native sk_image_get_unique_id
  (_fun _pointer -> _uint32))
(define-image-native image-unref/native sk_image_unref
  (_fun _pointer -> _void))
(define (gpu-image-native-inventory)
  (for/list ([entry (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car entry))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr entry)) #t))))
(define (gpu-image-native-check!)
  (for ([entry (in-list (reverse bindings))])
    (with-handlers ([exn:fail?
                     (lambda (e) (gpu-unavailable 'gpu-image-symbol
                                  "~a: ~a" (car entry) (exn-message e)))])
      (force (cdr entry))))
  (void))
