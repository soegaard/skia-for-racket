#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/runtime-effects skia/effects))

@title[#:tag "skia-runtime-effects"]{Runtime Effects}

@(declare-exporting skia)

Use a runtime effect when the built-in gradients, filters, or blend modes
cannot express the drawing effect you need. Write the color calculation in
SkSL, compile it with @racket[make-runtime-effect], and create a shader, color
filter, or blender instance for use in drawing. Built-in effects are simpler
when they already provide the required behavior.

A @deftech{runtime effect} is a compiled SkSL program for one stage of drawing:
a @tech{shader}, @tech{color filter}, or @tech{blender}. Compilation produces an
effect resource; creating an instance binds its @tech{uniforms} and child
resources. For built-in blenders and attaching a blender to a paint, see
@secref["skia-paint-blenders"].

Runtime effects can be used by CPU drawing. Compiling one does not create a GPU
context. The available SkSL language is the one supported by the installed
compatible native library, not an arbitrary desktop GLSL implementation.
Native rejection raises an exception. Compilation diagnostics use exceptions
satisfying @racket[exn:fail:skia-sksl?].

@defmodule[skia/runtime-effects #:no-declare]
@(declare-exporting skia skia/runtime-effects #:use-sources (skia/runtime-effects))

@local-table-of-contents[#:style 'immediate-only]

@section{Compilation and Stage Selection}

@defproc[(runtime-effect? [v any/c]) boolean?]{
Returns @racket[#t] for a runtime-effect resource and @racket[#f] otherwise.
The predicate remains true after closure.
}

@defproc[(make-runtime-effect
          [source string?]
          [#:kind kind (or/c 'shader 'color-filter 'blender) 'shader]) runtime-effect?]{
Compiles @racket[source] as an SkSL program for the selected stage.

The result is an owned effect. The source string must be nonempty and contain
no NUL characters. Both the character count and UTF-8 byte count must
fit @racket[current-skia-byte-limit]. The source and reflection information
(the compiler's descriptions of uniforms and children) are copied; changing a
mutable source string afterward has no effect.

A shader entry point receives @tech{local coordinates}. A color-filter entry point
receives a color. A blender entry point receives source and destination colors,
in that order. The compiler checks that the entry point fits the chosen stage.
Compilation failure raises an exception satisfying @racket[exn:fail:skia-sksl?];
argument, allocation, or reflection failures need not use that exception type.

A shader returns premultiplied RGBA. Returning straight RGB with partial alpha
does not automatically premultiply it. Uniforms marked @tt{layout(color)} are
supplied as unpremultiplied sRGB values and converted to the working color
space; ordinary numeric uniforms are not implicitly color converted.

@racketblock[
(with-skia ([effect
             (make-runtime-effect
              "uniform float gain; half4 main(float2 p) { return half4(gain,0,0,1); }")]
            [shader (runtime-effect->shader effect #:uniforms (hash 'gain 0.5))]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 4 4)])
  (draw-paint (surface-canvas surface) paint)
  (surface-pixel surface 1 1))
]

Shader coordinates follow local canvas and shader transforms, not normalized
texture coordinates. The source defines a function within Skia's drawing
pipeline; it does not replace clipping, coverage, or the final paint blend.
}

@subsection[#:tag "skia-runtime-metadata"]{Inspecting Compiled Effects}

The following queries read the source and compiler descriptions stored when
the effect was compiled. They remain available after the effect is closed;
creating a new shader, color filter, or blender instance still requires an
open effect.

@defproc[(runtime-effect-kind [effect runtime-effect?]) (or/c 'shader 'color-filter 'blender)]{
Returns the stage for which the effect was compiled.
}

@defproc[(runtime-effect-source [effect runtime-effect?])
         (and/c string? immutable?)]{
Returns the stored immutable source string. This is the submitted program,
not generated backend code.
}

@defproc[(runtime-effect-uniform-byte-size [effect runtime-effect?]) exact-nonnegative-integer?]{
Returns the uniform buffer size reported by the compiler, in bytes. It is a multiple
of four and can be zero.
}

@defproc[(runtime-effect-uniforms [effect runtime-effect?]) (listof runtime-uniform?)]{
Returns the stored ordered list of uniform-description structures.
}

@defproc[(runtime-effect-children [effect runtime-effect?]) (listof runtime-child?)]{
Returns the stored ordered list of child-slot description structures. The
indices are contiguous from zero. This does not return the resources later
bound to an instance.
}

@section[#:tag "skia-runtime-bindings"]{Uniform and Child Bindings}

Reuse a compiled runtime effect with different parameters or input effects by
creating separate instances. Pass numeric values through @racket[#:uniforms]
and child resources through @racket[#:children] to @racket[runtime-effect->shader],
@racket[runtime-effect->color-filter], or @racket[runtime-effect->blender].

A @deftech{uniform} is a named numeric parameter supplied when a runtime effect
is instantiated. Its value is copied into the instance and stays fixed for
that instance. A child binding supplies a shader, color filter, or blender
resource for the program to use.

Bindings are supplied in hash tables with symbol or string keys. Keys must exactly
match the compiled effect's uniform or child names after symbols are converted to strings.
Missing names, unknown names, and duplicate names after converting symbol keys
to strings are rejected. For example, @racket['gain] and @racket["gain"] cannot
both appear as keys in one hash table.
Every uniform and child in the compiled effect must be supplied; there are no implicit
zero uniforms or null-child fallbacks. The default empty hash tables work only
when the effect has no corresponding uniforms or children.

A nonarray scalar uniform takes one number. Vectors, matrices, and all arrays
require a flat list or vector of exactly the component count reported by the compiler.
A scalar array of length one still requires a one-element list or vector.
Matrices use SkSL's column-major component order, with array elements consecutive. Floating
components are packed as single-precision values. Integer
components are exact signed 32-bit integers. Half-precision declarations still
occupy four bytes per supplied component; the flag describes shader arithmetic,
not a two-byte host buffer.

Instances keep their own native references to the compiled effect and child
resources. They copy the bound uniform values; mutating a hash table or input
vector afterward does not update an existing instance. Create another instance
to use new values. Caller-owned
wrappers are not transferred. Closing them after
successful construction does not invalidate the instance, but GPU-dependent
children preserve their context, thread, and lifetime restrictions.

@defproc[(runtime-effect-uniform-bytes [effect runtime-effect?] [bindings hash?])
         (and/c bytes? immutable?)]{
Packs the uniform values in @racket[bindings] into a byte string for @racket[effect].
Use this diagnostic utility to inspect how values occupy the compiler's
uniform layout. For drawing, pass the binding hash table directly to an
instance constructor instead.

The result is a new immutable byte string. Packing follows the stored uniform
layout and the rules in @secref["skia-runtime-bindings"]. It uses native byte
order and the offsets reported by the compiler, not std140 padding. Its length equals
@racket[(runtime-effect-uniform-byte-size effect)]. It is not a portable serialization
format and is not accepted in place of the binding hash table by instance factories.

This packing operation does not call the native library and works after the
effect is closed. It still validates the current byte limit and all bindings.

@racketblock[
(define effect
  (make-runtime-effect "uniform float amount; half4 main(float2 p) { return half4(amount); }"))
(skia-close! effect)
(define packed (runtime-effect-uniform-bytes effect (hash 'amount 0.5)))
(list (immutable? packed) (bytes-length packed))
]

}

@defproc[(runtime-effect->shader
          [effect runtime-effect?]
          [#:uniforms uniforms hash? (hash)]
          [#:children children hash? (hash)]
          [#:local-matrix local-matrix (or/c matrix? #f) #f]) shader?]{
Creates a shader from @racket[effect] using the supplied uniforms and children.

The shader is an owned resource. The effect must be open and compiled for the
shader stage. Every child must be an open shader, color filter, or blender of
the kind required by the compiled effect; false children are rejected.
The optional affine local matrix must have a
representable inverse. It affects local shader coordinates and is not a
replacement for the @tech{canvas transform}. Binding and resource rules follow
@secref["skia-runtime-bindings"].

@racketblock[
(with-skia ([effect
             (make-runtime-effect
              "half4 main(float2 p) { half t=half(0.5+0.5*sin(p.x*0.08)); return half4(t,0,1-t,1); }")]
            [shader (runtime-effect->shader effect)]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 180 60 #:background 'white)])
  (draw-paint (surface-canvas surface) paint))
]

@reference-figure["runtime-effect-bands.png"
                  "Procedural vertical bands alternating smoothly between blue and red, generated by a SkSL runtime shader."]
}

@defproc[(runtime-effect->color-filter
          [effect runtime-effect?]
          [#:uniforms uniforms hash? (hash)]
          [#:children children hash? (hash)]) color-filter?]{
Returns an owned color-filter instance. The effect must be open and compiled
for the color-filter stage. Uniforms, child types, complete binding hash tables,
and resource ownership follow @secref["skia-runtime-bindings"]. No local-matrix
option is accepted for this stage.
}

@defproc[(runtime-effect->blender
          [effect runtime-effect?]
          [#:uniforms uniforms hash? (hash)]
          [#:children children hash? (hash)]) blender?]{
Returns an owned blender instance. The effect must be open and compiled
for the blender stage. Uniforms, child types, complete binding hash tables,
and resource ownership follow @secref["skia-runtime-bindings"]. No local-matrix
option is accepted for this stage.
}

@section{One Program, Several Composition Sites}

The stage fixes the meaning of a program's inputs.  A color-filter program
receives one premultiplied color.  A blender program receives the incoming
@racket[src] color first and the already-present @racket[dst] color second.
The following self-contained example keeps every input opaque, so each output
is safely premultiplied.  For translucent inputs, a custom program must still
ensure that every RGB component is no greater than alpha.

@racketblock[
(define surface (make-surface 420 270 #:background 'white))
(with-skia ([font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
            [color-effect (make-runtime-effect
                           "half4 main(half4 c) { return half4(c.b,c.g*0.5,c.r,c.a); }"
                           #:kind 'color-filter)]
            [color-filter (runtime-effect->color-filter color-effect)]
            [orange (make-paint #:color "#E94F37")]
            [filtered-orange (make-paint #:color "#E94F37" #:color-filter color-filter)]
            [child-effect (make-runtime-effect
                           "uniform shader child; half4 main(float2 p) { half4 c=child.eval(p); return half4(c.b,c.g*0.4,c.r,c.a); }")]
            [child-gradient (make-linear-gradient-shader 220 0 400 0 '(red blue))]
            [child-shader (runtime-effect->shader child-effect
                                                  #:children (hash 'child child-gradient))]
            [child-paint (make-paint #:shader child-shader)]
            [blender-effect (make-runtime-effect
                             "half4 main(half4 src, half4 dst) { return half4(src.r,dst.g,dst.b,1); }"
                             #:kind 'blender)]
            [paint-blender (runtime-effect->blender blender-effect)]
            [shader-blender (runtime-effect->blender blender-effect)]
            [filter-blender (runtime-effect->blender blender-effect)]
            [destination (make-paint #:color "#1769E0")]
            [source (make-paint #:color "#E94F37")]
            [source-with-blender (make-paint #:color "#E94F37")]
            [destination-shader (make-color-shader "#1769E0")]
            [source-shader (make-color-shader "#E94F37")]
            [combined-shader (make-blender-shader shader-blender
                                                   destination-shader source-shader)]
            [shader-paint (make-paint #:shader combined-shader)]
            [destination-filter (make-shader-image-filter destination-shader
                                                           #:crop '(290 130 110 55))]
            [source-filter (make-shader-image-filter source-shader
                                                      #:crop '(290 130 110 55))]
            [combined-filter (make-blender-image-filter filter-blender
                                                         destination-filter source-filter
                                                         #:crop '(290 130 110 55))]
            [filter-paint (make-paint #:image-filter combined-filter)]
            [arithmetic (make-arithmetic-blender 0 0.25 0.75 0)]
            [arithmetic-source (make-paint #:color "#E94F37")])
  (define canvas (surface-canvas surface))
  (paint-set-blender! source-with-blender paint-blender)
  (paint-set-blender! arithmetic-source arithmetic)
  (draw-simple-text canvas "color filter: source" 18 17 font label)
  (draw-simple-text canvas "bound child shader" 220 17 font label)
  (draw-rounded-rect canvas 18 28 82 45 7 7 orange)
  (draw-rounded-rect canvas 112 28 82 45 7 7 filtered-orange)
  (draw-rect canvas 220 28 180 45 child-paint)
  (draw-simple-text canvas "source" 34 84 font label)
  (draw-simple-text canvas "filtered" 126 84 font label)
  (draw-simple-text canvas "child = red-to-blue gradient" 220 84 font label)
  (draw-simple-text canvas "paint: D then S" 18 118 font label)
  (draw-simple-text canvas "shader: D, S" 155 118 font label)
  (draw-simple-text canvas "filter: bg=D, fg=S" 290 118 font label)
  (draw-rounded-rect canvas 18 130 110 55 8 8 destination)
  (draw-circle canvas 78 158 24 source-with-blender)
  (draw-rect canvas 155 130 110 55 shader-paint)
  (draw-rect canvas 290 130 110 55 filter-paint)
  (for ([x '(18 155 290)]) (draw-rect canvas x 130 110 55 outline))
  (draw-simple-text canvas "D = azure, S = orange" 18 206 font label)
  (draw-simple-text canvas "same runtime blender" 155 206 font label)
  (draw-simple-text canvas "arithmetic: .25 S + .75 D" 18 238 font label)
  (draw-rounded-rect canvas 225 220 110 28 6 6 destination)
  (draw-rounded-rect canvas 250 220 60 28 6 6 arithmetic-source))
surface
]
@reference-figure["runtime-blender-consumers.png"
                  "Top row: an orange source and its blue-purple runtime color-filter result; a runtime shader recolors a bound red-to-blue gradient child. Bottom row: one runtime blender combines an azure destination and orange source through a paint, a blender shader, and a blender image filter. A final swatch uses the arithmetic .25 source plus .75 destination blender."]

The three bottom panels use separately owned instances of the same compiled
blender program.  @racket[paint-set-blender!] sees the destination already in
the canvas; @racket[make-blender-shader] takes destination before source even
though the program receives source first; and
@racket[make-blender-image-filter] names those inputs @racket[background]
(destination) and @racket[foreground] (source).  The small final swatch uses
@racket[make-arithmetic-blender] with the same ordering.

@section{Uniform Descriptions}

@defproc[(runtime-uniform? [v any/c]) boolean?]{
Returns @racket[#t] for a runtime-uniform description and @racket[#f] otherwise.
}

@defproc[(runtime-uniform-name [uniform runtime-uniform?]) string?]{
Returns the immutable, nonempty uniform name used as a key in binding hash tables.
}

@defproc[(runtime-uniform-offset [uniform runtime-uniform?]) exact-nonnegative-integer?]{
Returns the byte offset in the effect uniform buffer. The offset is a multiple of four.
}

@defproc[(runtime-uniform-type
          [uniform runtime-uniform?])
         (or/c 'float 'float2 'float3 'float4 'float2x2 'float3x3 'float4x4 'int 'int2 'int3 'int4)]{
Returns the uniform's numeric type as reported by the compiler. A half declaration
uses the corresponding floating type here; query its half-precision flag separately.
}

@defproc[(runtime-uniform-count [uniform runtime-uniform?]) exact-positive-integer?]{
Returns the array length, or one for a nonarray uniform. Use
@racket[runtime-uniform-array?] to distinguish a one-element array from a scalar.
}

@defproc[(runtime-uniform-byte-size [uniform runtime-uniform?]) exact-positive-integer?]{
Returns the complete byte size, including all array elements. Each numeric
component occupies four bytes, including components declared as half.
}

@defproc[(runtime-uniform-array? [uniform runtime-uniform?]) boolean?]{
Returns whether the declaration is an array. Even an array with one scalar
element requires a list or vector when bound.
}

@defproc[(runtime-uniform-color? [uniform runtime-uniform?]) boolean?]{
Returns whether the declaration has @tt{layout(color)}. Its supplied values
are unpremultiplied sRGB, unlike arbitrary numeric uniforms.
}

@defproc[(runtime-uniform-half-precision? [uniform runtime-uniform?]) boolean?]{
Returns whether the declaration carries the half-precision flag. Host
packing still uses four bytes per component.
}

@section{Child Descriptions}

@defproc[(runtime-child? [v any/c]) boolean?]{
Returns @racket[#t] for a runtime-child description and
@racket[#f] otherwise. It does not test an actual shader or filter instance.
}

@defproc[(runtime-child-name [child runtime-child?]) string?]{
Returns the immutable, nonempty child name used as a key in the child-binding hash table.
}

@defproc[(runtime-child-kind [child runtime-child?]) (or/c 'shader 'color-filter 'blender)]{
Returns the required resource kind. A binding of another kind is rejected,
even if it can otherwise participate in drawing.
}

@defproc[(runtime-child-index [child runtime-child?]) exact-nonnegative-integer?]{
Returns the child's zero-based slot index in the compiled effect. Callers bind by name rather
than passing a native pointer array.
}

@section{Compilation Errors}

@defproc[(exn:fail:skia-sksl? [v any/c]) boolean?]{
Returns @racket[#t] for an SkSL compilation exception and @racket[#f]
otherwise. These exceptions also satisfy @racket[exn:fail?].
}

@defproc[(exn:fail:skia-sksl-kind
          [exception exn:fail:skia-sksl?]) (or/c 'shader 'color-filter 'blender)]{
Returns the stage requested by the unsuccessful compilation.
}

@defproc[(exn:fail:skia-sksl-source [exception exn:fail:skia-sksl?]) string?]{
Returns the copied source string supplied to the compiler.
}

@defproc[(exn:fail:skia-sksl-diagnostics [exception exn:fail:skia-sksl?]) string?]{
Returns the immutable native compiler diagnostics. The exact wording and
reported line formatting can change with the native library version.
}
