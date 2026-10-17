#lang racket

;;;
;;; Shaders Tests
;;;

;; Checks Shaders tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit "waves.rkt" skia)

;;;
;;; Regression Checks
;;;

(module+ test

  ; effect : runtime-effect?
  ;   Retains the compiled wave effect reused by the tutorial figures or checks.
  (define effect (make-runtime-effect wave-source))

  ; render : any/c #:premultiplied? [boolean?] -> bytes?
  ;   Renders a small shader sample for pixel-level regression checks.
  (define (render shader #:premultiplied? [premultiplied? #f])
    (with-skia ([surface (make-surface 96 64)] [paint (make-paint #:shader shader)])
      (draw-rect (surface-canvas surface) 0 0 96 64 paint)
      (surface->rgba-bytes surface #:premultiplied? premultiplied?)))
  (test-case "all four shader programs compile on the CPU path"
    (for ([source (list solid-source coordinate-source bands-source wave-source)])
      (with-skia ([compiled (make-runtime-effect source)])
        (check-true (runtime-effect? compiled)))))
  (test-case "all shader uniforms are supplied"
    (check-exn exn:fail?
               (lambda () (runtime-effect->shader effect #:uniforms (hash 'bend 0.2)))))
  (test-case "elapsed seconds determine phase without a frame counter"
    (check-= (phase-at 0) 0 1e-12)
    (check-= (phase-at 0.5) 1 1e-12)
    (check-= (phase-at 1.5) 3 1e-12))
  (test-case "phase changes the rendered pixels even with straight bands"
    (check-not-equal? (render (make-wave-shader effect 96 64 #:bend 0 #:phase 0))
                      (render (make-wave-shader effect 96 64 #:bend 0 #:phase 1))))
  (test-case "animated scene reuses one effect and redraws at new times"
    (define (frame seconds)
      (with-skia ([surface (make-surface 320 180)])
        (draw-wave-scene (surface-canvas surface) effect seconds 320 180)
        (surface->rgba-bytes surface)))
    (define still (frame 0))
    (check-equal? (subbytes still 0 4) (bytes 7 13 33 255))
    (check-not-equal? still (frame 0.8))
    (check-equal? still (frame 0)))
  (test-case "shader output is fully opaque"
    (define pixels (render (make-wave-shader effect 96 64)))
    (check-true (for/and ([i (in-range 3 (bytes-length pixels) 4)])
                  (= 255 (bytes-ref pixels i)))))
  (test-case "uniform mutation does not change an existing shader"
    (define bindings
      (make-hash '((extent . (96 64))
                   (frequency . 5)
                   (bend . 0.30)
                   (phase . 0)
                   (hue . 0.08)
                   (glow . 1.0))))
    (define shader (runtime-effect->shader effect #:uniforms bindings))
    (define before (render shader))
    (hash-set! bindings 'phase 1)
    (check-equal? (render shader) before)
    (check-not-equal? (render (runtime-effect->shader effect #:uniforms bindings))
                      before))
  (test-case "frequency changes the rendered pattern"
    (check-not-equal? (render (make-wave-shader effect 96 64 #:bend 0 #:frequency 3))
                      (render (make-wave-shader effect 96 64 #:bend 0 #:frequency 8))))
  (test-case "hue shifts the rainbow palette"
    (check-not-equal? (render (make-wave-shader effect 96 64 #:hue 0.08))
                      (render (make-wave-shader effect 96 64 #:hue 0.58))))
  (test-case "glow uniform changes the crests without recompiling the effect"
    (check-not-equal? (render (make-wave-shader effect 96 64 #:glow 0))
                      (render (make-wave-shader effect 96 64 #:glow 1))))
  (test-case "panel translation preserves the local pattern; moving only geometry does not"
    (define (panel-bytes x y translate?)
      (with-skia ([surface (make-surface 128 88)]
                  [shader (make-wave-shader effect 96 64)]
                  [paint (make-paint #:shader shader)])
        (define canvas (surface-canvas surface))
        (if translate?
            (draw-wave-panel canvas effect x y 96 64)
            (draw-rounded-rect canvas x y 96 64 20 20 paint))
        (define pixels (surface->rgba-bytes surface))
        (apply bytes-append
               (for/list ([row (in-range y (+ y 64))])
                 (define offset (* 4 (+ x (* row 128))))
                 (subbytes pixels offset (+ offset (* 4 96)))))))
    (define original (panel-bytes 0 0 #t))
    (define translated (panel-bytes 32 24 #t))
    (for ([a (in-bytes original)] [b (in-bytes translated)])
      (check-true (<= (abs (- a b)) 2)))
    (check-not-equal? original (panel-bytes 32 24 #f)))
  (test-case "invalid SkSL produces a compiler exception"
    (check-exn exn:fail:skia-sksl?
               (lambda () (make-runtime-effect "half4 main(float2 p) { invalid; }")))))
