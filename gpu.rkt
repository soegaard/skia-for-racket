#lang racket/base

;;;
;;; GPU Contexts and Rendering
;;;

;; Creates and scopes GPU contexts and exposes rendering, state, and shutdown operations.
;; This public GPU entry point coordinates backend providers with the private domain, surface,
;; image, and release protocols.

;;;
;;; Imports and Exports
;;;

(require "private/gpu-backends.rkt")
(require racket/runtime-path racket/future (only-in ffi/unsafe void/reference-sink)
         (only-in (submod "private/gpu-domain.rkt" presentation-internals) domain-execution-active?)
         "private/gpu-context.rkt" "private/gpu-presenter.rkt"
         "private/gpu-domain.rkt" "private/gpu-provider.rkt"
         "private/gpu-surfaces.rkt" "private/gpu-images.rkt"
         "private/gpu-image-operations.rkt" "private/gpu-cache.rkt")
(provide gpu-backends gpu-backend? gpu-backend-capabilities
         (all-from-out "private/gpu-images.rkt" "private/gpu-image-operations.rkt"
                       "private/gpu-presenter.rkt" "private/gpu-cache.rkt")
         gpu-surface-format-info gpu-surface->image-info
         gpu-surface->raster-buffer gpu-surface-read-pixmap!
         make-gpu-surface gpu-surface? gpu-surface-info
         gpu-flush! gpu-submit! gpu-flush-and-submit! gpu-wait!
         gpu-surface->rgba-bytes gpu-surface->raster-image gpu-surface-read-raster-buffer!
         gpu-context? make-gpu-context call-with-gpu-context call-with-new-gpu-context
         gpu-context-backend gpu-context-generation gpu-context-state gpu-context-info
         gpu-context-close! gpu-context-abandon! gpu-context-request-shutdown!
         gpu-drain-releases! gpu-drain-pending-contexts! gpu-smoke-test
         make-gpu-provider gpu-provider? gpu-provider-name gpu-provider-backend
         exn:fail:gpu:unavailable? exn:fail:gpu:unavailable-step)

;;;
;;; Backend Loading and Context Construction
;;;

; gl-driver-module : path?
;   Locates private/gpu-driver-gl.rkt for lazy loading of the selected implementation.
(define-runtime-path gl-driver-module "private/gpu-driver-gl.rkt")

; smoke-module : path?
;   Locates private/gpu-smoke.rkt for lazy loading of the selected implementation.
(define-runtime-path smoke-module "private/gpu-smoke.rkt")

; metal-driver-module : path?
;   Locates private/gpu-driver-metal.rkt for lazy loading of the selected implementation.
(define-runtime-path metal-driver-module "private/gpu-driver-metal.rkt")

; d3d12-driver-module : path?
;   Locates private/gpu-driver-d3d12.rkt for lazy loading of the selected implementation.
(define-runtime-path d3d12-driver-module "private/gpu-driver-d3d12.rkt")

