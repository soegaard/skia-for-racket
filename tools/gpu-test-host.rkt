#lang racket/base
(require racket/runtime-path "../gpu.rkt")
(provide call-with-gpu-backend-host)
(define-runtime-path gl-host-module "gpu-gui-host.rkt")
;; Supply a context maker, not a raw backend handle. Metal needs no host;
;; creating each context owns a new command queue. GL borrows its GUI host.
(define (call-with-gpu-backend-host backend proc)
  (case backend
    [(opengl)
     ((dynamic-require gl-host-module 'call-with-gpu-test-host)
      (lambda (provider info) (proc (lambda () (make-gpu-context provider)) info)))]
    [(metal)
     (proc (lambda () (make-gpu-context #:backend 'metal))
           (hasheq 'provider "owned Metal device/queue" 'headless #t
                   'presentation_tested #f 'requires_gl_context #f 'window_created #f))]
    [else (raise-argument-error 'call-with-gpu-backend-host "'opengl or 'metal" backend)]))
