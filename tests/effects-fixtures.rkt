#lang racket/base
(require racket/list "../main.rkt")
(provide effect-scene-names draw-effect-scene capture-effect-scene
         current-effects-renderer effect-pixel effect-width effect-height)
(define effect-width 64)
(define effect-height 48)
(define effect-scene-names
  '(stamp-1d stamp-2d line-2d table-mask gamma-mask clip-mask shader-mask
    fractal-noise turbulence shader-color-filter shader-blender runtime-blender
    arithmetic-blender image-blender picture-target empty-shader))
(define (effect-pixel bs x y)
  (define at (* 4 (+ x (* effect-width y))))
  (bytes->list (subbytes bs at (+ at 4))))
(define (cpu-render draw)
  (with-skia ([s (make-surface effect-width effect-height)])
    (draw (surface-canvas s))
    (surface->rgba-bytes s #:premultiplied? #t)))
(define current-effects-renderer (make-parameter cpu-render))
(define (capture-effect-scene name)
  ((current-effects-renderer) (lambda (c) (draw-effect-scene name c))))
(define (fill c paint)
  (draw-rect c 0 0 effect-width effect-height paint))
(define (masked-shape c mask)
  (with-skia ([p (make-paint #:color 'red #:mask-filter mask)]
              [shape (make-path '((move 8.25 6.25) (line 56.25 8.25)
                                  (line 48.25 40.25) (line 8.25 36.25) (close)))])
    ;; Paint retains its mask. The wrapper is deliberately closed before use.
    (skia-close! mask)
    (draw-path c shape p)))
(define (draw-effect-scene name c)
  (case name
    [(stamp-1d)
     (with-skia ([stamp (make-path '((move 0 0) (line 4 0) (line 4 4) (line 0 4) (close)))]
                 [effect (make-1d-path-effect stamp 12)]
                 [p (make-paint #:color 'red #:path-effect effect)]
                 [line (make-path '((move 8 24) (line 56 24)))])
       (path-reset! stamp) (skia-close! stamp) (skia-close! effect)
       (draw-path c line p))]
    [(stamp-2d)
     (with-skia ([stamp (make-path '((move -2 -2) (line 2 -2) (line 2 2) (line -2 2) (close)))]
                 [effect (make-2d-path-effect (matrix-scale 12 12) stamp)]
                 [p (make-paint #:color 'red #:path-effect effect)]
                 [shape (make-path '((move 4 4) (line 60 4) (line 60 44) (line 4 44) (close)))])
       (skia-close! stamp) (skia-close! effect) (draw-path c shape p))]
    [(line-2d)
     (with-skia ([effect (make-2d-line-path-effect 2 (matrix-scale 12 12))]
                 [p (make-paint #:color 'red #:path-effect effect)]
                 [shape (make-path '((move 4 4) (line 60 4) (line 60 44) (line 4 44) (close)))])
       (skia-close! effect) (draw-path c shape p))]
    [(table-mask)
     (define table (make-bytes 256 64))
     (with-skia ([mask (make-table-mask-filter table)])
       (bytes-fill! table 0) (masked-shape c mask))]
    [(gamma-mask)
     (with-skia ([mask (make-gamma-mask-filter 2)]) (masked-shape c mask))]
    [(clip-mask)
     (with-skia ([mask (make-clip-mask-filter 80 160)]) (masked-shape c mask))]
    [(shader-mask)
     (with-skia ([shader (make-color-shader (rgba 255 255 255 128))]
                 [mask (make-shader-mask-filter shader)])
       (skia-close! shader) (masked-shape c mask))]
    [(fractal-noise turbulence)
     (with-skia ([s ((if (eq? name 'fractal-noise) make-fractal-noise-shader make-turbulence-shader)
                     0.09 0.07 3 7 #:tile-size '(64 48))]
                 [p (make-paint #:shader s)])
       (skia-close! s) (fill c p))]
    [(shader-color-filter)
     (with-skia ([s (make-color-shader 'blue)]
                 [f (make-blend-color-filter 'red 'src)]
                 [combined (shader-with-color-filter s f)]
                 [p (make-paint #:shader combined)])
       (skia-close! s) (skia-close! f) (skia-close! combined) (fill c p))]
    [(shader-blender runtime-blender)
     (with-skia ([source (make-color-shader 'red)]
                 [destination (make-color-shader 'blue)])
       (define blender
         (if (eq? name 'shader-blender)
             (make-arithmetic-blender 0 0.25 0.75 0)
             (with-skia ([e (make-runtime-effect
                             "half4 main(half4 src, half4 dst) { return src * 0.25 + dst * 0.75; }"
                             #:kind 'blender)])
               (runtime-effect->blender e))))
       (call-with-skia-resource blender
         (lambda (b)
           (with-skia ([s (make-blender-shader b destination source)]
                       [p (make-paint #:shader s)])
             (skia-close! source) (skia-close! destination) (skia-close! b)
             (skia-close! s) (fill c p)))))]
    [(arithmetic-blender)
     (with-skia ([bg (make-paint #:color 'blue)]
                 [b (make-arithmetic-blender 0 0.25 0.75 0)]
                 [p (make-paint #:color 'red)])
       (fill c bg) (paint-set-blender! p b) (skia-close! b) (fill c p))]
    [(image-blender)
     (with-skia ([red (make-color-shader 'red)] [blue (make-color-shader 'blue)]
                 [bg (make-shader-image-filter red #:crop '(0 0 64 48))]
                 [fg (make-shader-image-filter blue #:crop '(0 0 64 48))]
                 [b (make-arithmetic-blender 0 0.25 0.75 0)]
                 [f (make-blender-image-filter b bg fg #:crop '(0 0 64 48))]
                 [p (make-paint #:image-filter f)])
       (for-each skia-close! (list red blue bg fg b f)) (fill c p))]
    [(picture-target)
     (with-skia ([pic (call-with-picture 64 48
                       (lambda (pc)
                         (with-skia ([red (make-paint #:color 'red)] [blue (make-paint #:color 'blue)])
                           (draw-rect pc 8 8 16 12 red) (draw-rect pc 32 8 16 12 blue))))]
                 [f (make-picture-image-filter pic #:target '(6 6 20 18))]
                 [p (make-paint #:image-filter f)])
       (skia-close! pic) (skia-close! f) (fill c p))]
    [(empty-shader)
     (with-skia ([bg (make-paint #:color 'blue)] [s (make-empty-shader)]
                 [p (make-paint #:shader s)])
       (fill c bg) (skia-close! s) (fill c p))]
    [else (raise-argument-error 'draw-effect-scene "symbol in effect-scene-names" name)]))