; make-gpu-context : [(or/c gpu-provider? #f)] [#:backend (or/c 'opengl 'metal 'direct3d #f)]
;   [#:adapter (or/c 'hardware 'warp #f)] [#:adapter-index (or/c (integer-in 0 4294967294) #f)]
;   [#:options (or/c gpu-context-options? #f)] [#:gl-interface (or/c 'default 'auto 'desktop 'gles
;   'webgl)] -> gpu-context?
;   Creates a ready context on the current Racket thread and registers shutdown notification with
;   the current custodian.
(define (make-gpu-context [provider #f] #:backend [requested #f]
                          #:adapter [adapter #f] #:adapter-index [index #f]
                          #:options [options #f]
                          #:gl-interface [interface-mode 'default])
  (define who 'make-gpu-context)
  (check-gl-interface-mode who interface-mode)
  (check-optional-context-options who options)
  (unless (or (not provider) (gpu-provider? provider))
    (raise-argument-error who "#f or gpu-provider?" provider))
  (when requested (check-gpu-backend! who requested))
  (define backend (or requested (and provider (gpu-provider-backend provider))))
  (unless backend
    (raise-arguments-error
     who "provide an OpenGL host or explicitly request an owned Metal/Direct3D context"))
  (when (and provider (not (eq? backend (gpu-provider-backend provider))))
    (raise-arguments-error who "requested backend disagrees with the supplied provider"
                           "backend" backend "provider backend" (gpu-provider-backend provider)))
  (check-gl-interface-backend who backend interface-mode)
  (when (and (or adapter index) (not (eq? backend 'direct3d)))
    (raise-arguments-error who "adapter selection is only supported for Direct3D"))
  (case backend
    [(direct3d)
     (when provider
       (gpu-unavailable 'd3d12-provider "external Direct3D providers are not supported in 0.48"))
     (define-values (host driver)
       ((dynamic-require d3d12-driver-module 'make-owned-d3d12-components)
        (or adapter 'hardware) (or index 0) #:options options))
     (wrap-gpu-domain (make-gpu-domain host driver))]
    [(opengl)
     (unless provider (raise-arguments-error who "OpenGL requires an explicit host provider"))
     (define driver
       ((dynamic-require gl-driver-module 'make-gl-driver)
        provider #:options options #:interface interface-mode))
     (wrap-gpu-domain (make-gpu-domain provider driver))]
    [(metal)
     (when provider
       (gpu-unavailable
        'metal-provider
        (string-append "external Metal providers are not supported; "
                       "omit the provider to create an owned device/queue")))
     (define-values (host driver)
       ((dynamic-require metal-driver-module 'make-owned-metal-components) #:options options))
     (wrap-gpu-domain (make-gpu-domain host driver))]))

;;;
;;; Context Scopes and State Queries
;;;

; call-with-new-gpu-context : (-> gpu-context?) (-> gpu-context? any) -> any
;   Creates and activates a context, then closes it outside the activation on every exit.
(define (call-with-new-gpu-context create proc)
  (define who 'call-with-new-gpu-context)
  (for ([callback (in-list (list create proc))] [arity (in-list '(0 1))])
    (unless (and (procedure? callback) (procedure-arity-includes? callback arity)
                 (let-values ([(required allowed) (procedure-keywords callback)])
                   (null? required)))
      (raise-argument-error who
        (format "procedure accepting ~a arguments and no required keywords" arity) callback)))
  (when (or (current-future) (domain-execution-active?))
    (error who "create a context outside GPU activations and futures"))
  (call-with-continuation-barrier
   (lambda ()
     (define context #f)
     (dynamic-wind void
       (lambda ()
         ;; Install cleanup ownership before a pending break can escape the constructor result.
         (parameterize-break #f (set! context (create)))
         (unless (gpu-context? context)
           (raise-arguments-error who "constructor did not return a GPU context" "result" context))
         (call-with-gpu-context context (lambda () (proc context))))
       (lambda () (when (gpu-context? context) (gpu-context-close! context)))))))

; call-with-gpu-context : gpu-context? (-> any) -> any
;   Activates the context's provider, calls thunk without arguments, and returns its multiple
;   values.
(define (call-with-gpu-context context thunk)
  (begin0 (domain-call (context-domain 'call-with-gpu-context context) thunk)
    (void/reference-sink context)))

; gpu-context-backend : gpu-context? -> (or/c 'opengl 'metal 'direct3d)
;   Returns the selected backend.
(define (gpu-context-backend context)
  (domain-backend (context-domain 'gpu-context-backend context)))

; gpu-context-generation : gpu-context? -> exact-positive-integer?
;   Returns the context's generation identifier.
(define (gpu-context-generation context)
  (domain-generation (context-domain 'gpu-context-generation context)))

; gpu-context-state : gpu-context? -> (or/c 'initializing 'ready 'releasing 'release-failed
;   'abandoned 'closing 'closed)
;   Returns the current wrapper state without requiring an active scope or owning thread.
(define (gpu-context-state context)
  (domain-state (context-domain 'gpu-context-state context)))

; gpu-context-info : gpu-context? -> (and/c hash? immutable?)
;   Returns detached context information on the owning Racket thread, outside a future.
(define (gpu-context-info context)
  (domain-info (context-domain 'gpu-context-info context)))

;;;
;;; Context Shutdown and Deferred Releases
;;;

; gpu-context-abandon! : gpu-context? -> void?
;   Marks a context abandoned on its owning thread, outside all GPU execution scopes.
(define (gpu-context-abandon! context)
  (domain-abandon! (context-domain 'gpu-context-abandon! context)))

; gpu-context-request-shutdown! : gpu-context? -> void?
;   Requests shutdown without activating a provider, waiting for the GPU, releasing native objects,
;   or running application callbacks.
(define (gpu-context-request-shutdown! context)
  (domain-request-shutdown! (context-domain 'gpu-context-request-shutdown! context)))

; gpu-drain-releases! : gpu-context? -> exact-nonnegative-integer?
;   Drains queued child-resource releases on the owning thread and returns the number of release
;   jobs processed by that call.
(define (gpu-drain-releases! context)
  (domain-drain! (context-domain 'gpu-drain-releases! context)))

; gpu-drain-pending-contexts! : [#:abandon? boolean?] -> (listof (and/c hash? immutable?))
;   Attempts shutdown for pending contexts owned by the calling Racket thread.
(define gpu-drain-pending-contexts! drain-pending-domains!)

;;;
;;; GPU Smoke Rendering
;;;

; gpu-smoke-test : gpu-context? -> (and/c hash? immutable?)
;   Runs a fixed synchronous 8 by 8 GPU rendering diagnostic.
(define (gpu-smoke-test context)
  ;; Retained 0.38 fixed diagnostic, independent of the general surface API.
  ((dynamic-require smoke-module 'run-gpu-smoke)
   (context-domain 'gpu-smoke-test context)))

;; 0.77b: pure configuration and checked GPU resource operations.
(require "gpu-context-options.rkt"
         (submod "gpu-context-options.rkt" internals)
         "private/gpu-context-control.rkt")
(provide (all-from-out "gpu-context-options.rkt" "private/gpu-context-control.rkt"))

;; 0.77c: no GPU/GL/native initialization on import.
(require "private/gpu-diagnostic-util.rkt" "gpu-diagnostics.rkt")
(provide (all-from-out "gpu-diagnostics.rkt"))

;; One-shot rendering. Imports remain native/GUI-lazy; construction is explicit.
(require (only-in "private/check.rkt" check-dimensions)
         (only-in "private/gpu-d3d12-util.rkt" d3d12-selection!)
         (only-in "private/core.rkt" surface-canvas surface-backend
                  canvas-execution-backend skia-close!)
         (only-in "color.rkt" color->rgba)
         "private/gpu-render.rkt")
(provide render-gpu->raster-image)

;;;
;;; Offscreen Rendering and Raster Readback
;;;

; render-gpu->raster-image : (integer-in 1 32768) (integer-in 1 32768) (-> canvas? any) #:backend
;   (or/c 'opengl 'metal 'direct3d) [#:background color?] [#:provider (or/c gpu-provider? #f)]
;   [#:adapter (or/c 'hardware 'warp #f)] [#:adapter-index (or/c (integer-in 0 4294967294) #f)] ->
;   image?
;   Creates a context and an RGBA8888 premultiplied offscreen surface, calls draw once with its
;   borrowed native Skia canvas, and returns an owned CPU image after readback.
(define (render-gpu->raster-image width height draw
                                 #:backend backend
                                 #:background [background 'transparent]
                                 #:provider [provider #f]
                                 #:adapter [adapter #f]
                                 #:adapter-index [index #f])
  (define who 'render-gpu->raster-image)
  (define color (color->rgba background))
  ;; Reject malformed requests before creating a context or loading a driver.
  (check-dimensions who width height)
  (unless (and (procedure? draw)
               (procedure-arity-includes? draw 1)
               (let-values ([(required allowed) (procedure-keywords draw)])
                 (null? required)))
    (raise-argument-error who "function accepting one argument and no required keywords" draw))
  (check-gpu-backend! who backend)
  (unless (or (not provider) (gpu-provider? provider))
    (raise-argument-error who "#f or gpu-provider?" provider))
  (cond
    [(eq? backend 'opengl)
     (unless (and provider (eq? (gpu-provider-backend provider) 'opengl))
       (raise-arguments-error who "OpenGL requires an explicit OpenGL host provider"
                              "provider" provider))]
    [provider
     (raise-arguments-error who "a provider is only accepted for OpenGL"
                            "backend" backend)])
  (cond
    [(eq? backend 'direct3d) (d3d12-selection! (or adapter 'hardware) (or index 0))]
    [(or adapter index)
     (raise-arguments-error who "adapter selection is only supported for Direct3D"
                            "backend" backend)])
  (call-with-rendered-gpu-image
   (lambda ()
     (make-gpu-context provider #:backend backend #:adapter adapter #:adapter-index index))
   call-with-gpu-context
   (lambda (context)
     (unless (eq? (gpu-context-backend context) backend)
       (error who "context did not use the requested backend"))
     (make-gpu-surface context width height #:background color))
   (lambda (context surface)
     (define canvas (surface-canvas surface))
     (unless (and (eq? (surface-backend surface) backend)
                  (eq? (canvas-execution-backend canvas) backend))
       (error who "drawing target did not use the requested backend"))
     (draw canvas))
   gpu-surface->raster-image
   skia-close!
   gpu-context-close!))
