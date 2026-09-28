#lang racket/base
;; The exact same ordinary Skia draw callback serves both window backends.
(require "../main.rkt" "../gpu.rkt" "gpu-scenes.rkt")
(provide draw-presentation-scene)
(define (draw-presentation-scene frame)
  (define c (gpu-frame-canvas frame))
  (define w (gpu-frame-width frame)) (define h (gpu-frame-height frame))
  (canvas-clear! c 'white)
  (with-canvas-state c
    (canvas-scale! c (/ w gpu-scene-width) (/ h gpu-scene-height))
    (draw-gpu-scene c 'perspective))
  ;; Large, unequal corner markers make vertical inversion and clipping easy
  ;; to inspect on a physical screen, including after moving between displays.
  (with-skia ([paint (make-paint #:color 'red)])
    (draw-rect c 0 0 18 18 paint)
    (paint-set-color! paint 'green) (draw-rect c (- w 26) 0 26 18 paint)
    (paint-set-color! paint 'blue) (draw-rect c 0 (- h 26) 18 26 paint)
    (paint-set-color! paint 'yellow) (draw-rect c (- w 26) (- h 26) 26 26 paint)))
