#lang racket/base
(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-provider.rkt" "gpu-native-scope.rkt")
(provide gpu-surface-native-check! gpu-surface-native-inventory)
;; Deliberately separate from the CPU symbol registry and the 0.38 probe.
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-surface-native group name native-name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'native-name (force library) type)))
    (set! bindings (cons (list 'group 'native-name promise) bindings))
    (define (name . args)
      (define call (force promise))
      (call-with-gpu-native-scope (lambda () (apply call args))))))
;; These calls cannot invoke application/Racket release callbacks in 0.39.
;; Native context pointers are not GC-managed. Readback descriptors and pixels
;; are explicitly malloc'ed raw storage, never moving Racket bytes/cstructs.
;; #:blocking? permits GC in other OS threads on CS; it is not an event loop.
(define-surface-native surface submit/native gr_direct_context_submit
  (_fun #:blocking? #t _pointer _stdbool -> _stdbool))
(define-surface-native surface flush/native gr_direct_context_flush
  (_fun #:blocking? #t _pointer -> _void))
(define-surface-native surface read-pixels/native sk_surface_read_pixels
  (_fun #:blocking? #t _pointer _pointer _pointer _size _int _int -> _stdbool))
(define-surface-native surface canvas-save-count/native sk_canvas_get_save_count
  (_fun _pointer -> _int))
(define-surface-native window make-backend-target/native gr_backendrendertarget_new_gl
  (_fun _int _int _int _int _pointer -> _pointer))
(define-surface-native window delete-backend-target/native gr_backendrendertarget_delete
  (_fun _pointer -> _void))
(define-surface-native window backend-target-valid?/native gr_backendrendertarget_is_valid
  (_fun _pointer -> _stdbool))
(define-surface-native window wrap-backend-target/native sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))
(define-surface-native window draw-surface/native sk_surface_draw
  (_fun _pointer _pointer _float _float _pointer -> _void))
(define (gpu-surface-native-check! [window? #f])
  (for ([binding (in-list (reverse bindings))]
        #:when (or window? (eq? (car binding) 'surface)))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (gpu-unavailable 'surface-symbols "missing GPU surface binding ~a: ~a"
                                        (cadr binding) (exn-message e)))])
      (force (caddr binding))))
  (void))

(define (gpu-surface-native-inventory [window? #f])
  (for/list ([binding (in-list (reverse bindings))]
             #:when (or window? (eq? (car binding) 'surface)))
    (hasheq 'name (symbol->string (cadr binding))
            'available (with-handlers ([exn:fail? (lambda (_) #f)])
                         (force (caddr binding)) #t))))
