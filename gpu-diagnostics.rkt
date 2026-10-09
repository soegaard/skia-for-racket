#lang racket/base
;; 0.77c: context-local native diagnostics. Detached reports need no live context.
(require racket/runtime-path (only-in ffi/unsafe void/reference-sink)
         "private/gpu-context.rkt" "private/gpu-domain.rkt"
         "private/graphics-data.rkt" "private/gpu-diagnostic-util.rkt")
(provide gpu-memory-statistics gpu-gl-interface-info gpu-gl-has-extension?)
(define-runtime-path native-module "private/gpu-diagnostics-native.rkt")
(define current-gpu-diagnostics-dispatch (make-parameter #f))
(module* testing #f (provide current-gpu-diagnostics-dispatch))
(define (dispatch)
  (or (current-gpu-diagnostics-dispatch)
      (dynamic-require native-module 'gpu-diagnostics-dispatch/native)))
(define (ready-domain who context gl?)
  (define d (context-domain who context))
  (when (and gl? (not (eq? (domain-backend d) 'opengl)))
    (raise-arguments-error who "requires an OpenGL context" "backend" (domain-backend d)))
  ;; Reject wrong owner, inactive, shutdown-requested, closed or abandoned
  ;; domains before loading the native diagnostics module. Native dispatch
  ;; rechecks after any library loading or collector-lock wait.
  (domain-pointer d)
  d)
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
(define (gpu-gl-interface-info context)
  (define d (ready-domain 'gpu-gl-interface-info context #t))
  (begin0 ((dispatch) 'gl-info d) (void/reference-sink context)))
(define (gpu-gl-has-extension? context name)
  (define extension (checked-gl-extension 'gpu-gl-has-extension? name))
  (define d (ready-domain 'gpu-gl-has-extension? context #t))
  (begin0 ((dispatch) 'gl-extension d extension) (void/reference-sink context extension)))
