#lang racket

(require racket/cmdline
         racket/file
         racket/path
         skia
         skia/gpu
         "scene.rkt")

(provide render-metal-scene)

(define (render-metal-scene output-path)
  (define target (path->complete-path output-path))
  (define image
    (render-gpu->raster-image
     scene-width scene-height draw-scene
     #:backend 'metal
     #:background scene-background))
  ;; GPU teardown has already completed. This scope only releases the CPU copy
  ;; promptly after encoding, including if directory creation or saving fails.
  (with-skia ([detached image])
    (make-directory* (or (path-only target) (current-directory)))
    (save-image detached target 'png #:exists 'replace))
  target)

(module+ main
  (define output-path
    (command-line
     #:program "gpu-offscreen.rkt"
     #:args ([output "gpu-metal.png"])
     output))
  (define written (render-metal-scene output-path))
  (printf "Wrote ~a using Metal\n" written))
