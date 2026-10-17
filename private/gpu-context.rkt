#lang racket/base

;;;
;;; GPU Context Resources
;;;

;; Wraps GPU domains and arranges owner-thread context cleanup.
;; Provides the resource identity used by public GPU constructors and operations.

(require ffi/unsafe/custodian "gpu-domain.rkt")
(provide gpu-context? wrap-gpu-domain context-domain gpu-context-close!)
;; The root domain registry never retains this wrapper. The unregister closure
;; returned by Racket explicitly takes the wrapper instead of capturing it.
(struct gpu-context (domain [unregister #:mutable]))
;; Fields:
;;   domain: owning GPU execution domain. unregister: mutable custodian/finalizer unregistration
;;   procedure or #f. Cleanup requests shutdown; native teardown still follows domain owner-thread
;;   rules.

; context-domain : symbol? gpu-context? -> gpu-domain?
;;   Checks a public GPU context wrapper before exposing its private execution domain.
(define (context-domain who context)
  (unless (gpu-context? context) (raise-argument-error who "gpu-context?" context))
  (gpu-context-domain context))
; request-from-finalizer : gpu-context? -> any
;;   Requests domain shutdown from finalization without executing native teardown on the finalizer
;;   thread.
(define (request-from-finalizer context)
  (domain-request-shutdown! (gpu-context-domain context) 'gc-or-custodian))
; wrap-gpu-domain : any/c -> any
;;   Wraps an existing domain and installs finalizer/custodian notification without changing native
;;   ownership.
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
; gpu-context-close! : gpu-context? -> void?
;;   Closes a context on its owning thread, outside every GPU execution scope.
(define (gpu-context-close! context)
  (domain-close! (context-domain 'gpu-context-close! context))
  (define unregister (gpu-context-unregister context))
  (when unregister (unregister context) (set-gpu-context-unregister! context #f))
  (void))
