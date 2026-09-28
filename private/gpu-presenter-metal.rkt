#lang racket/base
(require ffi/unsafe "../gpu.rkt" "core.rkt" "types.rkt" "gpu-types.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-metal-layer.rkt" "lifetime.rkt"
         (only-in "check.rkt" color-type-values)
         "gpu-presentation-native.rkt" "gpu-io-trace.rkt" "gpu-presentation-cleanup.rkt"
         (prefix-in n: "gpu-native.rkt")
         (submod "core.rkt" gpu-surface-internals)
         (submod "gpu-presenter.rkt" adapter-internals))
(provide make-metal-presentation-adapter)
(define (make-metal-presentation-adapter view post background)
  (presentation-native-check!)
  (define context (make-gpu-context #:backend 'metal))
  (define d (context-domain 'gpu-presenter context))
  (define layer #f)
  (define space #f)
  (define ok? #f)
  ;; Indeterminate abort/destruction must retain every remaining reference.
  ;; The presenter's finalizer roots failed owner cleanup; never retry it.
  (define quarantined '())
  (dynamic-wind
    void
    (lambda ()
      (set! layer (call-with-gpu-context context
                    (lambda () (make-metal-layer-host (domain-pointer d) view))))
      (set! space (make-srgb-color-space))
      (define adapter
        (presentation-adapter
         'metal context (lambda () (metal-layer-measure layer))
         (lambda (metrics receive)
           (call-with-gpu-context context
             (lambda ()
               (define token (metal-layer-acquire! layer metrics))
               (and token
                    (let ([descriptor #f] [handle #f] [native-context (domain-pointer d)])
                      (call-with-presentation-cleanup
                        (lambda (mark-presented!)
                          (define w (hash-ref metrics 'pixel_width))
                          (define h (hash-ref metrics 'pixel_height))
                          (define texture (make-gr-mtl-texture-info (metal-drawable-texture token)))
                          (set! descriptor (metal-backend-target/new w h texture))
                          (unless (and descriptor (presentation-target/valid? descriptor)
                                       (= (presentation-target/backend descriptor) gr-metal))
                            (error 'gpu-presenter "Metal drawable render-target descriptor rejected"))
                          (set! handle
                            (domain-new-resource d 'window-surface
                              (lambda ()
                                ;; Texture samples are encoded sRGB in BGRA8Unorm;
                                ;; the CAMetalLayer explicitly carries an sRGB tag.
                                (presentation-target/wrap (domain-pointer d) descriptor gr-top-left
                                                          (hash-ref color-type-values 'bgra-8888)
                                  (call-with-owned 'gpu-presenter (list (color-space-h 'gpu-presenter space)) values) #f))
                              n:sk_surface_unref #:keepalive context))
                          (define surface
                            (make-gpu-surface-record handle w h '() context d
                              (call-with-owned 'gpu-presenter (list (color-space-h 'gpu-presenter space)) values)
                              (hash-set* (metal-drawable-info token)
                                'storage "gpu" 'target_kind "metal-drawable"
                                'color_type "BGRA8888" 'context_generation (domain-generation d)
                                'actual_sample_count (presentation-target/samples descriptor)
                                'render_path "sk_surface_new_backend_render_target")))
                          (define info (gpu-surface-info surface))
                          (define c (surface-canvas surface))
                          (canvas-clear! c background)
                          (receive c info
                            (lambda ()
                              (unless (= (canvas-save-count c) 1)
                                (error 'gpu-presenter "render callback left unbalanced canvas saves/layers"))
                              (gpu-flush-and-submit! context)
                              (metal-layer-present! layer token)
                              (mark-presented!)
                              (record-gpu-io! (hasheq 'kind "present-request" 'backend "metal"
                                                      'method "same-queue-command-buffer"
                                                      'wait_requested #f)))))
                        (lambda ()
                          ;; Aborted frames are not presented. Finish any Skia
                          ;; work before returning this texture to the drawable
                          ;; pool. This exceptional-path wait is NOT a normal
                          ;; per-frame synchronization or user callback scope.
                          (record-gpu-io! (hasheq 'kind "cancelled-frame-sync" 'backend "metal"
                                                  'wait_requested #t))
                          (n:gr_direct_context_flush native-context)
                          (unless (n:gr_direct_context_submit native-context #t)
                            (error 'gpu-presenter "cancelled Metal frame could not complete; target quarantined")))
                        (lambda ()
                          ;; Skia reference, backend descriptor, then drawable.
                          ;; Detach each variable before its one release attempt.
                          (when handle
                            (define h handle) (set! handle #f)
                            (domain-resource-close! h) (domain-drain! d))
                          (when descriptor
                            (define b descriptor) (set! descriptor #f)
                            (presentation-target/delete b))
                          (metal-layer-release! layer token))
                        (lambda (e)
                          (set! quarantined (cons (list handle descriptor token e) quarantined)))))))))
         post
         (lambda ()
           ;; Context close refuses live application resources and can be retried
           ;; after the user closes them. Leave the layer intact on that failure.
           (unless (and (null? quarantined)
                        (zero? (hash-ref (metal-layer-info layer) 'live_drawables)))
             (error 'gpu-presenter-close! "indeterminate Metal frame references are quarantined"))
           (metal-layer-finish! layer)
           (gpu-context-close! context)
           (skia-close! space)
           (metal-layer-close! layer))
         (lambda () (hash-set* (metal-layer-info layer)
                       'context (gpu-context-info context)
                       'quarantined_frames (length quarantined)))))
      (set! ok? #t) adapter)
    (lambda ()
      (unless ok?
        (dynamic-wind void (lambda () (gpu-context-close! context))
          (lambda () (when space (skia-close! space))
                     (when layer (metal-layer-close! layer))))))))
