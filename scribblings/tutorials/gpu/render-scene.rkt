#lang racket

;;;
;;; Render Scene
;;;

;; Selects a requested raster or GPU renderer for the shared tutorial scene.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline skia skia/gpu "scene.rkt")

;; Keep the platform choice explicit. There is no automatic renderer fallback.
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; backend : symbol?
  ;   Selects backend for the example.
  (define backend 'raster)

  ; output : path-string?
  ;   Selects the destination used by this example's output.
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

  ; image : image?
  ;   Retains the rendered image for output after the drawing operation completes.
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
