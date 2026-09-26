# Runtime effects / SkSL

Import `(require skia)` or `(require skia/runtime-effects)`. The latter module
exports the runtime API only; ordinary canvas, paint, matrix, and resource helpers
come from `skia`. From a checkout, require `"main.rkt"`.

A runtime effect is a compiled SkSL program. Creating an instance binds a snapshot
of its uniform values and children and produces an ordinary `shader?`,
`color-filter?`, or `blender?`. Compilation is separate from instantiation: reuse
a compiled effect instead of compiling once per frame or once per shape.

## A complete raster example

```racket
#lang racket/base
(require "main.rkt")

(define source
  (string-append
   "layout(color) uniform half4 color;\n"
   "half4 main(float2 p) {\n"
   "  return half4(color.rgb * color.a, color.a);\n"
   "}\n"))

(with-skia ([effect (make-runtime-effect source)]
            [shader (runtime-effect->shader effect
                      #:uniforms (hash 'color '(0.2 0.4 0.8 0.75)))]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 320 180 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 30 30 260 120 18 18 paint)
  (save-png surface "runtime-example.png" #:exists 'replace))
```

`layout(color)` inputs are **unpremultiplied, extended-range sRGB** values. Skia
converts them into the working color space. Shader return values are
**premultiplied**. The example therefore multiplies RGB by alpha exactly once.
Ordinary numeric uniforms are not color-converted. A child shader's `eval`
returns premultiplied colors already; do not multiply those colors by alpha again.

The coordinates passed to `main` are local shader coordinates. Canvas transforms
and a shader's local matrix affect them. Image shaders use pixel coordinates,
not normalized texture coordinates. A parent runtime shader can modify the
coordinates before calling `child.eval(p)`.

## Compilation and diagnostics

```racket
(make-runtime-effect source #:kind [kind 'shader])
(runtime-effect? value)
(runtime-effect-kind effect)
(runtime-effect-source effect)
```

The three kinds have these entry-point shapes:

| Kind | Entry point | Instance |
|---|---|---|
| `'shader` | `half4 main(float2 p)` | `shader?` |
| `'color-filter` | `half4 main(half4 inputColor)` | `color-filter?` |
| `'blender` | `half4 main(half4 source, half4 destination)` | `blender?` |

Skia also accepts equivalent `float4`/`vec4` color signatures where appropriate.
The pinned C factory uses default runtime-effect compiler options. This is SkSL
for the Skia pipeline, not an arbitrary GLSL program or an OpenGL context. The
wrapper does not enable private SkSL features or change the compiler's default
language-version restrictions.

`source` is a nonempty, NUL-free string. Its immutable snapshot and UTF-8 bytes
are checked against `current-skia-byte-limit`. Invalid SkSL raises
`exn:fail:skia-sksl?`, with these accessors:

```racket
(exn:fail:skia-sksl-kind exception)
(exn:fail:skia-sksl-source exception)
(exn:fail:skia-sksl-diagnostics exception)
```

Diagnostics preserve Skia's text, including any source locations it reports;
the wrapper does not invent a separate diagnostic parser. Incorrect Racket
arguments raise ordinary contract exceptions. Unsupported or failed native
instance creation raises an ordinary native-allocation error.

## Reflected uniforms

```racket
(runtime-effect-uniform-byte-size effect)
(runtime-effect-uniforms effect)        ; immutable list of runtime-uniform? values
(runtime-effect-uniform-bytes effect bindings)

(runtime-uniform? value)
(runtime-uniform-name uniform)         ; immutable string
(runtime-uniform-offset uniform)       ; byte offset
(runtime-uniform-type uniform)
(runtime-uniform-count uniform)        ; 1 for a non-array
(runtime-uniform-byte-size uniform)
(runtime-uniform-array? uniform)
(runtime-uniform-color? uniform)
(runtime-uniform-half-precision? uniform)
```

Reflection is copied when compilation succeeds. The names and metadata contain
no foreign pointers. Reflection and `runtime-effect-uniform-bytes` remain usable
after closing the effect, including from another Racket thread. Native instance
creation still requires the live effect on its creating thread.

`bindings` is a hash with string or symbol keys. Every reflected uniform must be
supplied. Missing names, unknown names, and duplicate normalized spellings such
as `'color` and `"color"` raise; there are no implicit zero-filled uniforms.

| Reflected type | Accepted value | Stored bytes per element |
|---|---|---:|
| `'float` | One finite real representable as a C float | 4 |
| `'float2`, `'float3`, `'float4` | Flat list/vector of 2, 3, or 4 such reals | 8, 12, 16 |
| `'float2x2`, `'float3x3`, `'float4x4` | Flat list/vector of 4, 9, or 16 reals, **column-major** | 16, 36, 64 |
| `'int` | One exact signed 32-bit integer | 4 |
| `'int2`, `'int3`, `'int4` | Flat list/vector of exact signed 32-bit integers | 8, 12, 16 |

An array uses one flat list/vector containing `count * components` values.
Even a scalar array of length one needs a one-element sequence. Nested arrays
or row lists are not accepted. A geometry `matrix?` is not a uniform value:
provide the column-major numbers explicitly. For example, an affine 3x3 uniform
that translates x by 10 and y by 20 is:

```racket
(hash 'mapping '(1 0 0  0 1 0  10 20 1))
```

The m119 layout is tightly packed four-byte components, **not std140**. A
`float3` takes 12 bytes and an array of two `float3` values takes 24 bytes.
SkSL `half` uniforms still occupy 32-bit float storage; their precision flag is
retained in metadata. Packing uses reflected offsets and host endianness.

