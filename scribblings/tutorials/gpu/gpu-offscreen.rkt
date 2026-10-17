#lang racket

;;;
;;; GPU Offscreen
;;;

;; Renders the shared tutorial scene to a Metal surface and saves the readback.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline
         racket/file
         racket/path
         skia
         skia/gpu
         "scene.rkt")

(provide render-metal-scene)

;;;
;;; Drawing Data and Helpers
;;;

; render-metal-scene : path-string? -> path?
;   Renders the shared scene in Metal, saves its readback, and returns the output path.
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

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; output-path : path-string?
  ;   Names the destination selected for the rendered tutorial image.
  (define output-path
    (command-line
     #:program "gpu-offscreen.rkt"
     #:args ([output "gpu-metal.png"])
     output))

  ; written : path?
  ;   Retains the completed image path for the command-line status message.
  (define written (render-metal-scene output-path))
  (printf "Wrote ~a using Metal\n" written))
