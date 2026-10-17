#lang racket/base

;;;
;;; GPU Context Control
;;;

;; Validates and executes context reset, flush, and lifecycle operations.
;; Connects public context controls to the domain's owner-thread rules.

(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "gpu-context.rkt" "gpu-domain.rkt" "gpu-io-trace.rkt"
         "gpu-images.rkt" "core.rkt" "lifetime.rkt"
         (submod "core.rkt" gpu-surface-internals)
         (submod "core.rkt" gpu-image-internals))
(provide gpu-flush-surface! gpu-flush-image! gpu-context-release-and-abandon!)
; native-module : path?
;;   Locates the optional native dispatcher without loading it during module initialization.
(define-runtime-path native-module "gpu-context-control-native.rkt")
; current-context-control-dispatch : parameter?
;;   Provides an injectable context-control dispatcher without eagerly loading native operations.
(define current-context-control-dispatch (make-parameter #f))
(module* testing #f (provide current-context-control-dispatch))
; dispatch : -> any
;;   Selects an injected context-control implementation or loads the native dispatcher lazily.
(define (dispatch)
  (or (current-context-control-dispatch)
      (dynamic-require native-module 'context-control-dispatch/native)))
; targeted-flush : symbol? any/c any/c any/c -> void?
;;   Checks resource affinity before flushing a particular surface or image in its matching context.
(define (targeted-flush who context resource surface-target?)
  (unless ((if surface-target? gpu-surface? gpu-image?) resource)
    (raise-argument-error who (if surface-target? "gpu-surface?" "gpu-image?") resource))
  (define domain (context-domain who context))
  (define handle ((if surface-target? surface-h image-h) who resource))
  (unless (eq? domain (owned-gpu-domain handle))
    (error who "resources belong to different GPU contexts"))
  (define cp (domain-pointer domain))
  (define rp (resource-pointer handle))
  (when (and surface-target? (not (= 1 (canvas-save-count (surface-canvas resource)))))
    (error who "targeted surface flush requires a balanced canvas save/layer stack"))
  (define call (dispatch))
  (when (call 'abandoned? cp)
    (domain-request-shutdown! domain)
    (error who "native context is lost or abandoned; abandon/close the execution domain"))
  (record-gpu-io! (hasheq 'kind "flush" 'target (if surface-target? "surface" "image")
                        'context_generation (domain-generation domain)
                        'submission_requested #f 'completion_guaranteed #f))
  (call (if surface-target? 'flush-surface 'flush-image) cp rp)
  (void/reference-sink context resource)
  (void))
; gpu-flush-surface! : gpu-context? gpu-surface? -> void?
;;   Flushes work associated with a surface owned by context.
(define (gpu-flush-surface! context surface)
  (targeted-flush 'gpu-flush-surface! context surface #t))
; gpu-flush-image! : gpu-context? gpu-image? -> void?
;;   Like gpu-flush-surface!, for a live image in that same context.
(define (gpu-flush-image! context image)
  (targeted-flush 'gpu-flush-image! context image #f))
; gpu-context-release-and-abandon! : gpu-context? -> void?
;;   Releases native resources and abandons a ready context while its host is still usable.
(define (gpu-context-release-and-abandon! context)
  (define domain (context-domain 'gpu-context-release-and-abandon! context))
  (domain-release-and-abandon! domain
    (lambda (cp)
      (define call (dispatch))
      (record-gpu-io! (hasheq 'kind "context-release-and-abandon"
                            'context_generation (domain-generation domain)
                            'completion_guaranteed #f 'readback #f))
      (call 'release-and-abandon cp)
      (unless (call 'abandoned? cp)
        (error 'gpu-context-release-and-abandon! "native context did not report abandonment"))))
  (void/reference-sink context)
  (void))