`runtime-effect-uniform-bytes` returns independent immutable bytes for inspection
or diagnostics. Factories accept the checked hash, not arbitrary packed bytes.
The wrapper validates metadata sizes, offsets, flags, and child indices before
using them. A lowered byte limit is checked again when packing an instance.

## Instances and children

```racket
(runtime-effect->shader effect
  #:uniforms [bindings (hash)] #:children [children (hash)]
  #:local-matrix [matrix #f])
(runtime-effect->color-filter effect
  #:uniforms [bindings (hash)] #:children [children (hash)])
(runtime-effect->blender effect
  #:uniforms [bindings (hash)] #:children [children (hash)])

(runtime-effect-children effect)
(runtime-child? value)
(runtime-child-name child)
(runtime-child-kind child)             ; 'shader, 'color-filter, or 'blender
(runtime-child-index child)
```

Each factory enforces the kind selected at compilation. Uniform values are
copied into native `SkData`. Mutating the input vectors or hashes afterward
does not change an existing instance. To animate a uniform, make a new instance
from the same effect using the new value; no hidden clock is installed.

The shader's optional local matrix is an affine `matrix?` with a representable
inverse. It changes shader sampling coordinates, not the painted geometry.
Singular matrices and incorrectly typed values are rejected before the native
shader constructor. The geometry M33 layout is distinct from SkSL's column-major
matrix-uniform data.

Children are supplied as a separate hash, keyed by reflected names:

```racket
(with-skia ([effect
             (make-runtime-effect
              "uniform shader child; half4 main(float2 p) { return child.eval(p); }")]
            [gradient (make-linear-gradient-shader 0 0 200 0 '(blue cyan))]
            [shader (runtime-effect->shader effect
                      #:children (hash 'child gradient))])
  ;; shader retains the native effect and gradient.
  (skia-close! effect)
  (skia-close! gradient)
  (with-skia ([paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 200 80 paint)))
```

Every child slot is required and must match its reflected kind. This layer
rejects `#f` children rather than silently selecting Skia's null-child fallback.
Ordinary gradient/image shaders, runtime shaders, color filters, and blenders
can be children. Child arrays never escape the synchronous C call; the native
instance retains the references it needs. Closing the effect, input child
wrappers, or original image after construction does not invalidate the instance.

## Paint blenders

```racket
(blender? value)
(make-blend-mode-blender blend-mode)
(paint-set-blender! paint blender-or-false)
(paint-blender paint)
```

`make-blend-mode-blender` accepts the existing blend-mode names and produces an
owned native blender. `paint-set-blender!` retains its argument. Passing `#f`
restores Skia's default source-over behavior. `paint-blender` returns a separate
owned reference, or `#f` for the implicit default. Close a returned reference.

`paint-set-blend-mode!` and `paint-set-blender!` both set the paint's compositing
operation; the most recent setter wins. Paint copying retains the current
native blender. There is no new `#:blender` argument to `make-paint` in this
revision: use the explicit setter.

All effects and blenders work with `skia-resource?`, `skia-closed?`, `skia-close!`,
and `with-skia`. Native operations retain the library's creating-thread rule.
GC cleanup is a fallback, not a promise of immediate native-heap reclamation.

## PDF and SVG

**Use `draw-rasterized` for generic runtime effects in vector documents.** This
revision does not translate SkSL into SVG filters, shader source, or PDF objects,
and does not promise automatic native fallback for custom paint blenders.
Surrounding ordinary text, geometry, and annotations can remain vector.

```racket
(draw-rasterized canvas 20 50 240 100
  (lambda (raster-canvas)
    (with-skia ([paint (make-paint #:shader runtime-shader)])
      (draw-paint raster-canvas paint)))
  #:scale 2)
```

This is one bounded 480x200 image, not a rasterized page. For a custom blender
that needs underlying artwork, draw that backdrop **inside the same group**.
The temporary surface starts transparent; the blender cannot sample arbitrary
pixels already painted on the outer PDF/SVG canvas. Annotations authored inside
the raster group are discarded; place document links on the outer canvas.

Pictures retain runtime paint objects, but recording alone does not make those
objects vector-serializable. Rasterize their replay when exporting to vector
backends. The combined example explicitly rasterizes its twelve runtime panels
on both PDF and SVG and keeps labels/checkerboards vector.

## Limits and validation

Treat SkSL source as trusted application code. These wrappers are not a sandbox
and provide no compilation or per-pixel execution timeout. The byte limit bounds
source/metadata/uniform buffers, not total compiler memory, program complexity,
or the complete native heap. Finite uniform inputs do not guarantee finite,
properly premultiplied output from an arbitrary program; the program author is
responsible for its output.

No GPU context, runtime-effect serialization/cache, mutable native uniform
builder, shader debugger, or universal backend-capability analyzer is added.
The CPU feature set is the pinned Skia runtime compiler and raster implementation.
See [testing](RUNTIME-TESTING.md) and [ABI details](RUNTIME-ABI.md).

### Primary implementation sources

The binding is checked against mono/skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`, specifically:
`include/c/sk_runtimeeffect.h`, `src/c/sk_runtimeeffect.cpp`,
`include/c/sk_types.h`, `include/effects/SkRuntimeEffect.h`,
`src/core/SkRuntimeEffect.cpp`, `src/core/SkBlendModeBlender.cpp`, and
`src/c/sk_paint.cpp`. The upstream conceptual guide is **SkSL & Runtime Effects**
on the Skia documentation site. The pinned source determines the ABI and packing;
newer documentation must not override it.
