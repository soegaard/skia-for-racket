#lang racket

(require rackunit "waves.rkt" skia)

(module+ test
  (define effect (make-runtime-effect wave-source))
  (define (render shader)
    (with-skia ([surface (make-surface 96 64)] [paint (make-paint #:shader shader)])
      (draw-rect (surface-canvas surface) 0 0 96 64 paint)
      (surface->rgba-bytes surface)))
  (test-case "all three shader programs compile on the CPU path"
    (for ([source (list solid-source coordinate-source wave-source)])
      (with-skia ([compiled (make-runtime-effect source)])
        (check-true (runtime-effect? compiled)))))
  (test-case "all shader uniforms are supplied"
    (check-exn exn:fail?
               (lambda () (runtime-effect->shader effect #:uniforms (hash 'bend 0.2)))))
  (test-case "phase changes the rendered pixels"
    (check-not-equal? (render (make-wave-shader effect 96 64 #:phase 0))
                      (render (make-wave-shader effect 96 64 #:phase 1))))
  (test-case "ordinary opaque palettes produce opaque output"
    (define pixels (render (make-wave-shader effect 96 64)))
    (check-true (for/and ([i (in-range 3 (bytes-length pixels) 4)])
                  (= 255 (bytes-ref pixels i)))))
  (test-case "uniform mutation does not change an existing shader"
    (define bindings (make-hash '((extent . (96 64)) (frequency . 5) (bend . 0.28)
                                  (phase . 0) (dark . (0.03 0.09 0.19 1))
                                  (light . (0.22 0.84 0.8 1)))))
    (define shader (runtime-effect->shader effect #:uniforms bindings))
    (define before (render shader))
    (hash-set! bindings 'phase 1)
    (check-equal? (render shader) before)
    (check-not-equal? (render (runtime-effect->shader effect #:uniforms bindings)) before))
  (test-case "invalid SkSL produces a compiler exception"
    (check-exn exn:fail:skia-sksl?
               (lambda () (make-runtime-effect "half4 main(float2 p) { invalid; }")))))
