#lang racket

;;;
;;; Linux Opengl
;;;

;; Creates an explicit Racket OpenGL context to render the shared GPU tutorial scene.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/class
         (only-in racket/gui/base canvas% frame% sleep/yield)
         (only-in racket/draw gl-config%)
         skia
         skia/gpu
         skia/gpu-racket-gl
         "scene.rkt")

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; gl-config : (is-a?/c gl-config%)
  ;;   Requests an OpenGL configuration for the tutorial's explicit host context.
  (define gl-config (new gl-config%))
  (send gl-config set-legacy? #f)

  ; gl-frame : (is-a?/c frame%)
  ;;   Hosts the Racket OpenGL canvas used to make the context current.
  (define gl-frame
    (new frame% [label "OpenGL host"]
         [width 320] [height 240]))
  ; gl-canvas : (is-a?/c canvas%)
  ;;   Owns the GUI canvas that supplies the OpenGL context for the tutorial.
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
