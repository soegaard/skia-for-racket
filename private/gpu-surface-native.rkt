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
      (call-with-gpu-native-scope
        (lambda () (checked-backend-resource/native 'native-name args (lambda () (apply call args))))))))
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
        #:when (if window? (memq (car binding) '(surface window)) (eq? (car binding) 'surface)))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (gpu-unavailable 'surface-symbols "missing GPU surface binding ~a: ~a"
                                        (cadr binding) (exn-message e)))])
      (force (caddr binding))))
  (void))

(define (gpu-surface-native-inventory [window? #f])
  (for/list ([binding (in-list (reverse bindings))]
             #:when (if window? (memq (car binding) '(surface window)) (eq? (car binding) 'surface)))
    (hasheq 'name (symbol->string (cadr binding))
            'available (with-handlers ([exn:fail? (lambda (_) #f)])
                         (force (caddr binding)) #t))))

;; 0.73: scalar observation of native backend descriptors. These are not raw
;; resource ingress APIs. The constructors remain behind existing scoped hosts.
(define-surface-native resource texture-width/native gr_backendtexture_get_width (_fun _pointer -> _int))
(define-surface-native resource texture-height/native gr_backendtexture_get_height (_fun _pointer -> _int))
(define-surface-native resource texture-mipmaps?/native gr_backendtexture_has_mipmaps (_fun _pointer -> _stdbool))
(define-surface-native resource texture-backend/native gr_backendtexture_get_backend (_fun _pointer -> _int))
(define-surface-native resource texture-valid?/native gr_backendtexture_is_valid (_fun _pointer -> _stdbool))
(define-surface-native resource texture-gl-info/native gr_backendtexture_get_gl_textureinfo (_fun _pointer _pointer -> _stdbool))
(define-surface-native resource texture-delete/native gr_backendtexture_delete (_fun _pointer -> _void))
(define-surface-native resource target-width/native gr_backendrendertarget_get_width (_fun _pointer -> _int))
(define-surface-native resource target-height/native gr_backendrendertarget_get_height (_fun _pointer -> _int))
(define-surface-native resource target-samples/native gr_backendrendertarget_get_samples (_fun _pointer -> _int))
(define-surface-native resource target-stencils/native gr_backendrendertarget_get_stencils (_fun _pointer -> _int))
(define-surface-native resource target-backend/native gr_backendrendertarget_get_backend (_fun _pointer -> _int))
(define-surface-native resource target-gl-info/native gr_backendrendertarget_get_gl_framebufferinfo (_fun _pointer _pointer -> _stdbool))
(provide checked-backend-resource/native gpu-backend-resource-native-inventory)
(define (gpu-backend-resource-native-inventory)
  (for/list ([binding (in-list (reverse bindings))] #:when (eq? (car binding) 'resource))
    (hasheq 'name (symbol->string (cadr binding))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (caddr binding)) #t))))
(define (same-gl-info? who getter ptr original count)
  ;; m119 GL texture info = 3 uint32; GL framebuffer info = 2 uint32.
  ;; Compare scalar fields, not padding or native pointer identity.
  (define data (malloc (* 4 count) 'raw))
  (unless data (error who "GL descriptor observation allocation failed"))
  (dynamic-wind void
    (lambda ()
      (memset data 0 (* 4 count))
      (and (getter ptr data)
           (for/and ([i (in-range count)]) (= (ptr-ref data _uint32 i) (ptr-ref original _uint32 i)))))
    (lambda () (free data))))
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
