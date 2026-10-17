#lang racket/base

;;;
;;; Circle Example
;;;

;; Renders a red circle to PNG using a surface, its borrowed canvas, and a paint.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

(require racket/cmdline "../main.rkt")

; render-circle : path-string? -> void?
;   Renders a red circle and saves the surface as a PNG.
(define (render-circle filename)
  (with-skia ([s (make-surface 640 480 #:background 'white)]
              [p (make-paint #:color 'red)])
    (draw-circle (surface-canvas s) 320 240 100 p)
    (save-png s filename)))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; filename : path-string?
  ;   Selects the destination used by this example's output.
  (define filename
    (command-line #:program "circle.rkt" #:args ([output "circle.png"]) output))
  (render-circle filename)
  (printf "Wrote ~a\n" filename))
