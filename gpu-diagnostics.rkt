#lang racket/base

;;;
;;; GPU Diagnostic Queries
;;;

;; Queries native memory statistics and OpenGL interface capabilities.
;; This public diagnostic layer obtains a ready owning domain before forwarding queries to the
;; private backend implementation.

;;;
;;; Imports and Exports
;;;

;; 0.77c: context-local native diagnostics. Detached reports need no live context.
(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "private/gpu-context.rkt" "private/gpu-domain.rkt"
         "private/graphics-data.rkt" "private/gpu-diagnostic-util.rkt")
(provide gpu-memory-statistics gpu-gl-interface-info gpu-gl-has-extension?)

; native-module : path?
;   Locates private/gpu-diagnostics-native.rkt for lazy loading of the selected implementation.
(define-runtime-path native-module "private/gpu-diagnostics-native.rkt")

; current-gpu-diagnostics-dispatch : (parameter/c (or/c #f procedure?))
;   Allows tests to replace native diagnostics dispatch without loading GPU libraries.
(define current-gpu-diagnostics-dispatch (make-parameter #f))
(module* testing #f (provide current-gpu-diagnostics-dispatch))

; dispatch : -> procedure?
;   Selects the test override or lazily loads native GPU diagnostics.
(define (dispatch)
  (or (current-gpu-diagnostics-dispatch)
      (dynamic-require native-module 'gpu-diagnostics-dispatch/native)))

; ready-domain : symbol? any/c boolean? -> gpu-domain?
;   Checks backend, ownership, and context liveness before loading native diagnostics.
(define (ready-domain who context gl?)
  (define d (context-domain who context))
  (when (and gl? (not (eq? (domain-backend d) 'opengl)))
    (raise-arguments-error who "requires an OpenGL context" "backend" (domain-backend d)))
  ;; Reject wrong owner, inactive, shutdown-requested, closed or abandoned
  ;; domains before loading the native diagnostics module. Native dispatch
  ;; rechecks after any library loading or collector-lock wait.
  (domain-pointer d)
  d)

; gpu-memory-statistics : gpu-context? [#:detailed? boolean?] [#:dump-wrapped? boolean?]
;   [#:max-entries (integer-in 0 65536)] [#:string-limit (integer-in 0 65536)] [#:byte-limit
;   exact-nonnegative-integer?] -> memory-statistics?
;   Returns a detached memory report for the active context.
(define (gpu-memory-statistics context
                               #:detailed? [detailed? #f] #:dump-wrapped? [wrapped? #f]
                               #:max-entries [max-entries 4096]
                               #:string-limit [string-limit 4096]
                               #:byte-limit [byte-limit 1048576])
  (define who 'gpu-memory-statistics)
  (memory-options who detailed? wrapped? max-entries string-limit byte-limit)
  (define d (ready-domain who context #f))
  (begin0
    ((dispatch) 'memory d detailed? wrapped? max-entries string-limit byte-limit)
    (void/reference-sink context)))

; gpu-gl-interface-info : gpu-context? -> (and/c hash? immutable?)
;   Returns a detached description of the exact Skia GL interface retained by an active OpenGL
;   context.
(define (gpu-gl-interface-info context)
  (define d (ready-domain 'gpu-gl-interface-info context #t))
  (begin0 ((dispatch) 'gl-info d) (void/reference-sink context)))

; gpu-gl-has-extension? : gpu-context? string? -> boolean?
;   Reports whether the retained Skia GL interface for the active OpenGL context advertises name.
(define (gpu-gl-has-extension? context name)
  (define extension (checked-gl-extension 'gpu-gl-has-extension? name))
  (define d (ready-domain 'gpu-gl-has-extension? context #t))
  (begin0 ((dispatch) 'gl-extension d extension) (void/reference-sink context extension)))
