#lang racket/base
(require ffi/unsafe "../gpu.rkt" "core.rkt" "types.rkt" "lifetime.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-types.rkt" "gpu-io-trace.rkt"
         "gpu-interop-guard.rkt" "gpu-gl-interop-util.rkt" "gpu-gl-queries.rkt"
         "gpu-gl-interop-native.rkt" "gpu-surface-native.rkt" "gpu-image-native.rkt"
         (prefix-in n: "gpu-native.rkt")
         (submod "gpu-domain.rkt" gl-interop-internals)
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" gpu-image-internals))
(provide call-with-gpu-external-gl call-with-gpu-gl-framebuffer gpu-copy-gl-texture)
(define (context! who context)
  (when (or (current-gl-borrow?) (current-external-gl?))
    (error who "nested external GL handoff/borrowing is not supported"))
  (define d (context-domain who context))
  (define p (domain-pointer d))
  (unless (eq? (domain-backend d) 'opengl) (error who "an active OpenGL context is required"))
  (when (n:gr_direct_context_is_abandoned p)
    (domain-request-shutdown! d 'external-gl-context-lost)
    (error who "native GL context has been lost"))
  d)
(define (procedure! who thunk n)
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk n))
    (raise-argument-error who (format "procedure accepting ~a arguments" n) thunk)))
(define (reset! d) (n:gr_direct_context_reset_context (domain-pointer d) #xffffffff))
(define (call-with-gpu-external-gl context proc #:wait? [wait? #f])
  (define who 'call-with-gpu-external-gl)
  (procedure! who proc 0)
  (unless (boolean? wait?) (raise-argument-error who "boolean?" wait?))
  (define d (context! who context))
  ;; Issue all queued Skia commands BEFORE the host touches the same GL stream.
  ;; There is no promise of an application GL-state snapshot here.
  (gpu-flush-and-submit! context #:wait? wait?)
  (record-gpu-io! (hasheq 'kind "external-gl-begin" 'wait_requested wait?))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       void
       (lambda () (parameterize ([current-external-gl? #t]) (proc)))
       (lambda ()
         (parameterize-break #f
           (reset! d)
           (record-gpu-io! (hasheq 'kind "external-gl-end" 'skia_state_invalidated #t))))))))

(define (colorspace-pointer who space)
  (and space (call-with-owned who (list (color-space-h who space)) values)))
(define (close-borrow! context handles)
  (define d (context-domain 'gpu-gl-interop context))
  (parameterize-break #f
    (for ([h (in-list handles)] #:when h) (domain-resource-close! h))
    (domain-drain! d)))
(define (with-state d queries thunk)
  ;; On a native-context mismatch do not issue restoration calls into another
  ;; context. The caller violated the borrowing contract and must recover or
  ;; abandon before releasing its own GL names.
  ((gl-queries-with-bindings queries) thunk (lambda () (domain-pointer d))))

(define (call-with-gpu-gl-framebuffer context name width height proc
                                      #:origin [origin 'bottom-left]
                                      #:color-space [space #f]
                                      #:wait? [wait? #t])
  (define who 'call-with-gpu-gl-framebuffer)
  (check-gl-borrow-options who name width height origin wait?)
  (procedure! who proc 1)
  (define d (context! who context))
  (define queries (make-gl-queries (domain-gl-resolver d)))
  (define cp (colorspace-pointer who space))
  (gpu-surface-native-check! #t)
  ;; A nested activation is solely a lease boundary; the outer provider stays
  ;; active. The user only receives a canvas, never the borrowed surface/image.
  (call-with-gpu-context context
   (lambda ()
     (parameterize ([current-gl-borrow? #t])
       (define descriptor #f) (define handle #f)
       (define started? #f) (define borrowed-canvas #f)
       (dynamic-wind
         void
         (lambda ()
           (with-state d queries
            (lambda ()
              (gpu-flush-and-submit! context)
              (define info ((gl-queries-framebuffer queries) name width height))
              (reset! d)
              (dynamic-wind
                void
                (lambda ()
                  (parameterize-break #f
                    (set! descriptor
                      (domain-new-resource d 'borrowed-gl-framebuffer-description
                        (lambda () (make-backend-target/native width height 0 8
                                     (make-gr-gl-framebuffer-info name #x8058 #f)))
                        delete-backend-target/native #:keepalive context))
                    (unless (backend-target-valid?/native (resource-pointer descriptor))
                      (error who "Skia rejected the external framebuffer description"))
                    (set! handle
                      (domain-new-resource d 'surface
                        (lambda () (wrap-backend-target/native (domain-pointer d) (resource-pointer descriptor)
                                     (gl-origin-value who origin) rgba-8888 cp #f))
                        n:sk_surface_unref #:keepalive context)))
                  (define target
                    (make-gpu-surface-record handle width height '() context d cp
                      (hash-set* info 'origin (symbol->string origin) 'storage "gpu"
                                 'backend "opengl" 'context_generation (domain-generation d)
                                 'target_kind "borrowed-gl-framebuffer"
                                 'render_path "sk_surface_new_backend_render_target")))
                  (gpu-surface-info target) ; verifies the actual Ganesh context
                  (record-gpu-io! (hash-set* info 'kind "external-framebuffer-borrow"
                                             'origin (symbol->string origin) 'context_verified #t))
                  (set! started? #t)
                  (define canvas (surface-canvas target))
                  (set! borrowed-canvas canvas)
                  (begin0 (proc canvas)
                    (unless (= (canvas-save-count canvas) 1)
                      (error who "callback left unbalanced canvas saves or layers"))))
                (lambda ()
                  (parameterize-break #f
                    ;; Also submit issued commands after a callback exception.
                    ;; The GL stream is ordered before the host reuses storage.
                    (dynamic-wind
                      void
                      (lambda ()
                        (when borrowed-canvas
                          (let loop ()
                            (when (> (canvas-save-count borrowed-canvas) 1)
                              (canvas-restore! borrowed-canvas) (loop))))
                        (when started? (gpu-flush-and-submit! context #:wait? wait?)))
                      ;; Retire both references even if restoring/submitting
                      ;; fails. A wrong current context prevents draining but
                      ;; leaves queued jobs for explicit recovery/abandonment.
                      (lambda () (close-borrow! context (list handle descriptor))))
                    (define after ((gl-queries-framebuffer queries) name width height))
                    (unless (and (= (hash-ref after 'color_texture_id) (hash-ref info 'color_texture_id))
                                 (= (hash-ref after 'stencil_renderbuffer_id) (hash-ref info 'stencil_renderbuffer_id)))
                      (error who "external framebuffer attachment identities changed"))
                    (record-gpu-io! (hasheq 'kind "external-framebuffer-return" 'attachments_preserved #t
                                            'owns_host_framebuffer #f 'wait_requested wait?))))))))
         (lambda ()
           ;; with-state restored the saved bindings. Make Skia notice that.
           (reset! d)
           (void/reference-sink space)))))))

(define (gpu-copy-gl-texture context name width height
                             #:origin [origin 'bottom-left]
                             #:premultiplied? [premultiplied? #t]
                             #:color-space [space #f]
                             #:wait? [wait? #t])
  (define who 'gpu-copy-gl-texture)
  (check-gl-borrow-options who name width height origin wait?)
  (unless (boolean? premultiplied?) (raise-argument-error who "boolean?" premultiplied?))
  (define d (context! who context))
  (define queries (make-gl-queries (domain-gl-resolver d)))
  (define cp (colorspace-pointer who space))
  (gl-interop-native-check!) (gpu-image-native-check!)
  (define descriptor #f) (define handle #f) (define out #f) (define submitted? #f)
  (with-handlers ([(lambda (_) #t)
                   (lambda (e) (when out (skia-close! out)) (raise e))])
    (parameterize ([current-gl-borrow? #t])
      (dynamic-wind
        void
        (lambda ()
          (with-state d queries
           (lambda ()
             (gpu-flush-and-submit! context)
             (define description ((gl-queries-texture queries) name width height))
             (reset! d)
             (dynamic-wind
               void
               (lambda ()
                 (parameterize-break #f
                   (set! descriptor
                     (domain-new-resource d 'borrowed-gl-texture-description
                       (lambda () (borrowed-texture-descriptor/native width height #f
                                    (make-gr-gl-texture-info #x0DE1 name #x8058 #f)))
                       delete-texture-descriptor/native #:keepalive context))
                   (set! handle
                     (domain-new-resource d 'image
                       (lambda () (borrowed-texture-image/native (domain-pointer d) (resource-pointer descriptor)
                                    (gl-origin-value who origin) rgba-8888 (if premultiplied? 2 3) cp #f #f))
                       image-unref/native #:keepalive context)))
                 (define borrowed (make-image-record handle width height))
                 (unless (and (texture-backed?/native (resource-pointer handle))
                              (valid-image?/native (resource-pointer handle) (domain-pointer d)))
                   (error who "Skia rejected the borrowed texture for this context"))
                 (record-gpu-io! (hash-set* description 'kind "external-texture-copy"
                                            'origin (symbol->string origin) 'context_verified #t
                                            'cpu_readback #f 'aliases_source #f))
                 ;; A NEW Skia-owned allocation: returning a borrowed image would
                 ;; let shaders/pictures keep the external storage after scope.
                 (with-skia ([target (make-gpu-surface context width height #:color-space space)]
                             [paint (make-paint #:blend-mode 'src #:antialias? #f)])
                   (draw-image (surface-canvas target) borrowed 0 0 #:sampling 'nearest #:paint paint)
                   (set! out (gpu-surface-snapshot target))
                   (gpu-flush-and-submit! context #:wait? wait?)
                   (set! submitted? #t))
                 out)
               (lambda ()
                 (parameterize-break #f
                   ;; A failed allocation/draw may still have queued references.
                   (dynamic-wind
                     void
                     (lambda ()
                       (when (and handle (not submitted?)) (gpu-flush-and-submit! context #:wait? wait?)))
                     (lambda () (close-borrow! context (list handle descriptor))))
                   (record-gpu-io! (hasheq 'kind "external-texture-return"
                                           'owns_external_texture #f 'wait_requested wait?))))))))
        (lambda () (reset! d) (void/reference-sink space))))))
