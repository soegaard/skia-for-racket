#lang racket/base
(require racket/cmdline racket/file racket/path json "../main.rkt" "../gpu.rkt")
(module+ main
  (define adapter 'warp)
  (define index 0)
  (define destination
    (command-line
     #:once-each
     [("--adapter") name "warp or hardware (default warp)" (set! adapter (string->symbol name))]
     [("--adapter-index") number "exact hardware adapter index" (set! index (string->number number))]
     #:args (output-png) (path->complete-path output-png)))
  (define context (make-gpu-context #:backend 'direct3d #:adapter adapter #:adapter-index index))
  (write-json (gpu-context-info context)) (newline)
  (define detached
    (dynamic-wind
      void
      (lambda ()
        (call-with-gpu-context context
          (lambda ()
            (with-skia ([surface (make-gpu-surface context 320 180 #:background 'white)]
                        [paint (make-paint #:color 'blue)])
              (draw-rect (surface-canvas surface) 24 24 140 96 paint)
              ;; Explicit completion and CPU transfer are part of this call.
              (gpu-surface->raster-image surface)))))
      (lambda () (gpu-context-close! context))))
  ;; The context is closed: only the detached CPU image remains.
  (with-skia ([image detached])
    (make-directory* (path-only destination))
    (call-with-output-file destination
      (lambda (out) (write-bytes (image->png-bytes image) out)) #:exists 'error))
  (printf "Wrote ~a after context teardown.\n" destination))
