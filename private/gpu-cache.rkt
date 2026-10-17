#lang racket/base

;;;
;;; GPU Cache Control
;;;

;; Runs cache queries and cleanup inside the owning GPU domain.
;; Exposes cache management while preserving context ownership and activation rules.

(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "gpu-context.rkt" "gpu-domain.rkt" "gpu-cache-util.rkt" "gpu-io-trace.rkt")
(provide gpu-cache-info gpu-set-cache-limit! gpu-purge-unlocked! gpu-purge-bytes!
         gpu-perform-deferred-cleanup! gpu-free-resources!)

; native-module : path?
;   Locates the optional native dispatcher without loading it during module initialization.
(define-runtime-path native-module "gpu-cache-native.rkt")

; current-cache-dispatch : parameter?
;   Provides an injectable cache-operation dispatcher for native-free lifecycle tests.
(define current-cache-dispatch (make-parameter #f))
(module* testing #f (provide current-cache-dispatch))

; with-cache : symbol? any/c procedure? -> any
;   Dispatches a cache operation while the context's owning GPU domain is active.
(define (with-cache who context proc)
  (define d (context-domain who context))
  (define p (domain-pointer d)) ; all owner/scope/external-GL checks precede loading
  (define dispatch (or (current-cache-dispatch) (dynamic-require native-module
    'cache-dispatch/native)))
  (when (dispatch 'abandoned? p)
    (domain-request-shutdown! d 'native-context-lost)
    (error who "native context is lost or abandoned; abandon/close this execution domain"))
  (begin0 (proc d p dispatch) (void/reference-sink context)))

; gpu-cache-info : gpu-context? -> (and/c hash? immutable?)
;   Returns a detached hash containing the backend, context generation, 'limit_bytes,
;   'budgeted_resources, and 'budgeted_bytes.
(define (gpu-cache-info context)
  (with-cache 'gpu-cache-info context
    (lambda (d p dispatch)
      (define-values (limit count bytes) (dispatch 'info p))
      (cache-snapshot (domain-backend d) (domain-generation d) limit count bytes))))

; mutate : symbol? any/c any/c any/c any/c -> any
;   Runs a selected cache mutation and returns detached operation details under the same context
;   generation.
(define (mutate who context op args details)
  (with-cache who context
    (lambda (d p dispatch)
      ;; Requests are not proof of bytes freed or CPU completion. In particular
      ;; m119 freeGpuResources internally flushes/submits (without a CPU fence).
      (record-gpu-io! (hash-set* details 'kind "cache" 'operation (symbol->string op)
                      'context_generation (domain-generation d)
                      'native_may_submit (eq? op 'free-resources) 'completion_guaranteed #f))
      (apply dispatch op p args)
      (void))))

; gpu-set-cache-limit! : gpu-context? exact-nonnegative-integer? -> void?
;   Sets the context's budgeted cache byte limit.
(define (gpu-set-cache-limit! context bytes)
  (cache-size 'gpu-set-cache-limit! bytes)
  (mutate 'gpu-set-cache-limit! context 'set-limit (list bytes) (hasheq 'limit_bytes bytes)))

; gpu-purge-unlocked! : gpu-context? [#:scratch-only? boolean?] -> void?
;   Requests purging of unlocked cache resources, optionally restricted to scratch resources.
(define (gpu-purge-unlocked! context #:scratch-only? [scratch-only? #f])
  (cache-boolean 'gpu-purge-unlocked! scratch-only?)
  (mutate 'gpu-purge-unlocked! context 'purge (list scratch-only?) (hasheq 'scratch_only
    scratch-only?)))

; gpu-purge-bytes! : gpu-context? exact-nonnegative-integer? [#:prefer-scratch? boolean?] -> void?
;   Requests purging the given number of bytes, preferring scratch resources when requested.
(define (gpu-purge-bytes! context bytes #:prefer-scratch? [prefer-scratch? #t])
  (cache-size 'gpu-purge-bytes! bytes) (cache-boolean 'gpu-purge-bytes! prefer-scratch?)
  (mutate 'gpu-purge-bytes! context 'purge-bytes (list bytes prefer-scratch?)
          (hasheq 'bytes_requested bytes 'prefer_scratch prefer-scratch?)))

; gpu-perform-deferred-cleanup! : gpu-context? (integer-in 0 2147483647) -> void?
;   Requests native cleanup based on how long resources have been unused.
(define (gpu-perform-deferred-cleanup! context milliseconds)
  (cache-age 'gpu-perform-deferred-cleanup! milliseconds)
  (mutate 'gpu-perform-deferred-cleanup! context 'deferred (list milliseconds)
          (hasheq 'unused_milliseconds milliseconds)))

; gpu-free-resources! : gpu-context? -> void?
;   Requests release of context resources without abandoning the context.
(define (gpu-free-resources! context)
  (mutate 'gpu-free-resources! context 'free-resources '() (hasheq)))
