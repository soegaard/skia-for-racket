#lang racket/base
;; Public APIs only. This example really creates the explicitly selected backend.
(require racket/cmdline json "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt")
(provide describe-current-gpu)
(define (describe-current-gpu context)
  (hasheq 'context (gpu-context-info context)
          'budgeted_cache (gpu-cache-info context)
          'memory_dump (memory-statistics->jsexpr (gpu-memory-statistics context))
          'gl_interface (and (eq? (gpu-context-backend context) 'opengl)
                             (gpu-gl-interface-info context))))
(module+ main
  (define backend 'auto)
  (define adapter 'hardware)
  (command-line #:once-each
    [("--backend") b "egl, metal, direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    #:args () (void))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (unless (memq adapter '(hardware warp)) (error 'gpu-diagnostics "invalid adapter"))
  (define context
    (case backend
      [(egl) (make-egl-gpu-context #:gl-interface 'auto)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'gpu-diagnostics "unknown backend")]))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context context
        (lambda ()
          (with-skia ([surface (make-gpu-surface context 32 24)])
            (canvas-clear! (surface-canvas surface) (rgb 17 34 51))
            ;; Explicit submission is example setup, not part of the diagnostic.
            (gpu-flush! context)
            (gpu-submit! context #:wait? #t)
            (write-json (describe-current-gpu context))
            (newline)))))
    (lambda () (gpu-context-close! context))))
