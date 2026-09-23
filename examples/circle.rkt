#lang racket/base
(require racket/cmdline "../main.rkt")

(define (render-circle filename)
  (with-skia ([s (make-surface 640 480 #:background 'white)]
              [p (make-paint #:color 'red)])
    (draw-circle (surface-canvas s) 320 240 100 p)
    (save-png s filename)))

(module+ main
  (define filename
    (command-line #:program "circle.rkt" #:args ([output "circle.png"]) output))
  (render-circle filename)
  (printf "Wrote ~a\n" filename))
