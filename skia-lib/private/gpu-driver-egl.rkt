#lang racket/base

;;;
;;; EGL GPU Driver
;;;

;; Constructs the GL driver through an EGL context provider.
;; Connects the EGL backend to the same domain lifecycle as other GL contexts.

(require "gpu-egl-system.rkt" "gpu-egl-util.rkt" "gpu-driver-gl.rkt")
(provide make-owned-egl-components make-current-egl-provider)

; make-owned-egl-components : any/c any/c any/c [#:options any/c] [#:interface any/c] -> any
;   Creates a desktop EGL provider and matching GL driver with consistent interface options.
(define (make-owned-egl-components platform index surface #:options [options #f]
                                    #:interface [interface-mode 'default])
  (make-egl-components (make-egl-platform-ops platform index surface)
    (lambda (provider) (make-gl-driver provider #:options options #:interface interface-mode))))

; make-current-egl-provider : -> any
;   Captures the caller's current EGL context without taking ownership of its destruction.
(define (make-current-egl-provider) (capture-current-egl-provider))
