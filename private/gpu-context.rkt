#lang racket/base
(require ffi/unsafe/custodian "gpu-domain.rkt")
(provide gpu-context? wrap-gpu-domain context-domain gpu-context-close!)
;; The root domain registry never retains this wrapper. The unregister closure
;; returned by Racket explicitly takes the wrapper instead of capturing it.
(struct gpu-context (domain [unregister #:mutable]))
(define (context-domain who context)
  (unless (gpu-context? context) (raise-argument-error who "gpu-context?" context))
  (gpu-context-domain context))
(define (request-from-finalizer context)
  (domain-request-shutdown! (gpu-context-domain context) 'gc-or-custodian))
(define (wrap-gpu-domain domain)
  (define registered? #f)
  (dynamic-wind
    void
    (lambda ()
      (define context (gpu-context domain #f))
      (register-finalizer-and-custodian-shutdown
       context request-from-finalizer
       #:custodian-available
       (lambda (unregister)
         (set-gpu-context-unregister! context unregister)
         (set! registered? #t)
         context)
       #:custodian-unavailable
       (lambda (_) (error 'make-gpu-context "current custodian has already shut down"))))
    ;; This cleanup runs after the registration helper has left atomic mode.
    (lambda () (unless registered? (domain-close! domain)))))
(define (gpu-context-close! context)
  (domain-close! (context-domain 'gpu-context-close! context))
  (define unregister (gpu-context-unregister context))
  (when unregister (unregister context) (set-gpu-context-unregister! context #f))
  (void))
