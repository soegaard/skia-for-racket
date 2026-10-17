#lang racket/base

;;;
;;; Reference Effects Test
;;;

;; Checks retained effect inputs, filter composition, runtime uniform packing, and programmable
;; blending.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in native CPU semantics. No fonts, GUI, or GPU context is required.
(require rackunit racket/list skia)


;;;
;;; Diagnostic Operations
;;;

; red-matrix : (listof real?)
;   Stores a row-major 4-by-5 color matrix that fixes red at one while retaining input alpha.
(define red-matrix
  '(0 0 0 0 1
    0 0 0 0 0
    0 0 0 0 0
    0 0 0 1 0))

; swap-matrix : (listof real?)
;   Stores a row-major 4-by-5 matrix that exchanges red and blue while retaining green and alpha.
(define swap-matrix
  '(0 0 1 0 0
    0 1 0 0 0
    1 0 0 0 0
    0 0 0 1 0))

; filtered-color : color-filter? any/c -> color?
;   Renders a constant color through a filter and samples an interior pixel.
(define (filtered-color filter color)
  (with-skia ([surface (make-surface 4 4)]
              [paint (make-paint #:color color #:color-filter filter)])
    (draw-paint (surface-canvas surface) paint)
    (surface-pixel surface 1 1)))

; shader-color : shader? -> color?
;   Renders a shader into a small surface and samples an interior pixel.
(define (shader-color shader)
  (with-skia ([surface (make-surface 4 4)] [paint (make-paint #:shader shader)])
    (draw-paint (surface-canvas surface) paint)
    (surface-pixel surface 1 1)))

; gain-source : string?
;   Provides a runtime shader with one scalar gain uniform for reflection and value checks.
(define gain-source
  "uniform float gain; half4 main(float2 p) { return half4(gain,0,0,1); }")

(module+ test
  (skia-check!)
  (test-case "paint retains a dash effect after its input wrapper closes"
    (with-skia ([surface (make-surface 40 8)]
                [dash (make-dash-path-effect '(8 4))]
                [paint (make-paint #:color 'red #:style 'stroke #:stroke-width 2
                                   #:antialias? #f #:path-effect dash)])
      (skia-close! dash)
      (draw-line (surface-canvas surface) 0 4 40 4 paint)
      (check-equal? (surface-pixel surface 3 4) (color->rgba 'red))
      (check-equal? (rgba-alpha (surface-pixel surface 10 4)) 0)))
  (test-case "RGBA matrix offsets use normalized rather than byte-valued channels"
    (with-skia ([filter (make-color-matrix-filter red-matrix)])
      (check-equal? (filtered-color filter 'blue) (color->rgba 'red))))
  (test-case "color composition applies the inner filter first"
    (with-skia ([red (make-color-matrix-filter red-matrix)]
                [swap (make-color-matrix-filter swap-matrix)]
                [outer-swap (make-compose-color-filter swap red)]
                [outer-red (make-compose-color-filter red swap)])
      (check-equal? (filtered-color outer-swap 'white) (color->rgba 'blue))
      (check-equal? (filtered-color outer-red 'white) (color->rgba 'red))))
  (test-case "color lookup tables are copied and false tables preserve channels"
    (define table (list->bytes (build-list 256 values)))
    (with-skia ([filter (make-table-argb-color-filter #:red table)])
      (bytes-fill! table 0)
      (check-equal? (filtered-color filter "#326DE6") (color->rgba "#326DE6")))
    (with-skia ([identity (make-table-argb-color-filter)])
      (check-true (color-filter? identity))
      (check-equal? (filtered-color identity 'blue) (color->rgba 'blue))))
  (test-case "lighting ignores the multiplier and addend alpha"
    (with-skia ([a (make-lighting-color-filter (rgba 255 255 255 0) (rgba 0 0 0 255))]
                [b (make-lighting-color-filter 'white 'black)])
      (check-equal? (filtered-color a "#326DE6") (filtered-color b "#326DE6"))))
  (test-case "merge false input is the dynamic source rather than an empty branch"
    (with-skia ([shift (make-offset-image-filter 10 0)]
                [both (make-merge-image-filter (list #f shift))]
                [paint (make-paint #:color 'blue #:antialias? #f #:image-filter both)]
                [surface (make-surface 30 10)])
      (skia-close! shift)
      (skia-close! both)
      (draw-rect (surface-canvas surface) 0 0 5 5 paint)
      (check-equal? (surface-pixel surface 2 2) (color->rgba 'blue))
      (check-equal? (surface-pixel surface 12 2) (color->rgba 'blue))
      (check-equal? (rgba-alpha (surface-pixel surface 7 2)) 0)))
  (test-case "identity graph nodes still return resources"
    (with-skia ([offset (make-offset-image-filter 0 0)]
                [blend (make-blend-image-filter 'src #f #f)])
      (check-true (image-filter? offset))
      (check-true (image-filter? blend))))
  (test-case "an explicit image source retains its image"
    (with-skia ([image (rgba-bytes->image 1 1 (bytes 255 0 0 255))]
                [source (make-image-source-filter image #:destination '(0 0 4 4)
                                                  #:sampling 'nearest)]
                [paint (make-paint #:image-filter source)]
                [surface (make-surface 4 4)])
      (skia-close! image)
      (draw-paint (surface-canvas surface) paint)
      (check-equal? (surface-pixel surface 1 1) (color->rgba 'red))))
  (test-case "runtime instances retain effects and copy uniform values"
    (define uniforms (make-hash (list (cons 'gain 0.5))))
    (with-skia ([effect (make-runtime-effect gain-source)]
                [shader (runtime-effect->shader effect #:uniforms uniforms)])
      (hash-set! uniforms 'gain 0)
      (skia-close! effect)
      (check-= (rgba-red (shader-color shader)) 128 1)
      (check-equal? (rgba-alpha (shader-color shader)) 255)))
  (test-case "closed effect metadata and uniform packing remain available"
    (with-skia ([effect (make-runtime-effect gain-source)])
      (define metadata (runtime-effect-uniforms effect))
      (skia-close! effect)
      (check-equal? (runtime-effect-kind effect) 'shader)
      (check-equal? (runtime-effect-source effect) gain-source)
      (check-equal? (runtime-uniform-name (car metadata)) "gain")
      (define packed (runtime-effect-uniform-bytes effect (hash 'gain 0.5)))
      (check-true (immutable? packed))
      (check-equal? (bytes-length packed) 4)
      (check-equal? (floating-point-bytes->real packed (system-big-endian?)) 0.5)
      (check-exn exn:fail?
                 (lambda () (runtime-effect->shader effect #:uniforms (hash 'gain 0.5))))))
  (test-case "runtime bindings reject missing extra and duplicate normalized names"
    (with-skia ([effect (make-runtime-effect gain-source)])
      (for ([bindings (in-list (list (hash) (hash 'gain 1 'extra 0)
                                    (hash 'gain 1 "gain" 1)))])
        (check-exn exn:fail? (lambda () (runtime-effect-uniform-bytes effect bindings))))
      (check-exn exn:fail? (lambda () (runtime-effect-uniform-bytes effect (hash 'gain '(1)))))
      (check-exn exn:fail? (lambda () (runtime-effect->color-filter effect)))))
  (test-case "runtime child shaders are typed required and retained"
    (with-skia ([effect (make-runtime-effect
                        "uniform shader child; half4 main(float2 p) { return child.eval(p); }")]
                [red (make-color-shader 'red)]
                [filter (make-table-argb-color-filter)])
      (check-exn exn:fail? (lambda () (runtime-effect->shader effect)))
      (check-exn exn:fail?
                 (lambda () (runtime-effect->shader effect #:children (hash 'child #f))))
      (check-exn exn:fail?
                 (lambda () (runtime-effect->shader effect #:children (hash 'child filter))))
      (with-skia ([shader (runtime-effect->shader effect #:children (hash 'child red))])
        (skia-close! effect)
        (skia-close! red)
        (check-equal? (shader-color shader) (color->rgba 'red)))))
  (test-case "runtime shader local matrices require a representable inverse"
    (with-skia ([effect (make-runtime-effect "half4 main(float2 p) { return half4(1); }")])
      (check-exn exn:fail?
                 (lambda () (runtime-effect->shader effect #:local-matrix (matrix-scale 0))))))
  (test-case "runtime color filters run in their declared stage"
    (with-skia ([effect (make-runtime-effect
                        "half4 main(half4 c) { return half4(c.b,c.g,c.r,c.a); }"
                        #:kind 'color-filter)]
                [filter (runtime-effect->color-filter effect)])
      (check-equal? (filtered-color filter 'red) (color->rgba 'blue))))
  (test-case "compiler errors carry immutable source kind and diagnostics"
    (with-handlers ([exn:fail:skia-sksl?
                    (lambda (e)
                      (check-equal? (exn:fail:skia-sksl-kind e) 'shader)
                      (check-equal? (exn:fail:skia-sksl-source e) "not valid SkSL")
                      (check-true (immutable? (exn:fail:skia-sksl-diagnostics e))))])
      (make-runtime-effect "not valid SkSL")
      (fail "Expected an SkSL compilation exception")))
  (test-case "blender getters are independently owned and false restores source-over"
    (with-skia ([blender (make-arithmetic-blender 0 1 0 0)]
                [paint (make-paint)])
      (paint-set-blender! paint blender)
      (define retained (paint-blender paint))
      (check-true (blender? retained))
      (call-with-skia-resource retained
        (lambda (copy)
          (paint-set-blender! paint #f)
          (skia-close! blender)
          (with-skia ([blue (make-color-shader 'blue)] [red (make-color-shader 'red)]
                      [shader (make-blender-shader copy blue red)])
            (check-equal? (shader-color shader) (color->rgba 'red)))))))
  (test-case "runtime blender uses source-first SkSL parameters"
    (with-skia ([effect (make-runtime-effect
                        "half4 main(half4 src, half4 dst) { return src; }" #:kind 'blender)]
                [blender (runtime-effect->blender effect)]
                [blue (make-color-shader 'blue)] [red (make-color-shader 'red)]
                [shader (make-blender-shader blender blue red)])
      (check-equal? (shader-color shader) (color->rgba 'red)))))
