#lang racket

(require racket/cmdline skia skia/gpu "scene.rkt")

;; Keep the platform choice explicit. There is no automatic renderer fallback.
(module+ main
  (define backend 'raster)
  (define output
    (command-line
     #:program "render-scene.rkt"
     #:once-each
     [("--backend") value "Choose raster, metal, or direct3d"
      (set! backend (string->symbol value))]
     #:args ([output "scene.png"])
     output))
  (unless (memq backend '(raster metal direct3d))
    (raise-user-error 'render-scene
                      "choose raster, metal, or direct3d; Linux OpenGL uses linux-opengl.rkt"))
  (define image
    (case backend
      [(raster)
       (with-skia ([surface (make-surface scene-width scene-height
                                         #:background scene-background)])
         (draw-scene (surface-canvas surface))
         (surface-snapshot surface))]
      [else
       (render-gpu->raster-image scene-width scene-height draw-scene
                                 #:backend backend #:background scene-background)]))
  (with-skia ([result image])
    (save-image result output 'png #:exists 'replace))
  (printf "Wrote ~a using ~a\n" output backend))
