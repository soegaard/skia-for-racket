#lang racket/base

;;;
;;; GPU Headless Example
;;;

;; Renders a headless OpenGL image through an explicitly configured EGL binding.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file racket/path "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt")

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; output : string?
  ;   Selects the destination used by this example's output.
  (define output "output/egl-headless.png")

  ; platform : symbol?
  ;   Selects platform for the example.
  (define platform 'surfaceless)

  ; index : exact-integer?
  ;   Selects the device or adapter enumeration index requested by the command line.
  (define index 0)

  ; binding-surface : symbol?
  ;   Selects binding surface for the example.
  (define binding-surface 'surfaceless)
  (command-line #:once-each
    [("--output") path "PNG destination" (set! output path)]
    [("--egl-platform") name "surfaceless or device" (set! platform (string->symbol name))]
    [("--egl-device-index") value "Device enumeration index" (set! index (string->number value))]
    [("--egl-surface") name "surfaceless or pbuffer" (set! binding-surface (string->symbol name))]
    #:args () (void))

  ; image : image?
  ;   Holds the rendered CPU image after the scoped GPU context has closed.
  (define image
    (call-with-new-gpu-context
     (lambda ()
       (make-egl-gpu-context #:platform platform #:device-index index #:surface binding-surface))
     (lambda (context)
       (displayln (gpu-context-info context))
       (with-skia ([surface (make-gpu-surface context 640 360 #:background 'white)]
                   [blue (make-paint #:color (rgba 28 123 166 255))]
                   [orange (make-paint #:color (rgba 239 156 43 255))]
                   [font (make-font #:size 28)])
         (define canvas (surface-canvas surface))
         (draw-rect canvas 32 100 240 180 blue)
         (draw-circle canvas 438 190 90 orange)
         (draw-simple-text canvas "EGL / Ganesh - no window" 32 56 font blue)
         (gpu-surface->raster-image surface)))))
  (make-directory* (or (path-only (string->path output)) (current-directory)))
  (with-skia ([detached image]) (save-image detached output 'png #:exists 'replace))
  (printf "Saved ~a after closing the GPU context.\n" output))
