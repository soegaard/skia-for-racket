#lang racket/base

;;;
;;; Native GPU Surface Operations
;;;

;; Binds render-target creation, wrapping, and surface queries lazily.
;; Provides native surface services to the public GPU resource layer.

;; The surface, window, and resource tags select separate readiness inventories. FFI signatures
;; preserve argument order and blocking declarations; they do not grant ownership or context access.
;; Callers retain native inputs through the call. Descriptor factories are additionally checked
;; against the requested dimensions, backend, and scalar GL identity before their pointers escape.

(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-provider.rkt" "gpu-native-scope.rkt")
(provide gpu-surface-native-check! gpu-surface-native-inventory)
;; Deliberately separate from the CPU symbol registry and the 0.38 probe.

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; define-surface-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-surface-native group name native-name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'native-name (force library) type)))
    (set! bindings (cons (list 'group 'native-name promise) bindings))
    (define (name . args)
      (define call (force promise))
      (call-with-gpu-native-scope
        (lambda () (checked-backend-resource/native 'native-name args (lambda () (apply call
          args))))))))
;; These calls cannot invoke application/Racket release callbacks in 0.39.
;; Native context pointers are not GC-managed. Readback descriptors and pixels
;; are explicitly malloc'ed raw storage, never moving Racket bytes/cstructs.
;; #:blocking? permits GC in other OS threads on CS; it is not an event loop.

