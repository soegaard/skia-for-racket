#lang racket/base
;; Synchronous native diagnostics only: no flush, submission, wait or pixel I/O.
(require "gpu-native.rkt" "gpu-domain.rkt" "gpu-gl-interface.rkt"
         "graphics-trace-native.rkt")
(provide gpu-diagnostics-dispatch/native)
(define (checked-pointer who domain)
  (define pointer (domain-pointer domain))
  (when (gr_direct_context_is_abandoned pointer)
    (domain-request-shutdown! domain 'native-abandoned)
    (error who "native GPU context is abandoned; retire the execution domain"))
  pointer)
(define (gpu-diagnostics-dispatch/native operation domain . arguments)
  (case operation
    [(memory)
     (apply collect-memory-statistics/native
       'gpu-memory-statistics 'gpu-context-skia-resources
       (lambda (dump)
         ;; Runs only after the shared collector has entered its atomic
         ;; synchronous capture scope. It never calls application code.
         (gr_direct_context_dump_memory_statistics
          (checked-pointer 'gpu-memory-statistics domain) dump))
       arguments)]
    [(gl-info)
     (call-global-cache-native 'gpu-gl-interface-info
       (lambda ()
         (gl-context-interface-info/native
          (checked-pointer 'gpu-gl-interface-info domain))))]
    [(gl-extension)
     (call-global-cache-native 'gpu-gl-has-extension?
       (lambda ()
         (gl-context-has-extension?/native
          (checked-pointer 'gpu-gl-has-extension? domain) (car arguments))))]
    [else (error 'gpu-diagnostics "unknown private operation")]))
