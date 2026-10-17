#lang racket/base

;;;
;;; EGL GPU Entry Points
;;;

;; Creates headless EGL contexts or providers for an already-current EGL context.
;; This opt-in public entry point connects Linux EGL context management to the common GPU provider
;; and ownership interfaces.

;;;
;;; Imports and Exports
;;;

;; Explicit Linux EGL entry points. Importing this module initializes neither
;; EGL nor a GUI. Native platform loading happens only in these constructors.
(require racket/runtime-path "private/gpu-context.rkt" "private/gpu-domain.rkt"
         "private/gpu-egl-util.rkt")
(provide make-egl-gpu-context make-current-egl-gpu-provider)
; driver-module : path?
;;   Locates private/gpu-driver-egl.rkt for lazy loading of the selected implementation.
(define-runtime-path driver-module "private/gpu-driver-egl.rkt")
; make-egl-gpu-context : [#:platform (or/c 'surfaceless 'device)] [#:device-index
;   exact-nonnegative-integer?] [#:surface (or/c 'surfaceless 'pbuffer)] [#:options (or/c
;   gpu-context-options? #f)] [#:gl-interface (or/c 'default 'auto 'desktop)] -> gpu-context?
;;   Creates an owned desktop-OpenGL context through EGL.
(define (make-egl-gpu-context #:platform [platform 'surfaceless]
                              #:device-index [index 0]
                              #:surface [surface 'surfaceless]
                              #:options [options #f]
                              #:gl-interface [interface-mode 'default])
  (check-owned-egl-interface-mode 'make-egl-gpu-context interface-mode)
  (check-optional-context-options 'make-egl-gpu-context options)
  (check-egl-options 'make-egl-gpu-context platform index surface)
  (define-values (provider driver)
    ((dynamic-require driver-module 'make-owned-egl-components)
     platform index surface #:options options #:interface interface-mode))
  (wrap-gpu-domain (make-gpu-domain provider driver)))
; make-current-egl-gpu-provider : -> gpu-provider?
;;   Captures the currently bound desktop-EGL context as a borrowed GPU provider.
(define (make-current-egl-gpu-provider)
  ((dynamic-require driver-module 'make-current-egl-provider)))
(require (submod "gpu-context-options.rkt" internals))
(require "private/gpu-diagnostic-util.rkt")
