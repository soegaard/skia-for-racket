#lang racket/base

;;;
;;; Runtime Fixtures
;;;

;; Provides shared inputs and drawing fixtures for SkSL runtime effects, uniform packing, and
;; retained child effects.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(provide solid-sksl coordinate-sksl reflection-sksl matrix-sksl
         pass-child-sksl filter-child-sksl mixed-child-sksl invert-sksl mix-sksl)

;;;
;;; Fixtures and Assertions
;;;

; solid-sksl : string?
;;   Declares a color uniform and explicitly premultiplies its RGB result by alpha.
(define solid-sksl
  (string-append "layout(color) uniform half4 color;\n"
                 "half4 main(float2 p) { return half4(color.rgb * color.a, color.a); }\n"))

; coordinate-sksl : string?
;;   Encodes local x/y coordinates in red/green channels for shader-transform checks.
(define coordinate-sksl
  "half4 main(float2 p) { return half4(p.x / 20.0, p.y / 20.0, 0.0, 1.0); }")

; reflection-sksl : string?
;;   Keeps scalar, vector, array, matrix, integer, and color uniforms live for reflection tests.
(define reflection-sksl
  (string-append
   "uniform float shift; uniform float3 triple; uniform float pairs[2];\n"
   "uniform float2x2 basis; uniform int channel; layout(color) uniform half4 tint;\n"
   "half4 main(float2 p) {\n"
   "float v = shift + triple.x + triple.y + triple.z + pairs[0] + pairs[1];\n"
   "float2 q = basis * p; v += q.x + q.y + float(channel);\n"
   "return half4(tint.rgb * tint.a * fract(abs(v)), tint.a); }\n"))

; matrix-sksl : string?
;;   Applies a 3-by-3 matrix to coordinates so uniform element ordering is visible in pixels.
(define matrix-sksl
  (string-append "uniform float3x3 mapping;\n"
                 "half4 main(float2 p) { float3 q = mapping * float3(p, 1);\n"
                 "return half4(q.x / 100.0, q.y / 100.0, 0, 1); }\n"))

; pass-child-sksl : string?
;;   Forwards sampling to a shader child to test retained child ownership.
(define pass-child-sksl "uniform shader child; half4 main(float2 p) { return child.eval(p); }")

; filter-child-sksl : string?
;;   Forwards a color through a color-filter child.
(define filter-child-sksl
  "uniform colorFilter child; half4 main(half4 c) { return child.eval(c); }")

; mixed-child-sksl : string?
;;   Combines shader, color-filter, and blender children in one retained effect graph.
(define mixed-child-sksl
  (string-append "uniform shader image; uniform colorFilter filter; uniform blender blend;\n"
    "half4 main(float2 p) { return blend.eval(filter.eval(image.eval(p)), half4(0,0,1,1)); }"))

; invert-sksl : string?
;;   Inverts premultiplied RGB within the original alpha for runtime-filter checks.
(define invert-sksl "half4 main(half4 c) { return half4(c.a - c.rgb, c.a); }")

; mix-sksl : string?
;;   Interpolates source and destination colors using a scalar blender uniform.
(define mix-sksl "uniform float amount; half4 main(half4 s, half4 d) { return mix(s, d, amount); }")
