#lang racket/base
(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "private/gpu-context.rkt" "private/gpu-presenter.rkt"
         "private/gpu-domain.rkt" "private/gpu-provider.rkt"
         "private/gpu-surfaces.rkt" "private/gpu-images.rkt" "private/gpu-cache.rkt")
(provide (all-from-out "private/gpu-images.rkt" "private/gpu-presenter.rkt" "private/gpu-cache.rkt")
         make-gpu-surface gpu-surface? gpu-surface-info
         gpu-flush! gpu-submit! gpu-flush-and-submit! gpu-wait!
         gpu-surface->rgba-bytes gpu-surface->raster-image gpu-surface-read-raster-buffer!
         gpu-context? make-gpu-context call-with-gpu-context
         gpu-context-backend gpu-context-generation gpu-context-state gpu-context-info
         gpu-context-close! gpu-context-abandon! gpu-context-request-shutdown!
         gpu-drain-releases! gpu-drain-pending-contexts! gpu-smoke-test
         make-gpu-provider gpu-provider? gpu-provider-name gpu-provider-backend
         exn:fail:gpu:unavailable? exn:fail:gpu:unavailable-step)
(define-runtime-path gl-driver-module "private/gpu-driver-gl.rkt")
(define-runtime-path smoke-module "private/gpu-smoke.rkt")
(define-runtime-path metal-driver-module "private/gpu-driver-metal.rkt")
(define-runtime-path d3d12-driver-module "private/gpu-driver-d3d12.rkt")
(define (make-gpu-context [provider #f] #:backend [requested #f]
                          #:adapter [adapter #f] #:adapter-index [index #f])
  (define who 'make-gpu-context)
  (unless (or (not provider) (gpu-provider? provider))
    (raise-argument-error who "#f or gpu-provider?" provider))
  (unless (memq requested '(#f opengl metal direct3d))
    (raise-argument-error who "#f, 'opengl, 'metal, or 'direct3d" requested))
  (define backend (or requested (and provider (gpu-provider-backend provider))))
  (unless backend
    (raise-arguments-error who "provide an OpenGL host or explicitly request an owned Metal/Direct3D context"))
  (when (and provider (not (eq? backend (gpu-provider-backend provider))))
    (raise-arguments-error who "requested backend disagrees with the supplied provider"
                           "backend" backend "provider backend" (gpu-provider-backend provider)))
  (when (and (or adapter index) (not (eq? backend 'direct3d)))
    (raise-arguments-error who "adapter selection is only supported for Direct3D"))
  (case backend
    [(direct3d)
     (when provider
       (gpu-unavailable 'd3d12-provider "external Direct3D providers are not supported in 0.48"))
     (define-values (host driver)
       ((dynamic-require d3d12-driver-module 'make-owned-d3d12-components)
        (or adapter 'hardware) (or index 0)))
     (wrap-gpu-domain (make-gpu-domain host driver))]
    [(opengl)
     (unless provider (raise-arguments-error who "OpenGL requires an explicit host provider"))
     (define driver ((dynamic-require gl-driver-module 'make-gl-driver) provider))
     (wrap-gpu-domain (make-gpu-domain provider driver))]
    [(metal)
     (when provider
       (gpu-unavailable 'metal-provider "external Metal providers are not supported; omit the provider to create an owned device/queue"))
     (define-values (host driver)
       ((dynamic-require metal-driver-module 'make-owned-metal-components)))
     (wrap-gpu-domain (make-gpu-domain host driver))]))
(define (call-with-gpu-context context thunk)
  (begin0 (domain-call (context-domain 'call-with-gpu-context context) thunk)
    (void/reference-sink context)))
(define (gpu-context-backend context)
  (domain-backend (context-domain 'gpu-context-backend context)))
(define (gpu-context-generation context)
  (domain-generation (context-domain 'gpu-context-generation context)))
(define (gpu-context-state context)
  (domain-state (context-domain 'gpu-context-state context)))
(define (gpu-context-info context)
  (domain-info (context-domain 'gpu-context-info context)))
(define (gpu-context-abandon! context)
  (domain-abandon! (context-domain 'gpu-context-abandon! context)))
(define (gpu-context-request-shutdown! context)
  (domain-request-shutdown! (context-domain 'gpu-context-request-shutdown! context)))
(define (gpu-drain-releases! context)
  (domain-drain! (context-domain 'gpu-drain-releases! context)))
(define gpu-drain-pending-contexts! drain-pending-domains!)
(define (gpu-smoke-test context)
  ;; Retained 0.38 fixed diagnostic, independent of the general surface API.
  ((dynamic-require smoke-module 'run-gpu-smoke)
   (context-domain 'gpu-smoke-test context)))
