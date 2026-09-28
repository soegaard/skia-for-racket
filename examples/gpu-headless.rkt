#lang racket/base
(require racket/cmdline racket/file racket/path "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt")
(module+ main
  (define output "output/egl-headless.png")
  (define platform 'surfaceless) (define index 0) (define binding-surface 'surfaceless)
  (command-line #:once-each
    [("--output") path "PNG destination" (set! output path)]
    [("--egl-platform") name "surfaceless or device" (set! platform (string->symbol name))]
    [("--egl-device-index") value "Device enumeration index" (set! index (string->number value))]
    [("--egl-surface") name "surfaceless or pbuffer" (set! binding-surface (string->symbol name))]
    #:args () (void))
  (define context (make-egl-gpu-context #:platform platform #:device-index index #:surface binding-surface))
  (define image
    (dynamic-wind
      void
      (lambda ()
        (call-with-gpu-context context
          (lambda ()
            (with-skia ([surface (make-gpu-surface context 640 360 #:background 'white)]
                        [blue (make-paint #:color (rgba 28 123 166 255))]
                        [orange (make-paint #:color (rgba 239 156 43 255))]
                        [font (make-font #:size 28)])
              (define canvas (surface-canvas surface))
              (draw-rect canvas 32 100 240 180 blue)
              (draw-circle canvas 438 190 90 orange)
              (draw-simple-text canvas "EGL / Ganesh - no window" 32 56 font blue)
              (gpu-surface->raster-image surface)))))
      (lambda () (gpu-context-close! context))))
  (make-directory* (or (path-only (string->path output)) (current-directory)))
  (with-skia ([detached image]) (save-image detached output 'png #:exists 'replace))
  (displayln (gpu-context-info context))
  (printf "Saved ~a after closing the GPU context.\n" output))
