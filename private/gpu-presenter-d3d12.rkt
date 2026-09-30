#lang racket/base
;; Draw-only swap-chain surfaces are private and frame-scoped. The public
;; frame exposes only the ordinary canvas, never a SkSurface/back-buffer COM
;; object that could be snapshotted or read back behind this state protocol.
(require ffi/unsafe
         "../gpu.rkt" "core.rkt" "types.rkt" "gpu-types.rkt"
         "gpu-context.rkt" "gpu-domain.rkt" "gpu-driver-d3d12.rkt"
         "gpu-dxgi-system.rkt" "gpu-dxgi-types.rkt" "gpu-dxgi-util.rkt"
         "lifetime.rkt" "gpu-io-trace.rkt" "gpu-presentation-cleanup.rkt"
         (prefix-in n: "gpu-native.rkt")
         (submod "core.rkt" gpu-surface-internals)
         (submod "gpu-presenter.rkt" adapter-internals))
(provide make-d3d12-presentation-adapter)
;; Explicit test-only capture: D3D12 CopyTextureRegion + READBACK heap, not a
;; Skia surface read. Never installed by the production GUI/presenter factory.
(define current-dxgi-capture-hook (make-parameter #f))
(module* testing #f (provide current-dxgi-capture-hook))
(define (make-d3d12-presentation-adapter hwnd gui-measure post background selection index sync)
  (dxgi-sync-interval! sync)
  (n:gpu-native-check! 'dxgi)
  (define device #f) (define queue #f)
  (define-values (provider driver)
    (make-owned-d3d12-components selection index
      #:receive-handles (lambda (_adapter dev q) (set! device dev) (set! queue q))))
  (define context (wrap-gpu-domain (make-gpu-domain provider driver)))
  (define d (context-domain 'direct3d-presentation context))
  (define host #f) (define pin #f) (define space #f) (define ok? #f)
  (define quarantined '())
  (define (retire-skia!)
    ;; Resize/close only, never a normal frame. Drop Ganesh's indirect resource
    ;; references before DXGI ResizeBuffers releases/replaces the old buffers.
    (n:gr_direct_context_flush (domain-pointer d))
    (unless (n:gr_direct_context_submit (domain-pointer d) #t)
      (error 'direct3d-presentation "Ganesh retirement could not complete"))
    (n:gr_direct_context_free_gpu_resources (domain-pointer d)))
  (dynamic-wind void
    (lambda ()
      (set! host (make-dxgi-host device queue hwnd sync))
      ;; A live presenter pins its context. A caller cannot close the context
      ;; obtained through gpu-presenter-context beneath a live DXGI swap chain.
      (set! pin
        (call-with-gpu-context context
          (lambda ()
            (domain-new-resource d 'dxgi-presentation-host
              (lambda () (dxgi-host-pointer host))
              (lambda (_) (dxgi-host-close! host)) #:keepalive context))))
      (set! space (make-srgb-color-space))
      (define adapter
        (presentation-adapter
          'direct3d context
          (lambda ()
            (define m (gui-measure))
            (define-values (w h) (dxgi-client-size hwnd))
            (presentation-metrics w h (hash-ref m 'logical_width) (hash-ref m 'logical_height)
                                  #:visible? (hash-ref m 'visible)))
          (lambda (metrics receive)
            (call-with-gpu-context context
              (lambda ()
                (define w (hash-ref metrics 'pixel_width))
                (define h (hash-ref metrics 'pixel_height))
                (define token (dxgi-host-acquire! host w h retire-skia!))
                (and token
                  (let ([descriptor #f] [handle #f] [canvas #f] [cleared? #f] [finished? #f]
                        [capture (current-dxgi-capture-hook)])
                    (define (retire-target!)
                      (parameterize-break #f
                      (when handle
                        (define old handle) (set! handle #f)
                        (domain-resource-close! old) (domain-drain! d))
                      (when descriptor
                        (define old descriptor) (set! descriptor #f)
                        (n:gr_backendrendertarget_delete old))))
                    (define (finish! present?)
                      (parameterize-break #f
                      ;; The pinned m119 draw-only render-target wrapper has no
                      ;; exported surface/readback/snapshot path. After its clear
                      ;; and balanced drawing, its last access is RENDER_TARGET.
                      ;; Retire *both* Skia wrappers before the external transition
                      ;; to PRESENT; recreate with PRESENT as its starting state
                      ;; on each acquisition, rather than reuse stale Skia state.
                      (retire-target!)
                      (define-values (outcome pixels record)
                        (dxgi-host-finish! host token cleared? present? (and present? capture #t)))
                      (set! finished? #t)
                      (values outcome pixels record)))
                    (call-with-presentation-cleanup
                      (lambda (mark-handed-off!)
                        (when (and capture (not (and (procedure? capture) (procedure-arity-includes? capture 2))))
                          (error 'direct3d-presentation "invalid private capture hook"))
                        (define resource-info
                          (make-gr-d3d-texture-info (dxgi-token-resource token) #f
                            d3d12-state-present dxgi-format-rgba8 1 1 0 #f))
                        (set! descriptor (n:gr_backendrendertarget_new_direct3d w h resource-info))
                        (unless (and descriptor (n:gr_backendrendertarget_is_valid descriptor)
                                     (= (n:gr_backendrendertarget_get_backend descriptor) gr-direct3d)
                                     (= (n:gr_backendrendertarget_get_samples descriptor) 1)
                                     (= (n:gr_backendrendertarget_get_width descriptor) w)
                                     (= (n:gr_backendrendertarget_get_height descriptor) h))
                          (error 'direct3d-presentation "Skia rejected the DXGI render-target descriptor"))
                        (define cs (call-with-owned 'direct3d-presentation (list (color-space-h 'direct3d-presentation space)) values))
                        (set! handle
                          (domain-new-resource d 'window-surface
                            (lambda () (n:sk_surface_new_backend_render_target
                                         (domain-pointer d) descriptor gr-top-left rgba-8888 cs #f))
                            n:sk_surface_unref #:keepalive context))
                        (define surface
                          (make-gpu-surface-record handle w h '() context d cs
                            (hasheq 'storage "gpu" 'target_kind "dxgi-back-buffer"
                                    'target_identity (format "dxgi-~a-~a" (domain-generation d) (dxgi-token-generation token))
                                    'buffer_index (dxgi-token-index token)
                                    'swap_chain_generation (dxgi-token-generation token)
                                    'color_type "RGBA8888" 'origin "top-left"
                                    'context_generation (domain-generation d)
                                    'actual_sample_count 1 'requested_sample_count 0
                                    'render_path "sk_surface_new_backend_render_target")))
                        (define info (gpu-surface-info surface))
                        (define c (surface-canvas surface))
                        (set! canvas c)
                        ;; A clear is mandatory, even for an empty callback, because
                        ;; flip-discard does not preserve previous buffer contents.
                        (parameterize-break #f (canvas-clear! c background) (set! cleared? #t))
                        (receive c info
                          (lambda ()
                            (unless (= (canvas-save-count c) 1)
                              (error 'direct3d-presentation "render callback left unbalanced canvas saves/layers"))
                            (gpu-flush-and-submit! context)
                            (define-values (outcome pixels record) (finish! #t))
                            (mark-handed-off!)
                            (record-gpu-io!
                              (hasheq 'kind "present-request" 'backend "direct3d" 'method "dxgi-same-queue"
                                      'wait_requested #f 'hresult (hash-ref record 'hresult)
                                      'result (symbol->string outcome)
                                      'buffer_index (hash-ref record 'buffer_index)
                                      'swap_chain_generation (hash-ref record 'swap_chain_generation)
                                      'fence_value (hash-ref record 'fence_value)))
                            (when capture
                              (record-gpu-io! (hasheq 'kind "validation-readback" 'backend "direct3d"
                                                       'method "CopyTextureRegion" 'wait_requested #t))
                              (capture pixels record))
                            (if (eq? outcome 'occluded) 'occluded (void)))))
                      (lambda ()
                        ;; A user exception, unbalanced saves, close, or resize
                        ;; during a yield must retire the drawn target but not
                        ;; Present it. Native failure stays quarantined, not retried.
                        (unless finished?
                          (when cleared?
                            ;; Balance cancelled save-layers before flushing; the
                            ;; external transition must refer to the root target.
                            (canvas-restore-to-count! canvas 1)
                            (record-gpu-io! (hasheq 'kind "cancelled-frame-sync" 'backend "direct3d" 'wait_requested #t))
                            (n:gr_direct_context_flush (domain-pointer d))
                            (unless (n:gr_direct_context_submit (domain-pointer d) #f)
                              (error 'direct3d-presentation "cancelled frame submission failed")))
                          (define-values (_result _pixels _record) (finish! #f))
                          (void)))
                      (lambda () (retire-target!))
                      (lambda (e)
                        (set! quarantined (cons (list handle descriptor token e) quarantined)))))))))
          post
          (lambda ()
            (unless (null? quarantined)
              (error 'gpu-presenter-close! "indeterminate DXGI frame references are quarantined"))
            (when pin
              (call-with-gpu-context context
                (lambda ()
                  (retire-skia!)
                  (domain-resource-close! pin) (domain-drain! d)
                  (unless (equal? (hash-ref (dxgi-host-info host) 'state) "closed")
                    (error 'gpu-presenter-close! "DXGI host did not retire"))
                  (set! pin #f))))
            ;; User-owned images can still prevent context closure. Retrying after
            ;; they are retired is safe; the already-closed swap chain is not reused.
            (gpu-context-close! context)
            (when space (skia-close! space) (set! space #f)))
          (lambda ()
            (hash-set* (dxgi-host-info host)
              'context (gpu-context-info context)
              'presentation_context_children (if pin 1 0)
              'quarantined_frames (length quarantined)))))
      (set! ok? #t) adapter)
    (lambda ()
      (unless ok?
        (when pin
          (call-with-gpu-context context (lambda () (domain-resource-close! pin) (domain-drain! d))))
        (when (and host (not pin)) (dxgi-host-close! host))
        (when space (skia-close! space))
        (gpu-context-close! context)))))
