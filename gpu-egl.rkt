#lang racket/base
;; Explicit Linux EGL entry points. Importing this module initializes neither
;; EGL nor a GUI. Native platform loading happens only in these constructors.
(require racket/runtime-path "private/gpu-context.rkt" "private/gpu-domain.rkt"
         "private/gpu-egl-util.rkt")
(provide make-egl-gpu-context make-current-egl-gpu-provider)
(define-runtime-path driver-module "private/gpu-driver-egl.rkt")
(define (make-egl-gpu-context #:platform [platform 'surfaceless]
                              #:device-index [index 0]
                              #:surface [surface 'surfaceless])
  (check-egl-options 'make-egl-gpu-context platform index surface)
  (define-values (provider driver)
    ((dynamic-require driver-module 'make-owned-egl-components) platform index surface))
  (wrap-gpu-domain (make-gpu-domain provider driver)))
(define (make-current-egl-gpu-provider)
  ((dynamic-require driver-module 'make-current-egl-provider)))