; submit/native : (_fun #:blocking? #t _pointer _stdbool -> _stdbool) (FFI)
;   Calls the native gr_direct_context_submit entry point using the declared FFI layout.
(define-surface-native surface submit/native gr_direct_context_submit
  (_fun #:blocking? #t _pointer _stdbool -> _stdbool))

; flush/native : (_fun #:blocking? #t _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_flush entry point using the declared FFI layout.
(define-surface-native surface flush/native gr_direct_context_flush
  (_fun #:blocking? #t _pointer -> _void))

; read-pixels/native : (_fun #:blocking? #t _pointer _pointer _pointer _size _int _int -> _stdbool)
;   (FFI)
;   Calls the native sk_surface_read_pixels entry point using the declared FFI layout.
(define-surface-native surface read-pixels/native sk_surface_read_pixels
  (_fun #:blocking? #t _pointer _pointer _pointer _size _int _int -> _stdbool))

; canvas-save-count/native : (_fun _pointer -> _int) (FFI)
;   Calls the native sk_canvas_get_save_count entry point using the declared FFI layout.
(define-surface-native surface canvas-save-count/native sk_canvas_get_save_count
  (_fun _pointer -> _int))

; make-backend-target/native : (_fun _int _int _int _int _pointer -> _pointer) (FFI)
;   Calls the native gr_backendrendertarget_new_gl entry point using the declared FFI layout.
(define-surface-native window make-backend-target/native gr_backendrendertarget_new_gl
  (_fun _int _int _int _int _pointer -> _pointer))

; delete-backend-target/native : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendrendertarget_delete entry point using the declared FFI layout.
(define-surface-native window delete-backend-target/native gr_backendrendertarget_delete
  (_fun _pointer -> _void))

; backend-target-valid?/native : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendrendertarget_is_valid entry point using the declared FFI layout.
(define-surface-native window backend-target-valid?/native gr_backendrendertarget_is_valid
  (_fun _pointer -> _stdbool))

; wrap-backend-target/native : (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer)
;   (FFI)
;   Calls the native sk_surface_new_backend_render_target entry point using the declared FFI
;   layout.
(define-surface-native window wrap-backend-target/native sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))

; draw-surface/native : (_fun _pointer _pointer _float _float _pointer -> _void) (FFI)
;   Calls the native sk_surface_draw entry point using the declared FFI layout.
(define-surface-native window draw-surface/native sk_surface_draw
  (_fun _pointer _pointer _float _float _pointer -> _void))

; gpu-surface-native-check! : [any/c] -> void?
;   Requires surface symbols and, when requested, the separate window-target binding group.
(define (gpu-surface-native-check! [window? #f])
  (for ([binding (in-list (reverse bindings))]
        #:when (if window? (memq (car binding) '(surface window)) (eq? (car binding) 'surface)))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (gpu-unavailable 'surface-symbols "missing GPU surface binding ~a: ~a"
                                        (cadr binding) (exn-message e)))])
      (force (caddr binding))))
  (void))

; gpu-surface-native-inventory : [any/c] -> list?
;   Reports surface and optionally window-target symbol availability in declaration order.
(define (gpu-surface-native-inventory [window? #f])
  (for/list ([binding (in-list (reverse bindings))]
             #:when (if window? (memq (car binding) '(surface window)) (eq? (car binding) 'surface)))
    (hasheq 'name (symbol->string (cadr binding))
            'available (with-handlers ([exn:fail? (lambda (_) #f)])
                         (force (caddr binding)) #t))))

;; 0.73: scalar observation of native backend descriptors. These are not raw
;; resource ingress APIs. The constructors remain behind existing scoped hosts.

; texture-width/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendtexture_get_width entry point using the declared FFI layout.
(define-surface-native resource texture-width/native gr_backendtexture_get_width
  (_fun _pointer -> _int))

; texture-height/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendtexture_get_height entry point using the declared FFI layout.
(define-surface-native resource texture-height/native gr_backendtexture_get_height
  (_fun _pointer -> _int))

; texture-mipmaps?/native : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendtexture_has_mipmaps entry point using the declared FFI layout.
(define-surface-native resource texture-mipmaps?/native gr_backendtexture_has_mipmaps
  (_fun _pointer -> _stdbool))

; texture-backend/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendtexture_get_backend entry point using the declared FFI layout.
(define-surface-native resource texture-backend/native gr_backendtexture_get_backend
  (_fun _pointer -> _int))

; texture-valid?/native : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendtexture_is_valid entry point using the declared FFI layout.
(define-surface-native resource texture-valid?/native gr_backendtexture_is_valid
  (_fun _pointer -> _stdbool))

; texture-gl-info/native : (_fun _pointer _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendtexture_get_gl_textureinfo entry point using the declared FFI
;   layout.
(define-surface-native resource texture-gl-info/native gr_backendtexture_get_gl_textureinfo
  (_fun _pointer _pointer -> _stdbool))

; texture-delete/native : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendtexture_delete entry point using the declared FFI layout.
(define-surface-native resource texture-delete/native gr_backendtexture_delete
  (_fun _pointer -> _void))

; target-width/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_width entry point using the declared FFI layout.
(define-surface-native resource target-width/native gr_backendrendertarget_get_width
  (_fun _pointer -> _int))

; target-height/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_height entry point using the declared FFI layout.
(define-surface-native resource target-height/native gr_backendrendertarget_get_height
  (_fun _pointer -> _int))

; target-samples/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_samples entry point using the declared FFI layout.
(define-surface-native resource target-samples/native gr_backendrendertarget_get_samples
  (_fun _pointer -> _int))

; target-stencils/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_stencils entry point using the declared FFI layout.
(define-surface-native resource target-stencils/native gr_backendrendertarget_get_stencils
  (_fun _pointer -> _int))

; target-backend/native : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_backend entry point using the declared FFI layout.
(define-surface-native resource target-backend/native gr_backendrendertarget_get_backend
  (_fun _pointer -> _int))

; target-gl-info/native : (_fun _pointer _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendrendertarget_get_gl_framebufferinfo entry point using the declared
;   FFI layout.
(define-surface-native resource target-gl-info/native gr_backendrendertarget_get_gl_framebufferinfo
  (_fun _pointer _pointer -> _stdbool))
(provide checked-backend-resource/native gpu-backend-resource-native-inventory)

; gpu-backend-resource-native-inventory : -> list?
;   Reports scalar backend-descriptor query availability without exposing raw resource ingress.
(define (gpu-backend-resource-native-inventory)
  (for/list ([binding (in-list (reverse bindings))] #:when (eq? (car binding) 'resource))
    (hasheq 'name (symbol->string (cadr binding))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (caddr binding)) #t))))

; same-gl-info? : symbol? procedure? cpointer? cpointer? exact-positive-integer? -> boolean?
;   Compares declared GL descriptor fields after a native round trip, ignoring padding and
;   pointer-wrapper identity.
(define (same-gl-info? who getter ptr original count)
  ;; m119 GL texture info = 3 uint32; GL framebuffer info = 2 uint32.
  ;; Compare scalar fields, not padding or native pointer identity.
  (define data (malloc (* 4 count) 'raw))
  (unless data (error who "GL descriptor observation allocation failed"))
  (dynamic-wind void
    (lambda ()
      (memset data 0 (* 4 count))
      (and (getter ptr data)
           (for/and ([i (in-range count)]) (= (ptr-ref data _uint32 i) (ptr-ref original _uint32
             i)))))
    (lambda () (free data))))

; checked-backend-resource/native : symbol? list? procedure? -> (or/c #f cpointer?)
;   Validates newly constructed backend descriptors against scoped inputs and deletes mismatching
;   wrappers on failure.
(define (checked-backend-resource/native name args create)
  (define texture-backend
    (case name [(gr_backendtexture_new_gl) 0] [(gr_backendtexture_new_metal) 1]
               [(gr_backendtexture_new_direct3d) 3] [else #f]))
  (define target? (eq? name 'gr_backendrendertarget_new_gl))
  (cond
    [(or texture-backend target?)
     (define ptr (create))
     (cond
       [(not ptr) #f]
       [else
        (with-handlers ([(lambda (_) #t)
                        (lambda (e)
                          (if target? (delete-backend-target/native ptr) (texture-delete/native ptr))
                          (raise e))])
          (define width (car args)) (define height (cadr args))
          (define valid?
            (if target?
                (and (backend-target-valid?/native ptr)
                     (= width (target-width/native ptr)) (= height (target-height/native ptr))
                     (= 0 (target-backend/native ptr))
                     ;; GrBackendRenderTarget reports at least one sample even
                     ;; when GL's single-sample framebuffer is described with 0.
                     (= (target-samples/native ptr) (max 1 (list-ref args 2)))
                     (= (target-stencils/native ptr) (list-ref args 3))
                     (same-gl-info? name target-gl-info/native ptr (list-ref args 4) 2))
                (and (texture-valid?/native ptr)
                     (= width (texture-width/native ptr)) (= height (texture-height/native ptr))
                     (= texture-backend (texture-backend/native ptr))
                     (or (= texture-backend 3) (eq? (caddr args) (texture-mipmaps?/native ptr)))
                     (or (not (= texture-backend 0))
                         (same-gl-info? name texture-gl-info/native ptr (list-ref args 3) 3)))))
          (unless valid? (error name "native backend descriptor disagrees with scoped input"))
          ptr)])]
    [else (create)]))
