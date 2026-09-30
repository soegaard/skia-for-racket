#lang racket/base
(require racket/runtime-path "../gpu.rkt"
         (only-in "../private/gpu-d3d12-util.rkt" d3d12-selection!))
(provide call-with-gpu-backend-host)
(define-runtime-path gl-host-module "gpu-gui-host.rkt")
(define-runtime-path egl-module "../gpu-egl.rkt")
;; Supply a context maker, not a raw backend handle. Metal needs no host;
;; creating each context owns a new command queue. GL borrows its GUI host.
(define (call-with-gpu-backend-host backend proc #:host [host 'gui]
                                    #:egl-platform [platform 'surfaceless]
                                    #:egl-device-index [index 0]
                                    #:egl-surface [surface 'surfaceless]
                                    #:adapter [adapter #f] #:adapter-index [adapter-index #f])
  (unless (gpu-backend? backend)
    (raise-argument-error 'call-with-gpu-backend-host "GPU backend" backend))
  (unless (memq host '(gui egl owned))
    (raise-argument-error 'call-with-gpu-backend-host "'gui, 'egl, or 'owned" host))
  (when (and (eq? host 'owned) (eq? backend 'opengl))
    (error 'call-with-gpu-backend-host "OpenGL requires a GUI or explicit EGL host"))
  (when (and (or adapter adapter-index) (not (eq? backend 'direct3d)))
    (error 'call-with-gpu-backend-host "adapter selection requires Direct3D"))
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
    [(direct3d)
     (define selection (or adapter 'hardware))
     (define selected-index (or adapter-index 0))
     (d3d12-selection! selection selected-index)
     (proc (lambda () (make-gpu-context #:backend 'direct3d
                                      #:adapter selection #:adapter-index selected-index))
           (hasheq 'provider "owned Direct3D device/queue" 'headless #t
                   'presentation_tested #f 'requires_gl_context #f 'requires_gui #f
                   'window_created #f 'requested_adapter (symbol->string selection)
                   'requested_adapter_index selected-index))]))
