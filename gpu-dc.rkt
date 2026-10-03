#lang racket/base
;; Explicit, headless-safe entry point. Native GPU code is loaded on first use,
;; never by importing this module or querying its declaration/predicate.
(require racket/runtime-path
         "private/gpu-dc-scope.rkt"
         (only-in "private/gpu-presenter.rkt" gpu-frame? gpu-frame-canvas))
(provide call-with-gpu-frame-dc call-with-gpu-surface-dc
         skia-gpu-dc? skia-gpu-dc-capabilities)
(define-runtime-path native-module "private/gpu-dc-native.rkt")
(define (check-callback who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "procedure accepting one DC argument" proc))
  (when (gpu-dc-scope-active?) (error who "nested GPU DC scopes are not supported")))
(define (call-with-gpu-frame-dc frame proc
                               #:background [background "white"]
                               #:smoothing [smoothing 'smoothed])
  (check-callback 'call-with-gpu-frame-dc proc)
  (unless (gpu-frame? frame) (raise-argument-error 'call-with-gpu-frame-dc "gpu-frame?" frame))
  (gpu-frame-canvas frame) ; owner/expiry rejection before loading native code
  ((dynamic-require native-module 'call-with-gpu-frame-dc/native)
   frame proc background smoothing))
(define (call-with-gpu-surface-dc surface proc
                                 #:logical-width [logical-width #f]
                                 #:logical-height [logical-height #f]
                                 #:background [background "white"]
                                 #:smoothing [smoothing 'smoothed]
                                 #:clear? [clear? #f])
  (check-callback 'call-with-gpu-surface-dc proc)
  ((dynamic-require native-module 'call-with-gpu-surface-dc/native)
   surface proc logical-width logical-height background smoothing clear?))
