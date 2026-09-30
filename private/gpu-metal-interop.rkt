#lang racket/base
(require ffi/unsafe "../gpu.rkt" "core.rkt" "types.rkt" "lifetime.rkt"
         "gpu-types.rkt" "gpu-context.rkt" "gpu-domain.rkt" "gpu-metal-handles.rkt"
         "gpu-metal-interop-policy.rkt" "gpu-metal-interop-session.rkt"
         "gpu-metal-interop-system.rkt" "gpu-interop-cleanup.rkt"
         "gpu-interop-guard.rkt" "gpu-io-trace.rkt"
         (prefix-in i: "gpu-metal-interop-native.rkt")
         (prefix-in n: "gpu-native.rkt") (prefix-in im: "gpu-image-native.rkt")
         (only-in "check.rkt" check-dimensions)
         (submod "gpu-external.rkt" backend-internals)
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" gpu-image-internals))
(provide make-metal-external-texture call-with-gpu-metal-device)
(define quarantined-operations '())
(define (context! who context)
  (when (or (current-external-operation) (current-external-native?)
            (current-external-gl?) (current-gl-borrow?))
    (error who "nested native handoff/borrowing is not supported"))
  (define d (context-domain who context))
  (unless (eq? (domain-backend d) 'metal) (error who "an active Metal context is required"))
  (define p (domain-pointer d))
  (when (n:gr_direct_context_is_abandoned p)
    (domain-request-shutdown! d 'metal-context-lost)
    (error who "native Metal context is lost"))
  d)
(define (procedure! who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1)
               (let-values ([(required allowed) (procedure-keywords proc)]) (null? required)))
    (raise-argument-error who "one-argument procedure without required keywords" proc)))
(define (call-with-gpu-metal-device context proc)
  (procedure! 'call-with-gpu-metal-device proc)
  (define d (context! 'call-with-gpu-metal-device context))
  (call-with-metal-handles (domain-pointer d)
    (lambda (device _queue)
      ;; No private Ganesh queue is exposed. The caller may create its own
      ;; queue; retaining this device beyond the callback is an unsafe contract.
      (call-with-continuation-barrier
        (lambda () (parameterize ([current-external-native? #t]) (proc device)))))))
(define (space-pointer space)
  (and space (call-with-owned 'metal-interop (list (color-space-h 'metal-interop space)) values)))
(define (make-metal-external-texture context texture
          #:producer-command-buffer producer
          #:timeout-ms [timeout 5000] #:premultiplied? [premultiplied? #t]
          #:color-space [space #f])
  (metal-timeout! timeout)
  (unless (boolean? premultiplied?)
    (raise-argument-error 'make-metal-external-texture "boolean?" premultiplied?))
  (define d (context! 'make-metal-external-texture context))
  (space-pointer space)
  (i:metal-interop-native-check!)
  (define session #f) (define pin #f) (define ready? #f)
  (dynamic-wind void
    (lambda ()
      (parameterize-break #f
        (call-with-metal-handles (domain-pointer d)
          (lambda (device queue)
            (set! session (make-metal-session (load-metal-interop-ops device queue) texture producer timeout))))
        (set! pin (domain-new-resource d 'external-metal-texture
          (lambda () (metal-session-texture session))
          (lambda (_) (metal-session-close! session)) #:keepalive context)))
      (define desc (metal-session-description session))
      (define w (hash-ref desc 'width)) (define h (hash-ref desc 'height))
      (check-dimensions 'make-metal-external-texture w h)
      (define info (gpu-context-info context))
      (unless (and (<= w (hash-ref info 'max_texture_size)) (<= h (hash-ref info 'max_texture_size))
                   (<= w (hash-ref info 'max_render_target_size)) (<= h (hash-ref info 'max_render_target_size)))
        (error 'make-metal-external-texture "external texture exceeds the context limits"))
      (define t
        (make-external-texture 'metal context (domain-generation d)
          (hash-set* desc 'format_name "RGBA8888" 'origin "top-left"
            'ownership "retained-single-handoff" 'completion "bounded-synchronous"
            'premultiplied premultiplied? 'producer_coverage_verified #f)
          (lambda (mode)
            (domain-pointer d) (resource-pointer pin) (space-pointer space)
            (when (n:gr_direct_context_is_abandoned (domain-pointer d))
              (error 'metal-interop "native Metal context is lost"))
            (check-dimensions 'metal-interop w h)
            (metal-check-texture! desc (eq? mode 'surface))
            (when (and (eq? mode 'surface) (not premultiplied?))
              (error 'metal-interop "render targets require premultiplied alpha")))
          (lambda (mode proc) (operate context d session pin w h space premultiplied? mode proc))
          (lambda () (domain-resource-close! pin))
          (lambda () (metal-session-info session))))
      (set! ready? #t) t)
    (lambda ()
      (unless ready?
        (cond [pin (domain-resource-close! pin) (domain-drain! d)]
              [session (metal-session-close! session)])))))
(define (operate context d session pin w h space premultiplied? mode proc)
  (define descriptor #f) (define handle #f) (define target #f) (define out #f)
  (define began? #f) (define body-ok? #f) (define quarantined? #f)
  (define (quarantine! e)
    (unless quarantined?
      (set! quarantined? #t)
      (metal-session-quarantine! session e)
      (set! quarantined-operations
        (cons (list session pin descriptor handle target out space context e) quarantined-operations))
      (domain-request-shutdown! d 'metal-interop-indeterminate)))
  (call-with-gpu-context context
    (lambda ()
      (call-with-interop-cleanup
        (lambda ()
          ;; A wait failure is indeterminate: never release possibly in-flight
          ;; texture storage or let the same handoff be attempted again.
          (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine! e) (raise e))])
            (gpu-flush-and-submit! context)
            (metal-session-begin! session)
            (set! began? #t))
          (record-gpu-io! (hasheq 'kind "external-metal-producer-complete" 'wait_requested #t
                                  'producer_status 4 'cpu_pixel_readback #f))
          (define cp (space-pointer space))
          (parameterize-break #f
            (set! descriptor (i:gr_backendtexture_new_metal w h #f
                               (make-gr-mtl-texture-info (metal-session-texture session))))
            (unless (and descriptor (i:gr_backendtexture_is_valid descriptor)
                         (= (i:gr_backendtexture_get_backend descriptor) gr-metal))
              (error 'metal-interop "Skia rejected the actual Metal texture descriptor"))
            (set! handle
              (domain-new-resource d 'metal-interop-wrapper
                (lambda ()
                  (if (eq? mode 'copy)
                      (i:sk_image_new_from_texture (domain-pointer d) descriptor gr-top-left rgba-8888
                        (if premultiplied? 2 3) cp #f #f)
                      (i:sk_surface_new_backend_texture (domain-pointer d) descriptor gr-top-left 0 rgba-8888 cp #f)))
                (if (eq? mode 'copy) im:image-unref/native n:sk_surface_unref)
                #:keepalive context)))
          (case mode
            [(copy)
             (unless (and (im:texture-backed?/native (resource-pointer handle))
                          (im:valid-image?/native (resource-pointer handle) (domain-pointer d)))
               (error 'gpu-import-image "external texture did not produce a valid Metal image"))
             (define borrowed (make-image-record handle w h))
             ;; Never return a borrowed image: paints/pictures must retain only
             ;; an independent Skia-owned allocation, not the external storage.
             (with-skia ([surface (make-gpu-surface context w h #:color-space space)]
                         [paint (make-paint #:blend-mode 'src #:antialias? #f)])
               (draw-image (surface-canvas surface) borrowed 0 0 #:sampling 'nearest #:paint paint)
               (set! out (gpu-surface-snapshot surface)))
             (record-gpu-io! (hasheq 'kind "external-image-copy" 'backend "metal"
               'aliases_source #f 'cpu_readback #f 'skia_copy_draws 1))
             (set! body-ok? #t) out]
            [(surface)
             (set! target (make-gpu-surface-record handle w h '() context d cp
               (hasheq 'target_kind "external-metal-texture" 'origin "top-left"
                 'color_type "RGBA8888" 'alpha_type "premultiplied"
                 'requested_sample_count 0 'actual_sample_count 1
                 'render_path "sk_surface_new_backend_texture")))
             (gpu-surface-info target) ; checks native recording context/backend
             (define canvas (surface-canvas target))
             (record-gpu-io! (hasheq 'kind "external-surface-borrow" 'backend "metal" 'contents_preserved #t))
             (call-with-canvas-state canvas
               (lambda ()
                 (define floor (canvas-save-count canvas))
                 (begin0 (proc canvas)
                   (unless (= (canvas-save-count canvas) floor)
                     (error 'call-with-gpu-external-surface "callback left unbalanced canvas saves/layers")))))]))
        (lambda ()
          (metal-session-rethrow! session)
          (when began?
            ;; Metal has no caller-visible D3D12 state transition to normalize.
            ;; Submit on Ganesh's queue and observe a retained tail buffer on
            ;; that SAME queue. No waitUntilCompleted or CPU pixel staging.
            (gpu-flush-and-submit! context)
            (metal-session-complete! session)
            (record-gpu-io! (hasheq 'kind "external-metal-completion" 'wait_requested #t
              'completion_status 4 'same_ganesh_queue #t 'cpu_pixel_readback #f)))
          (when handle
            (define p handle) (set! handle #f) (domain-resource-close! p) (domain-drain! d))
          (when descriptor
            (define p descriptor) (set! descriptor #f) (i:gr_backendtexture_delete p))
          (when (and out (not body-ok?)) (skia-close! out) (set! out #f) (domain-drain! d))
          (domain-resource-close! pin) (domain-drain! d)
          (when began?
            (record-gpu-io! (hasheq 'kind "external-resource-return" 'backend "metal"
                                   'completion_verified #t 'cpu_readback #f)))
          (void/reference-sink space))
        quarantine!))))
