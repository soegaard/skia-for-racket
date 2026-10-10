#lang racket

(require racket/cmdline
         racket/file
         racket/path
         skia
         skia/gpu
         "scene.rkt")

(provide render-metal-scene)

(define (render-metal-scene output-path)
  (define target
    (path->complete-path output-path))
  (make-directory*
   (or (path-only target)
       (current-directory)))

  (define context
    (make-gpu-context #:backend 'metal))

  (unless (eq? (gpu-context-backend context)
               'metal)
    (error 'render-metal-scene
           "context did not use Metal"))

  (define detached-image
    (dynamic-wind
      void
      (lambda ()
        (call-with-gpu-context
         context
         (lambda ()
           (with-skia
               ([surface
                 (make-gpu-surface
                  context
                  scene-width scene-height
                  #:background scene-background)])
             (define canvas
               (surface-canvas surface))
             (unless
                 (and
                  (eq? (surface-backend surface)
                       'metal)
                  (eq? (canvas-execution-backend canvas)
                       'metal))
               (error 'render-metal-scene
                      "drawing target did not use Metal"))
             (draw-scene canvas)
             (gpu-surface->raster-image
              surface)))))
      (lambda ()
        (gpu-context-close! context))))

  (save-image detached-image
              target
              'png
              #:exists 'replace)
  target)

(module+ main
  (define output-path
    (command-line
     #:program "gpu-offscreen.rkt"
     #:args ([output "gpu-metal.png"])
     output))
  (define written
    (render-metal-scene output-path))
  (printf "Wrote ~a using Metal\n" written))
