#lang racket/base
(require "gpu.rkt" "private/core.rkt" "private/output-executor.rkt"
         "private/audit-trace.rkt"
         (submod "private/core.rkt" gpu-surface-internals))
(provide make-gpu-raster-executor call-with-gpu-raster-executor)

(define (check-context! context)
  (unless (gpu-context? context)
    (raise-argument-error 'make-gpu-raster-executor "gpu-context?" context))
  ;; This is an owner-thread, detached metadata check, not native activation.
  (define info (gpu-context-info context))
  (unless (and (equal? (hash-ref info 'state) "ready")
               (not (hash-ref info 'shutdown_requested)))
    (error 'make-gpu-raster-executor "GPU context is not ready (or shutdown was requested)")))

(define (context-plan context picture)
  (check-context! context)
  (define affinity (skia-resource-gpu-context picture))
  (when (and affinity (not (eq? affinity context)))
    (error 'draw-output-group "captured picture belongs to another GPU context; detach explicitly"))
  (output-raster-plan
   (gpu-context-backend context) (gpu-context-generation context) #f
   (lambda (width height colorspace replay consume)
     (call-with-gpu-context context
       (lambda ()
         (with-skia ([surface (make-gpu-surface context width height
                               #:background 'transparent #:color-space colorspace
                               #:sample-count 0 #:opaque? #f)])
           (define target (gpu-surface-info surface))
           ;; Only this exact target's operations receive raster-representation
           ;; audit semantics. Lifetime checks still see the actual GPU backend.
           (call-with-audit-gpu-raster (surface-h 'draw-output-group surface)
             (lambda () (replay (surface-canvas surface))))
           ;; The document must retain a CPU-owned image, never the GPU snapshot.
           ;; Readback is explicit, synchronous, and preserves the target space.
           (with-skia ([image (gpu-surface->raster-image surface)])
             (consume image target))))))))

(define (make-gpu-raster-executor context)
  (check-context! context)
  (define generation (gpu-context-generation context))
  (make-output-raster-executor
   (lambda ()
     (check-context! context)
     (unless (= generation (gpu-context-generation context))
       (error 'make-gpu-raster-executor "stale GPU context generation")))
   (lambda (picture) (context-plan context picture))))

(define (call-with-gpu-raster-executor make-context proc #:on-unavailable [policy 'error])
  (call-with-lazy-output-raster-executor
   make-context check-context! context-plan
   (lambda (context) (when (gpu-context? context) (gpu-context-close! context)))
   proc #:on-unavailable policy))
