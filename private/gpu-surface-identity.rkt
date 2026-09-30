#lang racket/base
(require "gpu-backends.rkt")
(provide gpu-surface-identity/validated)
;; Private stamping boundary, called only AFTER gpu-surface-info has checked
;; the live recording context's pointer against the owning domain. Backend,
;; generation and geometry come from that validation, never a constructor's
;; descriptive hash. This prevents the 0.49 missing-backend regression.
(define (gpu-surface-identity/validated description backend generation native width height)
  (unless (and (hash? description) (immutable? description))
    (raise-argument-error 'gpu-surface-info "immutable description hash" description))
  (check-gpu-backend! 'gpu-surface-info backend)
  (unless (and (exact-nonnegative-integer? native)
               (= native (gpu-backend-native-id backend)))
    (error 'gpu-surface-info "native backend disagrees with owning domain"))
  (unless (andmap exact-positive-integer? (list generation width height))
    (error 'gpu-surface-info "invalid generation or surface dimensions"))
  (hash-set* description
             'backend (string->immutable-string (symbol->string backend))
             'context_generation generation 'native_backend native
             'context_matches #t 'storage "gpu" 'width width 'height height))
