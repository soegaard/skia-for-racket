#lang racket/base
(provide solid-sksl coordinate-sksl reflection-sksl matrix-sksl
         pass-child-sksl filter-child-sksl mixed-child-sksl invert-sksl mix-sksl)
(define solid-sksl
  (string-append "layout(color) uniform half4 color;\n"
                 "half4 main(float2 p) { return half4(color.rgb * color.a, color.a); }\n"))
(define coordinate-sksl
  "half4 main(float2 p) { return half4(p.x / 20.0, p.y / 20.0, 0.0, 1.0); }")
(define reflection-sksl
  (string-append
   "uniform float shift; uniform float3 triple; uniform float pairs[2];\n"
   "uniform float2x2 basis; uniform int channel; layout(color) uniform half4 tint;\n"
   "half4 main(float2 p) {\n"
   "float v = shift + triple.x + triple.y + triple.z + pairs[0] + pairs[1];\n"
   "float2 q = basis * p; v += q.x + q.y + float(channel);\n"
   "return half4(tint.rgb * tint.a * fract(abs(v)), tint.a); }\n"))
(define matrix-sksl
  (string-append "uniform float3x3 mapping;\n"
                 "half4 main(float2 p) { float3 q = mapping * float3(p, 1);\n"
                 "return half4(q.x / 100.0, q.y / 100.0, 0, 1); }\n"))
(define pass-child-sksl "uniform shader child; half4 main(float2 p) { return child.eval(p); }")
(define filter-child-sksl
  "uniform colorFilter child; half4 main(half4 c) { return child.eval(c); }")
(define mixed-child-sksl
  (string-append "uniform shader image; uniform colorFilter filter; uniform blender blend;\n"
                 "half4 main(float2 p) { return blend.eval(filter.eval(image.eval(p)), half4(0,0,1,1)); }"))
(define invert-sksl "half4 main(half4 c) { return half4(c.a - c.rgb, c.a); }")
(define mix-sksl "uniform float amount; half4 main(half4 s, half4 d) { return mix(s, d, amount); }")
