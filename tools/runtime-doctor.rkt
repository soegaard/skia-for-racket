#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt" "../tests/runtime-fixtures.rkt")
(provide runtime-doctor!)
(define (runtime-doctor!)
  (with-skia ([reflection (make-runtime-effect reflection-sksl)]
              [effect (make-runtime-effect solid-sksl)]
              [shader (runtime-effect->shader effect #:uniforms (hash 'color '(1 0 0 1)))]
              [filter-effect (make-runtime-effect invert-sksl #:kind 'color-filter)]
              [filter (runtime-effect->color-filter filter-effect)]
              [blend-effect (make-runtime-effect mix-sksl #:kind 'blender)]
              [blender (runtime-effect->blender blend-effect #:uniforms (hash 'amount 0.5))]
              [paint (make-paint #:shader shader #:color-filter filter)]
              [surface (make-surface 4 4 #:background 'blue)])
    (unless (and (= (runtime-effect-uniform-byte-size reflection) 60)
                 (equal? (map runtime-uniform-offset (runtime-effect-uniforms reflection))
                         '(0 4 16 24 40 44)))
      (error 'doctor "runtime uniform reflection has unexpected layout"))
    (paint-set-blender! paint blender)
    ;; Paint/native nodes retain their program, uniform data, and children.
    (skia-close! shader) (skia-close! effect)
    (skia-close! filter) (skia-close! filter-effect)
    (skia-close! blender) (skia-close! blend-effect)
    (draw-paint (surface-canvas surface) paint)
    ;; Invert red to cyan, then mix cyan (source) and blue (destination).
    (define pixel (surface-pixel surface 1 1))
    (unless (and (<= (rgba-red pixel) 2)
                 (<= 126 (rgba-green pixel) 130)
                 (>= (rgba-blue pixel) 253) (= (rgba-alpha pixel) 255))
      (error 'doctor "runtime shader/filter/blender output mismatch: ~s" pixel))
    (define bad (with-handlers ([exn:fail:skia-sksl? values])
                  (make-runtime-effect "half4 main(float2 p) { return not_declared; }")))
    (unless (and (exn:fail:skia-sksl? bad)
                 (positive? (string-length (exn:fail:skia-sksl-diagnostics bad))))
      (error 'doctor "runtime compiler did not return structured diagnostics")))
  (printf "Runtime effects passed: packed reflection, shader/filter/blender, retained inputs, compiler diagnostics; uniform=~a child=~a\n"
          (ctype-sizeof _sk-runtime-uniform) (ctype-sizeof _sk-runtime-child)))
