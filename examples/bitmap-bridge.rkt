#lang racket/base

;;;
;;; Bitmap Bridge Example
;;;

;; Copies a Skia drawing into a Racket bitmap and saves the detached result.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline "../main.rkt" "../bitmap.rkt")

;;;
;;; Drawing Data and Helpers
;;;

; render-bitmap : path-string? -> void?
;   Saves a detached Racket bitmap without replacing an existing destination.
(define (render-bitmap filename)
  ;; The returned bitmap owns a copy and can outlive the Skia surface.
  (define bm
    (with-skia ([s (make-surface 320 240)]
                [p (make-paint #:color (rgba 35 115 235 180))])
      (draw-circle (surface-canvas s) 160 120 80 p)
      (surface->bitmap s)))
  ;; This example deliberately exercises racket/draw's PNG encoder instead.
  (when (file-exists? filename)
    (error 'bitmap-bridge "output file already exists: ~a" filename))
  (unless (send bm save-file filename 'png)
    (error 'bitmap-bridge "could not save ~a" filename)))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; filename : path-string?
  ;   Selects the destination used by this example's output.
  (define filename
    (command-line #:program "bitmap-bridge.rkt" #:args ([output "bitmap.png"]) output))
  (render-bitmap filename)
  (printf "Wrote ~a\n" filename))
