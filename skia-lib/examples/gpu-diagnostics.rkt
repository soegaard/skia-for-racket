#lang racket/base

;;;
;;; GPU Diagnostics Example
;;;

;; Reports context, cache, and memory diagnostics for an explicitly selected GPU.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Public APIs only. This example really creates the explicitly selected backend.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline json "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt")
(provide describe-current-gpu)

;;;
;;; Current GPU Context Diagnostics
;;;

; describe-current-gpu : gpu-context? -> hash?
;   Returns context, cache, and memory diagnostics as a JSON-compatible hash.
(define (describe-current-gpu context)
  (hasheq 'context (gpu-context-info context)
          'budgeted_cache (gpu-cache-info context)
          'memory_dump (memory-statistics->jsexpr (gpu-memory-statistics context))
          'gl_interface (and (eq? (gpu-context-backend context) 'opengl)
                             (gpu-gl-interface-info context))))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; backend : symbol?
  ;   Selects backend for the example.
  (define backend 'auto)

  ; adapter : symbol?
  ;   Selects the requested GPU adapter, or leaves backend selection at its default.
  (define adapter 'hardware)
  (command-line #:once-each
    [("--backend") b "egl, metal, direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    #:args () (void))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (unless (memq adapter '(hardware warp)) (error 'gpu-diagnostics "invalid adapter"))

  (call-with-new-gpu-context
   (lambda ()
     (case backend
       [(egl) (make-egl-gpu-context #:gl-interface 'auto)]
       [(metal) (make-gpu-context #:backend 'metal)]
       [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
       [else (error 'gpu-diagnostics "unknown backend")]))
   (lambda (context)
     (with-skia ([surface (make-gpu-surface context 32 24)])
       (canvas-clear! (surface-canvas surface) (rgb 17 34 51))
       ;; Explicit submission is example setup, not part of the diagnostic.
       (gpu-flush! context)
       (gpu-submit! context #:wait? #t)
       (write-json (describe-current-gpu context))
       (newline)))))
