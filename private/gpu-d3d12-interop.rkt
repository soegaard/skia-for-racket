#lang racket/base
(require ffi/unsafe "../gpu.rkt" "core.rkt" "types.rkt" "lifetime.rkt"
         "gpu-types.rkt" "gpu-context.rkt" "gpu-domain.rkt" "gpu-dxgi-types.rkt"
         "gpu-d3d12-handles.rkt" "gpu-d3d12-interop-policy.rkt" "gpu-d3d12-interop-system.rkt"
         "gpu-io-trace.rkt" "gpu-interop-guard.rkt"
         (prefix-in i: "gpu-d3d12-interop-native.rkt")
         (prefix-in n: "gpu-native.rkt")
         (prefix-in im: "gpu-image-native.rkt")
         (only-in "check.rkt" check-dimensions)
         (submod "gpu-external.rkt" backend-internals)
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" gpu-image-internals))
(provide make-d3d12-external-texture call-with-gpu-d3d12-device)
(define quarantined-operations '())
(define (context! who context)
  (when (or (current-external-operation) (current-external-native?) (current-external-gl?) (current-gl-borrow?))
    (error who "nested native handoff/borrowing is not supported"))
  (define d (context-domain who context))
  (unless (eq? (domain-backend d) 'direct3d) (error who "an active Direct3D context is required"))
  (domain-pointer d)
  d)
(define (call-with-gpu-d3d12-device context proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-gpu-d3d12-device "one-argument procedure" proc))
  (define d (context! 'call-with-gpu-d3d12-device context))
  (call-with-d3d12-handles (domain-pointer d)
    (lambda (_adapter device _queue)
      ;; Device access, not queue handoff: external code creates its OWN queue
      ;; and resources. It cannot use private Ganesh resources or reenter Skia.
      (call-with-continuation-barrier
        (lambda () (parameterize ([current-external-native? #t]) (proc device)))))))
(define (space-pointer space)
  (and space (call-with-owned 'd3d12-interop (list (color-space-h 'd3d12-interop space)) values)))
(define (make-d3d12-external-texture context resource
          #:producer-fence producer #:producer-value value
          #:incoming-state incoming #:outgoing-state outgoing
          #:timeout-ms [timeout 5000] #:premultiplied? [premultiplied? #t]
          #:color-space [space #f])
  (interop-state incoming) (interop-state outgoing) (interop-timeout! timeout) (interop-fence-value! value)
  (unless (boolean? premultiplied?) (raise-argument-error 'make-d3d12-external-texture "boolean?" premultiplied?))
  (define d (context! 'make-d3d12-external-texture context))
  (space-pointer space)
  (i:interop-native-check!)
  (define session #f) (define pin #f) (define ready? #f)
  (define w #f) (define h #f)
  (dynamic-wind void
    (lambda ()
      (parameterize-break #f
        (call-with-d3d12-handles (domain-pointer d)
          (lambda (_a device queue)
            (set! session (make-interop-session device queue resource producer value incoming outgoing timeout))))
        ;; The resource/fence now have independent COM references. Domain
        ;; finalization only enqueues this destructor; it never calls COM off-owner.
        (set! pin (domain-new-resource d 'external-d3d12-texture
          (lambda () (session-resource session))
          (lambda (_) (session-close! session)) #:keepalive context)))
      (define description (session-description session))
      (set! w (hash-ref description 'width)) (set! h (hash-ref description 'height))
      (check-dimensions 'make-d3d12-external-texture w h)
      (define info (gpu-context-info context))
      (unless (and (<= w (hash-ref info 'max_texture_size)) (<= h (hash-ref info 'max_texture_size))
                   (<= w (hash-ref info 'max_render_target_size)) (<= h (hash-ref info 'max_render_target_size)))
        (error 'make-d3d12-external-texture "external texture exceeds the context limits"))
      (define result
        (make-external-texture 'direct3d context (domain-generation d)
          (hash-set* description 'format_name "RGBA8888" 'origin "top-left"
            'ownership "retained-single-handoff" 'completion "bounded-synchronous"
            'premultiplied premultiplied? 'state_query_available #f)
          (lambda (mode)
            (domain-pointer d) (resource-pointer pin) (space-pointer space)
            (check-dimensions 'd3d12-interop w h)
            (when (eq? mode 'surface)
              (unless premultiplied? (error 'd3d12-interop "render targets require premultiplied alpha"))
              (check-interop-resource! description #t)
              (n:gpu-native-check! 'dxgi)))
          (lambda (mode proc)
            (run-operation context d session pin w h space premultiplied? mode proc))
          (lambda () (domain-resource-close! pin))
          (lambda () (session-info session))))
      (set! ready? #t) result)
    (lambda ()
      (unless ready?
        (cond [pin (domain-resource-close! pin) (domain-drain! d)]
              [session (session-close! session)])))))
(define (run-operation context d session pin w h space premultiplied? mode proc)
  (define descriptor #f) (define handle #f) (define borrowed-surface #f)
  (define canvas #f) (define out #f) (define body-ok? #f)
  (define entered-target? #f) (define wrapped? #f)
  (define native-context (domain-pointer d))
  (define (retire-wrappers!)
    (when handle
      (define old handle) (set! handle #f) (domain-resource-close! old) (domain-drain! d))
    (when descriptor
      (define old descriptor) (set! descriptor #f)
      (if (eq? mode 'copy) (i:gr_backendtexture_delete old) (n:gr_backendrendertarget_delete old))))
  (define (complete!)
    ;; Ganesh submission is nonblocking; our own queue fence supplies the
    ;; bounded completion boundary, not an unbounded submit(syncCpu=true).
    (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine! e) (raise e))])
      (gpu-flush-and-submit! context)
      (session-complete! session))
    (record-gpu-io! (hasheq 'kind "external-d3d12-completion" 'wait_requested #t 'cpu_pixel_readback #f)))
  (define (quarantine! e)
    (session-quarantine! session e)
    (set! quarantined-operations
      (cons (list session pin handle descriptor borrowed-surface canvas out context e) quarantined-operations))
    (domain-request-shutdown! d 'external-d3d12-indeterminate))
  ;; A nested domain activation is the borrowed canvas lease, even when the
  ;; caller already has an outer active context.
  (call-with-gpu-context context
    (lambda ()
      (call-with-interop-cleanup
        (lambda ()
          (gpu-flush-and-submit! context)
          (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine! e) (raise e))])
            (parameterize-break #f
              (case mode
                [(copy) (session-copy-source! session)]
                [(surface) (session-begin-target! session) (set! entered-target? #t)])))
          (define cp (space-pointer space))
          (define texture-info
            (make-gr-d3d-texture-info
              (if (eq? mode 'copy) (session-bridge session) (session-resource session)) #f
              (if (eq? mode 'copy) #x80 d3d12-state-render-target) 28 1 1 0 #f))
          (parameterize-break #f
            (case mode
              [(copy)
               (set! descriptor (i:gr_backendtexture_new_direct3d w h texture-info))
               (unless (and descriptor (i:gr_backendtexture_is_valid descriptor)
                            (= (i:gr_backendtexture_get_backend descriptor) gr-direct3d))
                 (error 'gpu-import-image "invalid Direct3D bridge texture"))
               (set! handle (domain-new-resource d 'interop-bridge-image
                 (lambda () (i:sk_image_new_from_texture native-context descriptor gr-top-left rgba-8888
                                                        (if premultiplied? 2 3) cp #f #f))
                 im:image-unref/native #:keepalive context))]
              [(surface)
               (set! descriptor (n:gr_backendrendertarget_new_direct3d w h texture-info))
               (unless (and descriptor (n:gr_backendrendertarget_is_valid descriptor)
                            (= (n:gr_backendrendertarget_get_backend descriptor) gr-direct3d))
                 (error 'call-with-gpu-external-surface "invalid external Direct3D render target"))
               (set! handle (domain-new-resource d 'interop-external-surface
                 (lambda () (n:sk_surface_new_backend_render_target native-context descriptor gr-top-left rgba-8888 cp #f))
                 n:sk_surface_unref #:keepalive context))]))
          (set! wrapped? #t)
          (case mode
            [(copy)
             (define image (make-image-record handle w h))
             (unless (and (im:texture-backed?/native (resource-pointer handle))
                          (im:valid-image?/native (resource-pointer handle) native-context))
               (error 'gpu-import-image "bridge is not a valid GPU image"))
             (with-skia ([target (make-gpu-surface context w h #:color-space space)]
                         [paint (make-paint #:blend-mode 'src #:antialias? #f)])
               (draw-image (surface-canvas target) image 0 0 #:sampling 'nearest #:paint paint)
               (set! out (gpu-surface-snapshot target)))
             (complete!)
             (record-gpu-io! (hasheq 'kind "external-image-copy" 'backend "direct3d"
               'aliases_source #f 'cpu_readback #f 'native_bridge_copies 1 'skia_copy_draws 1))
             (set! body-ok? #t)
             out]
            [(surface)
             (set! borrowed-surface
               (make-gpu-surface-record handle w h '() context d cp
                 (hasheq 'target_kind "external-d3d12-render-target" 'origin "top-left"
                   'color_type "RGBA8888" 'alpha_type "premultiplied"
                   'requested_sample_count 0 'actual_sample_count 1
                   'render_path "sk_surface_new_backend_render_target")))
             (gpu-surface-info borrowed-surface)
             (set! canvas (surface-canvas borrowed-surface))
             (record-gpu-io! (hasheq 'kind "external-surface-borrow" 'backend "direct3d" 'contents_preserved #t))
             (call-with-canvas-state canvas
               (lambda ()
                 (define floor (canvas-save-count canvas))
                 (begin0 (proc canvas)
                   (unless (= (canvas-save-count canvas) floor)
                     (error 'call-with-gpu-external-surface "callback left unbalanced canvas saves/layers")))))]))
        (lambda ()
          (when (hash-ref (session-info session) 'quarantined)
            (error 'd3d12-interop "quarantined: ~a" (hash-ref (session-info session) 'error)))
          (when wrapped?
            (cond
              [(eq? mode 'surface)
               ;; Arbitrary callback operations can leave the root as COPY_SOURCE
               ;; (for example backdrop reads). m119 exports no state getter.
               ;; Snapshot the NON-TEXTURABLE render target (a separate GPU copy),
               ;; then issue exactly one full src draw back to the root. The
               ;; pinned D3D texture draw ends in a render pass / RENDER_TARGET.
               ;; This intentionally costs GPU work; it is NOT a zero-copy claim.
               (when canvas (canvas-restore-to-count! canvas 1))
               (with-skia ([snapshot (gpu-surface-snapshot borrowed-surface)]
                           [shader (make-image-shader snapshot #:sampling 'nearest)]
                           [paint (make-paint #:shader shader #:blend-mode 'src #:antialias? #f)])
                 ;; call-with-canvas-state restored the complete identity matrix
                 ;; and full clip, including when the callback raised or escaped.
                 ;; Use a shader-filled rectangle, not draw-image, to require a
                 ;; render pass rather than allow a texture-copy optimization.
                 (draw-rect (surface-canvas borrowed-surface) 0 0 w h paint))
               (record-gpu-io! (hasheq 'kind "external-target-normalization" 'backend "direct3d"
                  'gpu_snapshot_copies 1 'gpu_copy_draws 1 'cpu_readback #f))]
              [else (void)])
            (complete!))
          (retire-wrappers!)
          (when (and out (not body-ok?))
            (skia-close! out) (set! out #f) (domain-drain! d))
          (when entered-target? (session-return-target! session))
          (domain-resource-close! pin) (domain-drain! d)
          (when (hash-ref (session-info session) 'external_state_returned)
            (record-gpu-io! (hasheq 'kind "external-resource-return" 'backend "direct3d"
              'completion_verified #t 'outgoing_state (hash-ref (session-info session) 'outgoing_state)
              'cpu_readback #f)))
          (void/reference-sink space))
        quarantine!))))
