#lang racket/base
(require "gpu-driver-metal.rkt" "gpu-domain.rkt")
(provide run-metal-construction-probe)
;; The legacy 0.38 diagnostic deliberately remains construction-only. Actual
;; Metal rendering is independently exercised by the 0.41 lifecycle/scene tests.
(define (run-metal-construction-probe)
  (define-values (provider driver) (make-owned-metal-components))
  (define domain (make-gpu-domain provider driver))
  (dynamic-wind void (lambda () (domain-info domain)) (lambda () (domain-close! domain)))
  (hash-set* (domain-info domain) 'construction_only #t 'rendering_verified #f))
