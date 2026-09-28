#lang racket/base
(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "private/gpu-context.rkt"
         "private/gpu-domain.rkt" "private/gpu-provider.rkt"
         "private/gpu-surfaces.rkt" "private/gpu-images.rkt")
(provide (all-from-out "private/gpu-images.rkt")
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
(define (make-gpu-context provider)
  (unless (gpu-provider? provider)
    (raise-argument-error 'make-gpu-context "gpu-provider?" provider))
  (unless (eq? (gpu-provider-backend provider) 'opengl)
    (gpu-unavailable 'backend "0.40 public rendering contexts support OpenGL; Metal has a construction probe only"))
  (define driver ((dynamic-require gl-driver-module 'make-gl-driver) provider))
  (wrap-gpu-domain (make-gpu-domain provider driver)))
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
