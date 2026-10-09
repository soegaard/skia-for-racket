#lang racket/base
(require "gpu-egl-system.rkt" "gpu-egl-util.rkt" "gpu-driver-gl.rkt")
(provide make-owned-egl-components make-current-egl-provider)
(define (make-owned-egl-components platform index surface #:options [options #f]
                                    #:interface [interface-mode 'default])
  (make-egl-components (make-egl-platform-ops platform index surface)
    (lambda (provider) (make-gl-driver provider #:options options #:interface interface-mode))))
(define (make-current-egl-provider) (capture-current-egl-provider))
