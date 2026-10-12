#lang racket
(require rackunit skia "atlas.rkt" "scene.rkt" "model.rkt" "../support/sprite-math.rkt")
(module+ test
  (test-case "atlas is the actual 224 by 112 CPU image"
    (with-skia ([atlas (make-ball-atlas)])
      (check-equal? (image-width atlas) 224)
      (check-equal? (image-height atlas) 112)))
  (test-case "gutter pixels remain transparent"
    (with-skia ([atlas (make-ball-atlas)])
      (define pixels (image->rgba-bytes atlas))
      (for* ([y (in-range 112)] [x (in-range 224)]
             #:when (or (< (modulo x 56) 4) (>= (modulo x 56) 52)
                        (< (modulo y 56) 4) (>= (modulo y 56) 52)))
        (check-equal? (bytes-ref pixels (+ 3 (* 4 (+ x (* 224 y))))) 0))))
  (test-case "every cell contains an opaque center"
    (with-skia ([atlas (make-ball-atlas)])
      (define pixels (image->rgba-bytes atlas))
      (for ([index (in-range 8)])
        (match-define (list x y _ _) (sprite-source index))
        (check-equal? (bytes-ref pixels (+ 3 (* 4 (+ (+ x 24) (* 224 (+ y 24)))))) 255))))
  (test-case "atlas drawing agrees with a source-rectangle draw"
    (with-skia ([atlas (make-ball-atlas)] [first (make-surface 64 64)]
                [second (make-surface 64 64)])
      (match-define (list x y w h) (sprite-source 1))
      (draw-atlas (surface-canvas first) atlas
                  (list (make-atlas-transform 32 32 #:anchor sprite-anchor))
                  (list (sprite-source 1)) #:sampling 'nearest)
      (draw-image-subrect (surface-canvas second) atlas x y w h 8 8 48 48 #:sampling 'nearest)
      (check-equal? (surface->rgba-bytes first) (surface->rgba-bytes second))))
  (test-case "one simulated second changes the rendered scene"
    (with-skia ([atlas (make-ball-atlas)] [surface (make-surface scene-width scene-height)])
      (define world (make-ball-world))
      (draw-balls (surface-canvas surface) atlas world)
      (define first (surface->rgba-bytes surface))
      (for ([_ (in-range 120)]) (step-balls! world fixed-step void))
      (draw-balls (surface-canvas surface) atlas world)
      (check-not-equal? first (surface->rgba-bytes surface)))))
