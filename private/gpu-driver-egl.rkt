#lang racket/base
(require "gpu-egl-system.rkt" "gpu-egl-util.rkt" "gpu-driver-gl.rkt")
(provide make-owned-egl-components make-current-egl-provider)
(define (make-owned-egl-components platform index surface)
  (make-egl-components (make-egl-platform-ops platform index surface) make-gl-driver))
(define (make-current-egl-provider) (capture-current-egl-provider))
