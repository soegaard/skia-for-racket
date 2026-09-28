#lang racket/base
(require racket/runtime-path "../gpu.rkt")
(provide call-with-gpu-backend-host)
(define-runtime-path gl-host-module "gpu-gui-host.rkt")
(define-runtime-path egl-module "../gpu-egl.rkt")
;; Supply a context maker, not a raw backend handle. Metal needs no host;
;; creating each context owns a new command queue. GL borrows its GUI host.
(define (call-with-gpu-backend-host backend proc #:host [host 'gui]
                                    #:egl-platform [platform 'surfaceless]
                                    #:egl-device-index [index 0]
                                    #:egl-surface [surface 'surfaceless])
  (unless (memq host '(gui egl))
    (raise-argument-error 'call-with-gpu-backend-host "'gui or 'egl" host))
  (when (and (eq? host 'egl) (not (eq? backend 'opengl)))
    (error 'call-with-gpu-backend-host "EGL host requires the OpenGL backend"))
  (case backend
    [(opengl)
     (if (eq? host 'egl)
         (proc (lambda () ((dynamic-require egl-module 'make-egl-gpu-context)
                            #:platform platform #:device-index index #:surface surface))
               (hasheq 'provider "owned EGL headless host" 'headless #t 'window_created #f
                       'egl_platform (symbol->string platform) 'egl_surface (symbol->string surface)
                       'presentation_tested #f 'display_server_free #t))
         ((dynamic-require gl-host-module 'call-with-gpu-test-host)
          (lambda (provider info) (proc (lambda () (make-gpu-context provider)) info))))]
    [(metal)
     (proc (lambda () (make-gpu-context #:backend 'metal))
           (hasheq 'provider "owned Metal device/queue" 'headless #t
                   'presentation_tested #f 'requires_gl_context #f 'window_created #f))]
    [else (raise-argument-error 'call-with-gpu-backend-host "'opengl or 'metal" backend)]))
