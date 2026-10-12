#lang racket

(require racket/class
         (only-in racket/gui/base canvas% frame% sleep/yield)
         (only-in racket/draw gl-config%)
         skia
         skia/gpu
         skia/gpu-racket-gl
         "scene.rkt")

(module+ main
  (define gl-config (new gl-config%))
  (send gl-config set-legacy? #f)

  (define gl-frame
    (new frame% [label "OpenGL host"]
         [width 320] [height 240]))
  (define gl-canvas
    (new canvas% [parent gl-frame]
         [style '(gl no-autoclear)]
         [gl-config gl-config]
         [paint-callback (lambda (_canvas _dc) (void))]))
  (dynamic-wind
    (lambda () (send gl-frame show #t))
    (lambda ()
      (sleep/yield 0.08)

      (define gl-context
        (send (send gl-canvas get-dc) get-gl-context))
      (unless (and gl-context (send gl-context ok?))
        (error 'linux-gpu-example "OpenGL context unavailable"))
      (define gl-provider
        (make-racket-gl-provider gl-context))

      (define linux-image
        (render-gpu->raster-image
         scene-width scene-height draw-scene
         #:backend 'opengl
         #:provider gl-provider
         #:background scene-background))

      (save-image linux-image "scene-opengl.png" 'png #:exists 'replace)
      (void))
    (lambda () (send gl-frame show #f))))
