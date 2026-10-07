#lang racket/base
(require "../main.rkt")
(provide make-advanced-canvas-example)
(define (make-advanced-canvas-example)
  ;; Capture application drawing once as a genuine native recorded drawable.
  ;; Each replay retains the captured picture, not this Racket callback.
  (with-skia ([d (call-with-drawable 160 100
                  (lambda (c)
                    (with-skia ([p (make-paint #:color 'blue)])
                      (draw-circle c 80 50 32 p))))]
              [left (make-surface 160 100 #:background 'white)]
              [right (make-surface 160 100 #:background 'white)])
    (call-with-nway-canvas (list left right)
      (lambda (c)
        (with-skia ([opacity (make-paint #:color (rgba 0 0 0 160))])
          (call-with-canvas-layer-rec c (lambda () (draw-drawable c d))
            #:paint opacity #:clip '(0 0 160 100)))))
    (surface-snapshot left)))
(module+ main
  (with-skia ([im (make-advanced-canvas-example)])
    (save-image im "advanced-canvases.png" 'png #:exists 'replace)))
