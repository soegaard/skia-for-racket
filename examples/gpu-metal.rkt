#lang racket/base
(require racket/cmdline racket/file racket/path
         "../main.rkt" "../gpu.rkt" "gpu-scenes.rkt")
(provide render-metal-example)
(define (render-metal-example path [scene 'gradients])
  (unless (memq scene gpu-scene-names)
    (raise-argument-error 'render-metal-example "name from gpu-scene-names" scene))
  (define target (path->complete-path path))
  (make-directory* (or (path-only target) (current-directory)))
  (define context (make-gpu-context #:backend 'metal))
  (define image
    (dynamic-wind void
      (lambda ()
        (call-with-gpu-context context
          (lambda ()
            (with-skia ([surface (make-gpu-surface context gpu-scene-width gpu-scene-height)])
              (draw-gpu-scene (surface-canvas surface) scene)
              (gpu-surface->raster-image surface)))))
      (lambda () (gpu-context-close! context))))
  (with-skia ([detached image]) (save-image detached target 'png #:exists 'replace))
  target)
(module+ main
  (define scene 'gradients)
  (command-line #:once-each
    [("--scene") name "Shared scene name" (set! scene (string->symbol name))]
    #:args ([filename "output/gpu-metal-example.png"])
    (displayln (render-metal-example filename scene))))
