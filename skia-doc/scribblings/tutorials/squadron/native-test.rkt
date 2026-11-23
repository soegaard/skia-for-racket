#lang racket

;;;
;;; Squadron Native Test
;;;

;; Checks Squadron tutorial behavior with native rendering tests.
;; This module guards the documentation's examples and support code against regressions.

;;;
;;; Imports and Exports
;;;

(require rackunit skia "atlas.rkt" "scene.rkt" "model.rkt" "../support/sprite-math.rkt")

;;;
;;; Regression Checks
;;;

(module+ test
  (test-case "game atlas has 16 bounded cells"
    (with-skia ([atlas (make-game-atlas)])
      (check-equal? (image-width atlas) 224)
      (check-equal? (image-height atlas) 224)
      (check-equal? (vector-length sprite-names) 16)))
  (test-case "all sprite cells have actual artwork and isolated gutters"
    (with-skia ([atlas (make-game-atlas)])
      (define pixels (image->rgba-bytes atlas))
      (for ([index (in-range 16)])
        (match-define (list x y w h) (sprite-source index))
        (check-true
         (for/or ([yy (in-range y (+ y h))])
           (for/or ([xx (in-range x (+ x w))])
             (positive? (bytes-ref pixels (+ 3 (* 4 (+ xx (* 224 yy))))))))))
      (for* ([y (in-range 224)] [x (in-range 224)]
             #:when (or (< (modulo x 56) 4) (>= (modulo x 56) 52)
                        (< (modulo y 56) 4) (>= (modulo y 56) 52)))
        (check-equal? (bytes-ref pixels (+ 3 (* 4 (+ x (* 224 y))))) 0))))
  (test-case "game drawing does not change the model"
    (with-skia ([atlas (make-game-atlas)] [surface (make-surface scene-width scene-height)])
      (define world (demonstration-game))
      (define before (format "~s" world))
      (draw-game (surface-canvas surface) atlas world)
      (check-equal? (format "~s" world) before)))
  (test-case "the nose of a zero-degree enemy points down"
    (check-= (travel-heading 0 0 0 10) 0 1e-9)
    (check-= (travel-heading 0 0 10 0) -90 1e-9)
    (check-= (travel-heading 0 0 0 -10) -180 1e-9)
    (check-= (travel-heading 0 0 -10 0) 90 1e-9))
  (test-case "diving sprites face along the simulated trajectory"
    (define attack (dive 120 180 166 420 1))
    (define sprite (enemy 7 'scout 1 attack))
    (define-values (x y) (enemy-position sprite 120))
    (define future (struct-copy enemy sprite
                                [dive (struct-copy dive attack [age 121])]))
    (define-values (next-x next-y) (enemy-position future 121))
    (define radians (* (/ pi 180) (enemy-angle sprite 120)))
    (define nose-x (- (sin radians)))
    (define nose-y (cos radians))
    (check-true (> (+ (* (- next-x x) nose-x) (* (- next-y y) nose-y)) 0)))
  (test-case "render lists select only defined atlas cells"
    (for ([sprite (in-list (game-sprites (demonstration-game)))])
      (check-true (<= 0 (first sprite) 15))))
  (test-case "the illustrated game is not a black image"
    (with-skia ([atlas (make-game-atlas)] [surface (make-surface scene-width scene-height)])
      (draw-game (surface-canvas surface) atlas (demonstration-game))
      (define pixels (surface->rgba-bytes surface))
      (check-true (> (for/sum ([i (in-range 0 (bytes-length pixels) 4)]
                               #:when (> (bytes-ref pixels i) 150)) 1)
                    500)))))
