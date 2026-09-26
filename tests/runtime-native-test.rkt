#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../main.rkt" "runtime-fixtures.rkt")
(provide runtime-native-tests)

(define (check-rgba-near actual expected [tolerance 2])
  (for ([a (in-list (list (rgba-red actual) (rgba-green actual)
                          (rgba-blue actual) (rgba-alpha actual)))]
        [e (in-list expected)])
    (check-= a e tolerance)))
(define (shader-pixel sh [x 0] [y 0])
  (with-skia ([s (make-surface 24 24)] [p (make-paint #:shader sh)])
    (draw-paint (surface-canvas s) p)
    (surface-pixel s x y)))
(define (filter-pixel cf)
  (with-skia ([s (make-surface 2 2)]
              [p (make-paint #:color 'red #:color-filter cf)])
    (draw-paint (surface-canvas s) p)
    (surface-pixel s 0 0)))
(define (blend-pixel b)
  (with-skia ([s (make-surface 2 2 #:background 'blue)]
              [p (make-paint #:color 'red)])
    (paint-set-blender! p b)
    (draw-paint (surface-canvas s) p)
    (surface-pixel s 0 0)))
(define (in-other-thread thunk)
  (define ch (make-channel))
  (define t
    (thread (lambda ()
              (channel-put ch (with-handlers ([exn? values]) (thunk))))))
  (define result (channel-get ch))
  (thread-wait t)
  result)

(define runtime-native-tests
  (test-suite
   "Runtime effects: native compilation, rendering, and ownership"
   (test-case "shader compilation and empty reflection"
     (with-skia ([e (make-runtime-effect coordinate-sksl)])
       (check-true (runtime-effect? e))
       (check-true (skia-resource? e))
       (check-equal? (runtime-effect-kind e) 'shader)
       (check-equal? (runtime-effect-source e) coordinate-sksl)
       (check-equal? (runtime-effect-uniform-byte-size e) 0)
       (check-equal? (runtime-effect-uniforms e) '())
       (check-equal? (runtime-effect-children e) '())))
   (test-case "invalid source raises structured compiler diagnostics"
     (define source "half4 main(float2 p) { return missing_variable; }")
     (define result
       (with-handlers ([exn:fail:skia-sksl? values]) (make-runtime-effect source)))
     (check-true (exn:fail:skia-sksl? result))
     (check-equal? (exn:fail:skia-sksl-kind result) 'shader)
     (check-equal? (exn:fail:skia-sksl-source result) source)
     (check-true (positive? (string-length (exn:fail:skia-sksl-diagnostics result)))))
   (test-case "compiler enforces the color-filter entry point"
     (check-exn exn:fail:skia-sksl?
                (lambda () (make-runtime-effect coordinate-sksl #:kind 'color-filter))))
   (test-case "reflection follows packed offsets including float3 and arrays"
     (with-skia ([e (make-runtime-effect reflection-sksl)])
       (define us (runtime-effect-uniforms e))
       (check-equal? (map runtime-uniform-name us) '("shift" "triple" "pairs" "basis" "channel" "tint"))
       (check-equal? (map runtime-uniform-offset us) '(0 4 16 24 40 44))
       (check-equal? (map runtime-uniform-type us) '(float float3 float float2x2 int float4))
       (check-equal? (map runtime-uniform-count us) '(1 1 2 1 1 1))
       (check-equal? (runtime-effect-uniform-byte-size e) 60)
       (check-true (runtime-uniform-array? (list-ref us 2)))
       (check-true (runtime-uniform-color? (list-ref us 5)))
       (check-true (runtime-uniform-half-precision? (list-ref us 5)))))
   (test-case "all reflected numeric types have the expected byte sizes"
     (with-skia ([e (make-runtime-effect
                     (string-append
                      "uniform float a; uniform float2 b; uniform float3 c; uniform float4 d;"
                      "uniform float2x2 e; uniform float3x3 f; uniform float4x4 g;"
                      "uniform int h; uniform int2 i; uniform int3 j; uniform int4 k;"
                      "half4 main(float2 p) { float v=a+b.x+c.x+d.x+e[0][0]+f[0][0]+g[0][0];"
                      "v+=float(h+i.x+j.x+k.x); return half4(fract(v),0,0,1); }"))])
       (check-equal? (map runtime-uniform-byte-size (runtime-effect-uniforms e))
                     '(4 8 12 16 16 36 64 4 8 12 16))))
   (test-case "detached reflection and packing survive effect closure"
     (define e (make-runtime-effect solid-sksl))
     (define fields (runtime-effect-uniforms e))
     (skia-close! e)
     (check-true (skia-closed? e))
     (check-equal? (runtime-uniform-name (car fields)) "color")
     (check-equal? (bytes-length (runtime-effect-uniform-bytes e (hash 'color '(1 0 0 1)))) 16)
     (check-equal? (runtime-effect-source e) solid-sksl)
     (skia-close! e))
   (test-case "uniform colors render as ordinary shaders"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [red (runtime-effect->shader e #:uniforms (hash 'color '(1 0 0 1)))]
                 [green (runtime-effect->shader e #:uniforms (hash "color" '#(0 1 0 1)))])
       (check-rgba-near (shader-pixel red) '(255 0 0 255))
       (check-rgba-near (shader-pixel green) '(0 255 0 255))))
   (test-case "premultiplied shader output preserves alpha"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [s (runtime-effect->shader e #:uniforms (hash 'color '(1 0.5 0 0.5)))])
       (check-rgba-near (shader-pixel s) '(255 128 0 128) 3)))
   (test-case "layout-color converts to the destination working space"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [sh (runtime-effect->shader e #:uniforms (hash 'color '(0.5 0.5 0.5 1)))]
                 [linear (make-linear-srgb-color-space)]
                 [s (make-surface 2 2 #:color-space linear)]
                 [p (make-paint #:shader sh)])
       (draw-paint (surface-canvas s) p)
       ;; sRGB 0.5 becomes roughly 0.214 in a linear working surface.
       (check-rgba-near (surface-pixel s 0 0) '(55 55 55 255) 3)))
   (test-case "new instances snapshot mutable caller uniform vectors"
     (define color (vector 1 0 0 1))
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [before (runtime-effect->shader e #:uniforms (hash 'color color))])
       (vector-set! color 0 0) (vector-set! color 1 1)
       (with-skia ([after (runtime-effect->shader e #:uniforms (hash 'color color))])
         (check-rgba-near (shader-pixel before) '(255 0 0 255))
         (check-rgba-near (shader-pixel after) '(0 255 0 255)))))
   (test-case "shader owns its program after effect close and collection"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [sh (runtime-effect->shader e #:uniforms (hash 'color '(0 0 1 1)))])
       (skia-close! e) (collect-garbage)
       (check-rgba-near (shader-pixel sh) '(0 0 255 255))))
   (test-case "factory rejects closed effects"
     (define e (make-runtime-effect coordinate-sksl))
     (skia-close! e)
     (check-exn exn:fail? (lambda () (runtime-effect->shader e))))
   (test-case "factory enforces the compiled stage"
     (with-skia ([e (make-runtime-effect coordinate-sksl)])
       (check-exn exn:fail:contract? (lambda () (runtime-effect->color-filter e)))
       (check-exn exn:fail:contract? (lambda () (runtime-effect->blender e)))))
   (test-case "uniform dictionaries reject missing unknown and duplicate names"
     (with-skia ([e (make-runtime-effect solid-sksl)])
       (check-exn exn:fail:contract? (lambda () (runtime-effect->shader e)))
       (check-exn exn:fail:contract?
                  (lambda () (runtime-effect->shader e #:uniforms (hash 'colour '(1 0 0 1)))))
       (check-exn exn:fail:contract?
                  (lambda () (runtime-effect->shader e #:uniforms
                              (hash 'color '(1 0 0 1) "color" '(0 1 0 1)))))))
   (test-case "float3x3 uniform uses column-major coefficients"
     (with-skia ([e (make-runtime-effect matrix-sksl)]
                 [sh (runtime-effect->shader e #:uniforms
                        (hash 'mapping '(1 0 0 0 1 0 10 20 1)))])
       (check-rgba-near (shader-pixel sh 0 0) '(27 52 0 255))))
   (test-case "local matrix affects coordinates, not the output geometry"
     (with-skia ([e (make-runtime-effect coordinate-sksl)]
                 [plain (runtime-effect->shader e)]
                 [shifted (runtime-effect->shader e #:local-matrix (matrix-translate 5 0))])
       (check-rgba-near (shader-pixel plain 10 5) '(134 70 0 255))
       (check-rgba-near (shader-pixel shifted 10 5) '(70 70 0 255))))
   (test-case "singular and mistyped local matrices reject"
     (with-skia ([e (make-runtime-effect coordinate-sksl)])
       (check-exn exn:fail:contract?
                  (lambda () (runtime-effect->shader e #:local-matrix (matrix-scale 0))))
       (check-exn exn:fail:contract?
                  (lambda () (runtime-effect->shader e #:local-matrix '(1 0 0 1 0 0))))))
   (test-case "child metadata is copied and names resolve to correct kinds"
     (with-skia ([e (make-runtime-effect mixed-child-sksl)])
       (check-equal? (map runtime-child-name (runtime-effect-children e)) '("image" "filter" "blend"))
       (check-equal? (map runtime-child-kind (runtime-effect-children e)) '(shader color-filter blender))
       (check-equal? (map runtime-child-index (runtime-effect-children e)) '(0 1 2))))
   (test-case "ordinary child shaders can be closed after parent creation"
     (with-skia ([e (make-runtime-effect pass-child-sksl)]
                 [child (make-color-shader 'red)]
                 [sh (runtime-effect->shader e #:children (hash 'child child))])
       (skia-close! child) (skia-close! e) (collect-garbage)
       (check-rgba-near (shader-pixel sh) '(255 0 0 255))))
   (test-case "image shaders remain valid children after image close"
     (with-skia ([im (rgba-bytes->image 1 1 (bytes 0 255 0 255))]
                 [child (make-image-shader im)]
                 [e (make-runtime-effect pass-child-sksl)]
                 [sh (runtime-effect->shader e #:children (hash 'child child))])
       (skia-close! im) (skia-close! child)
       (check-rgba-near (shader-pixel sh) '(0 255 0 255))))
   (test-case "nested runtime shader graphs retain all children"
     (with-skia ([inner-e (make-runtime-effect solid-sksl)]
                 [inner (runtime-effect->shader inner-e #:uniforms (hash 'color '(1 0 1 1)))]
                 [outer-e (make-runtime-effect pass-child-sksl)]
                 [outer (runtime-effect->shader outer-e #:children (hash 'child inner))])
       (skia-close! inner) (skia-close! inner-e) (skia-close! outer-e)
       (check-rgba-near (shader-pixel outer) '(255 0 255 255))))
   (test-case "missing extra null and mistyped children reject"
     (with-skia ([e (make-runtime-effect pass-child-sksl)] [p (make-paint)])
       (check-exn exn:fail:contract? (lambda () (runtime-effect->shader e)))
       (check-exn exn:fail:contract? (lambda () (runtime-effect->shader e #:children (hash 'child #f))))
       (check-exn exn:fail:contract? (lambda () (runtime-effect->shader e #:children (hash 'child p))))
       (check-exn exn:fail:contract? (lambda () (runtime-effect->shader e #:children (hash 'extra p))))))
   (test-case "already-closed children reject before native construction"
     (with-skia ([e (make-runtime-effect pass-child-sksl)] [child (make-color-shader 'blue)])
       (skia-close! child)
       (check-exn exn:fail? (lambda () (runtime-effect->shader e #:children (hash 'child child))))))
   (test-case "color-filter runtime compiles and changes pixels"
     (with-skia ([e (make-runtime-effect invert-sksl #:kind 'color-filter)]
                 [cf (runtime-effect->color-filter e)])
       (check-true (color-filter? cf))
       (check-rgba-near (filter-pixel cf) '(0 255 255 255))))
   (test-case "runtime color filters retain a color-filter child"
     (with-skia ([inner-e (make-runtime-effect invert-sksl #:kind 'color-filter)]
                 [inner (runtime-effect->color-filter inner-e)]
                 [outer-e (make-runtime-effect filter-child-sksl #:kind 'color-filter)]
                 [outer (runtime-effect->color-filter outer-e #:children (hash 'child inner))])
       (skia-close! inner-e) (skia-close! inner) (skia-close! outer-e)
       (check-rgba-near (filter-pixel outer) '(0 255 255 255))))
   (test-case "runtime color filters participate in existing composition"
     (with-skia ([e (make-runtime-effect invert-sksl #:kind 'color-filter)]
                 [cf (runtime-effect->color-filter e)]
                 [twice (make-compose-color-filter cf cf)])
       (check-rgba-near (filter-pixel twice) '(255 0 0 255))))
   (test-case "blender runtime receives source then destination"
     (with-skia ([e (make-runtime-effect mix-sksl #:kind 'blender)]
                 [src (runtime-effect->blender e #:uniforms (hash 'amount 0))]
                 [dst (runtime-effect->blender e #:uniforms (hash 'amount 1))]
                 [mid (runtime-effect->blender e #:uniforms (hash 'amount 0.5))])
       (check-rgba-near (blend-pixel src) '(255 0 0 255))
       (check-rgba-near (blend-pixel dst) '(0 0 255 255))
       (check-rgba-near (blend-pixel mid) '(128 0 128 255))))
   (test-case "blender resources use common cleanup and retain their program"
     (with-skia ([e (make-runtime-effect mix-sksl #:kind 'blender)]
                 [b (runtime-effect->blender e #:uniforms (hash 'amount 0.5))])
       (check-true (blender? b)) (check-true (skia-resource? b))
       (skia-close! e)
       (check-rgba-near (blend-pixel b) '(128 0 128 255))))
   (test-case "shader accepts shader color-filter and blender children together"
     (with-skia ([s (make-color-shader 'red)]
                 [ce (make-runtime-effect invert-sksl #:kind 'color-filter)]
                 [cf (runtime-effect->color-filter ce)]
                 [b (make-blend-mode-blender 'src)]
                 [e (make-runtime-effect mixed-child-sksl)]
                 [sh (runtime-effect->shader e #:children (hash 'image s 'filter cf 'blend b))])
       (skia-close! s) (skia-close! cf) (skia-close! ce) (skia-close! b) (skia-close! e)
       (check-rgba-near (shader-pixel sh) '(0 255 255 255))))
   (test-case "paint retains blender and getter returns an independent reference"
     (with-skia ([e (make-runtime-effect mix-sksl #:kind 'blender)]
                 [b (runtime-effect->blender e #:uniforms (hash 'amount 0.5))]
                 [p (make-paint)])
       (paint-set-blender! p b)
       (with-skia ([copy (paint-blender p)])
         (skia-close! b) (skia-close! p) (skia-close! e)
         (check-rgba-near (blend-pixel copy) '(128 0 128 255)))))
   (test-case "changing blend mode replaces the runtime blender"
     (with-skia ([e (make-runtime-effect mix-sksl #:kind 'blender)]
                 [b (runtime-effect->blender e #:uniforms (hash 'amount 1))]
                 [p (make-paint #:color 'red)]
                 [s (make-surface 2 2 #:background 'blue)])
       (paint-set-blender! p b)
       (paint-set-blend-mode! p 'src)
       (draw-paint (surface-canvas s) p)
       (check-rgba-near (surface-pixel s 0 0) '(255 0 0 255))))
   (test-case "false blender resets paint to source-over"
     (with-skia ([b (make-blend-mode-blender 'dst)]
                 [p (make-paint #:color 'red)]
                 [s (make-surface 2 2 #:background 'blue)])
       (paint-set-blender! p b)
       (paint-set-blender! p #f)
       (draw-paint (surface-canvas s) p)
       (check-rgba-near (surface-pixel s 0 0) '(255 0 0 255))))
   (test-case "paint copy retains the runtime shader after all inputs close"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [sh (runtime-effect->shader e #:uniforms (hash 'color '(0 1 1 1)))]
                 [p (make-paint #:shader sh)] [copy (paint-copy p)]
                 [s (make-surface 2 2)])
       (skia-close! p) (skia-close! sh) (skia-close! e)
       (draw-paint (surface-canvas s) copy)
       (check-rgba-near (surface-pixel s 0 0) '(0 255 255 255))))
   (test-case "effect factory access is rejected across Racket threads"
     (with-skia ([e (make-runtime-effect coordinate-sksl)])
       (check-true (exn:fail? (in-other-thread (lambda () (runtime-effect->shader e)))))
       (check-equal? (in-other-thread (lambda () (runtime-effect-kind e))) 'shader)))
   (test-case "child and blender mutation reject cross-thread native access"
     (with-skia ([b (make-blend-mode-blender 'src)] [p (make-paint)])
       (check-true (exn:fail? (in-other-thread (lambda () (paint-set-blender! p b)))))
       (check-true (exn:fail? (in-other-thread (lambda () (skia-close! b)))))))
   (test-case "lowered uniform byte limit rejects instantiation"
     (with-skia ([e (make-runtime-effect solid-sksl)])
       (parameterize ([current-skia-byte-limit 15])
         (check-exn exn:fail? (lambda () (runtime-effect->shader e #:uniforms (hash 'color '(1 0 0 1))))))))
   (test-case "recorded runtime drawing owns shader inputs"
     (with-skia ([e (make-runtime-effect solid-sksl)]
                 [sh (runtime-effect->shader e #:uniforms (hash 'color '(0 1 0 1)))]
                 [pic (call-with-picture 8 8
                        (lambda (c) (with-skia ([p (make-paint #:shader sh)]) (draw-paint c p))))]
                 [s (make-surface 8 8)])
       (skia-close! sh) (skia-close! e)
       (draw-picture (surface-canvas s) pic)
       (check-rgba-near (surface-pixel s 4 4) '(0 255 0 255))))
   (test-case "explicit raster fallback produces an SVG image"
     (with-skia ([e (make-runtime-effect coordinate-sksl)] [sh (runtime-effect->shader e)])
       (define bs
         (call-with-svg-bytes 30 30
           (lambda (c)
             (draw-rasterized c 0 0 20 20
               (lambda (rc) (with-skia ([p (make-paint #:shader sh)]) (draw-paint rc p)))))))
       (check-true (regexp-match? #rx#"data:image/png;base64," bs))
       (check-true (regexp-match? #rx#"<image" bs))))
   (test-case "explicit raster fallback produces PDF without shader serialization"
     (with-skia ([e (make-runtime-effect coordinate-sksl)] [sh (runtime-effect->shader e)])
       (define bs
         (call-with-pdf-bytes
          (lambda (d)
            (with-document-page (c d 30 30)
              (draw-rasterized c 0 0 20 20
                (lambda (rc) (with-skia ([p (make-paint #:shader sh)]) (draw-paint rc p))))))))
       (check-true (regexp-match? #rx#"^%PDF-" bs))
       (check-true (regexp-match? #rx#"/Subtype /Image" bs))))))
(module+ test (run-tests runtime-native-tests))
