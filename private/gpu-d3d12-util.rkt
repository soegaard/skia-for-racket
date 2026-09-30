#lang racket/base
(require "gpu-provider.rkt" "gpu-domain.rkt")
(provide (struct-out d3d12-platform-ops) (struct-out d3d12-context-ops)
         d3d12-selection! make-d3d12-components)

;; Private synchronous operations. Tests supply doubles without Windows/Skia.
;; Adapter, device and queue factories return owned +1 COM references.
(struct d3d12-platform-ops (adapter device queue release describe removed-reason))
(struct d3d12-context-ops (create release abandon abandoned? wait describe))
(define (d3d12-selection! adapter index)
  (unless (memq adapter '(hardware warp))
    (raise-argument-error 'make-gpu-context "'hardware or 'warp" adapter))
  (unless (and (exact-nonnegative-integer? index) (< index #xffffffff))
    (raise-argument-error 'make-gpu-context "adapter index in [0, 4294967294]" index))
  (when (and (eq? adapter 'warp) (not (zero? index)))
    (raise-arguments-error 'make-gpu-context "WARP has no selectable adapter index" "index" index))
  (void))

(define (make-d3d12-components platform native selection index)
  (d3d12-selection! selection index)
  (unless (d3d12-platform-ops? platform)
    (raise-argument-error 'make-d3d12-components "d3d12-platform-ops?" platform))
  (unless (d3d12-context-ops? native)
    (raise-argument-error 'make-d3d12-components "d3d12-context-ops?" native))
  (define creator (current-thread))
  (define key (gensym 'd3d12-queue))
  (define current-key (make-parameter #f))
  (define details (hasheq))
  (define adapter #f)
  (define device #f)
  (define queue #f)
  (define provider
    (make-gpu-provider
     #:name 'd3d12-owned #:backend 'direct3d #:key key
     ;; This is a private queue ownership scope, not an OS current-context API.
     #:current? (lambda () (and (eq? creator (current-thread)) (eq? key (current-key))))
     #:call-as-current (lambda (thunk) (parameterize ([current-key key]) (thunk)))
     #:describe (lambda () details)))
  (define (release-handles!)
    ;; Clear each slot before its one attempted Release. No finalizers call COM.
    ;; If Release throws, remaining references stay rooted with the driver;
    ;; indeterminate native destruction is not retried by the shared domain.
    (when queue
      (define q queue) (set! queue #f) ((d3d12-platform-ops-release platform) q))
    (when device
      (define d device) (set! device #f) ((d3d12-platform-ops-release platform) d))
    (when adapter
      (define a adapter) (set! adapter #f) ((d3d12-platform-ops-release platform) a)))
  (define (create)
    (define success? #f)
    (dynamic-wind
      void
      (lambda ()
        (set! adapter ((d3d12-platform-ops-adapter platform) selection index))
        (unless adapter (gpu-unavailable 'd3d12-adapter "selected DXGI adapter is unavailable"))
        (set! details (freeze-gpu-details ((d3d12-platform-ops-describe platform) adapter)))
        (unless (and (hash? details) (exact-nonnegative-integer? (hash-ref details 'adapter_flags #f)))
          (error 'direct3d "invalid DXGI adapter description"))
        (define software? (bitwise-bit-set? (hash-ref details 'adapter_flags) 1))
        (unless (eq? software? (eq? selection 'warp))
          (gpu-unavailable 'd3d12-adapter "selected adapter class does not match ~a; no automatic fallback" selection))
        (set! details (hash-set* details
                                'adapter_selection (symbol->string selection)
                                'adapter_index (if (eq? selection 'warp) #f index)
                                'renderer_class (if software? "software" "hardware-reported")
                                'd3d12_warp (eq? selection 'warp)
                                'hardware_acceleration_verified #f
                                'window_created #f 'requires_gui #f))
        (set! device ((d3d12-platform-ops-device platform) adapter))
        (unless device (gpu-unavailable 'd3d12-device "D3D12CreateDevice returned null"))
        (set! queue ((d3d12-platform-ops-queue platform) device))
        (unless queue (gpu-unavailable 'd3d12-queue "CreateCommandQueue returned null"))
        ;; The C shim borrows the by-value POD. Ganesh retains its own references.
        ;; Keep our independent +1 references until AFTER Ganesh destruction, so
        ;; device-loss checks and every partial failure have explicit ownership.
        (define p ((d3d12-context-ops-create native) adapter device queue))
        (unless p (gpu-unavailable 'd3d12-ganesh "Ganesh Direct3D construction returned null (possible disabled native backend)"))
        (set! success? #t)
        p)
      (lambda () (unless success? (release-handles!)))))
  (define (removed?)
    (negative? ((d3d12-platform-ops-removed-reason platform) device)))
  (define driver
    (gpu-driver
     create
     (lambda (p)
       (when (removed?) ((d3d12-context-ops-abandon native) p))
       ;; Normal teardown retires work; abandonment must never wait on a lost device.
       (unless ((d3d12-context-ops-abandoned? native) p)
         ((d3d12-context-ops-wait native) p))
       ((d3d12-context-ops-release native) p)
       (release-handles!))
     (lambda (p) ((d3d12-context-ops-abandon native) p))
     (lambda (p)
       (when (removed?)
         ((d3d12-context-ops-abandon native) p)
         (error 'call-with-gpu-context "D3D12 device removed; abandon/close this context"))
       (when ((d3d12-context-ops-abandoned? native) p)
         (error 'call-with-gpu-context "D3D12 context is abandoned")))
     (lambda (p) ((d3d12-context-ops-describe native) p details))))
  (values provider driver))
