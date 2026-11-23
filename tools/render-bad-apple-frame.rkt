#lang racket/base

;;;
;;; Bad Apple!! Acceptance Frame Renderer
;;;

;; Renders one prepared frame without creating a window. This is useful for comparing the documented
;; acceptance indices against an independent SVG renderer at exactly 480 by 360 pixels.

(require racket/cmdline
         "../skia-lib/examples/bad-apple/data.rkt"
         "../skia-lib/examples/bad-apple/scene.rkt"
         "../skia-lib/main.rkt")

(module+ main
  (define data-path #f)
  (define output-path #f)
  (define frame-index #f)
  (command-line
   #:program "render-bad-apple-frame.rkt"
   #:once-each
   [("--data") path "prepared frames.json.gz path" (set! data-path path)]
   [("--frame") frame "zero-based frame index"
    (define parsed (string->number frame))
    (unless (exact-nonnegative-integer? parsed)
      (raise-argument-error '--frame "zero-based exact nonnegative integer" frame))
    (set! frame-index parsed)]
   [("--output") path "PNG output path" (set! output-path path)]
   #:args () (void))
  (unless data-path (error 'render-bad-apple-frame.rkt "--data is required"))
  (unless output-path (error 'render-bad-apple-frame.rkt "--output is required"))
  (unless frame-index (error 'render-bad-apple-frame.rkt "--frame is required"))
  (define asset (read-bad-apple-asset data-path))
  (unless (< frame-index (bad-apple-asset-frame-count asset))
    (raise-arguments-error 'render-bad-apple-frame.rkt "frame index is outside this asset"
                           "frame" frame-index
                           "last valid frame" (sub1 (bad-apple-asset-frame-count asset))))
  ;; The synchronously built scene and surface live on this process's main thread, satisfying the
  ;; same native ownership contract as the GUI player.
  (define scene (compile-bad-apple-scene asset))
  (dynamic-wind
    void
    (lambda ()
      (with-skia ([surface (make-surface 480 360 #:background 'black)])
        (draw-bad-apple-frame (surface-canvas surface) scene frame-index 480 360)
        (save-png surface output-path #:exists 'replace)))
    (lambda () (bad-apple-scene-close! scene)))
  (printf "Wrote frame ~a to ~a\n" frame-index output-path))
