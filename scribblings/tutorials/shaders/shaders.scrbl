#lang scribble/manual

@(require racket/file racket/runtime-path "eval.rkt" "waves.rkt"
          "../support/source.rkt" (for-label racket skia))
@(define-runtime-path program-source "waves.rkt")

@title{Runtime Shaders — Paint Contour Waves}

@section{The Finished Poster}

@(wave-poster-pict)

The curved bands in this poster are not paths or an imported image. A short
SkSL program calculates a color from each sampling position. Skia uses that
program as a shader attached to an ordinary paint.

@centered{@bold{Geometry decides where to draw. A runtime shader computes the paint's color.}}

This example uses a CPU surface. Writing a shader does not require an OpenGL
program or a GPU window. The complete @filepath{waves.rkt} file appears at the
end; save it locally to use the helpers in the following examples.

@section{Start with a Constant Color}

A runtime shader has an entry point that accepts a two-dimensional position and
returns a four-component color. Start with a program that ignores the position:

@codeblock[(source-definition program-source 'solid-source)]

The components are red, green, blue, and alpha. This example is opaque because
alpha is 1. Compile the source, create a shader, and attach it to a paint:

@shaders-racketblock+eval[
(require skia "waves.rkt")
(define solid-effect (make-runtime-effect solid-source))
(define solid-shader (runtime-effect->shader solid-effect))
(define solid-paint (make-paint #:shader solid-shader))
(define surface (make-surface 320 180))
(draw-rect (surface-canvas surface) 0 0 320 180 solid-paint)
]

@(shader-pict solid-source (hash))

The @racket[make-runtime-effect] function compiles source. The
@racket[runtime-effect->shader] function creates an instance of that compiled
program. The drawing is still an ordinary @racket[draw-rect] call; the shader
does not choose the rectangle's size.

@section{Turn Coordinates into Color}

The position passed to the shader is in local shader coordinates, not a
normalized texture space. Divide by the drawing's dimensions to get values
that approximately range from 0 to 1 across this rectangle:

@codeblock[(source-definition program-source 'coordinate-source)]

The @tt{extent} uniform supplies the width and height. A uniform is a parameter
shared by the shader's evaluations for this instance; it is not a mutable Racket
binding that Skia consults while drawing.

@shaders-racketblock+eval[
(define coordinate-effect (make-runtime-effect coordinate-source))
(define coordinate-shader
  (runtime-effect->shader coordinate-effect
                          #:uniforms (hash 'extent '(320 180))))
]

@(shader-pict coordinate-source (hash 'extent '(320 180)))

The red channel increases from left to right and the green channel increases
from top to bottom. The blue channel stays at 0.25. Pixel sampling positions
need not land exactly on the rectangle's mathematical edges, so the last pixel
need not contain exactly 1 in a varying channel.

The @tt{extent} uniform does not normalize coordinates automatically. The
@tt{p / extent} expression in the source performs that calculation.

@section{Make Repeating Bands}

For the poster, use a sine wave instead of a direct coordinate ramp. This
expression converts a scalar field into a value between 0 and 1:

@verbatim{
float wave = 0.5 + 0.5 * sin(6.2831853 * frequency * field);
}

The frequency controls the number of cycles per normalized coordinate unit.
The factor 6.2831853 is approximately two pi. The shader uses @tt{smoothstep} to
turn the wave into soft-edged bands and @tt{mix} to choose between two colors.

Here is the complete wave source. First consider it with @tt{bend} set to zero:

@codeblock[(source-definition program-source 'wave-source)]

@shaders-racketblock+eval[
(define effect (make-runtime-effect wave-source))
(define straight-shader (make-wave-shader effect 480 210 #:bend 0))
]

@(waves-pict #:bend 0)

The bands are straight because @tt{field} is just @tt{q.x} when the bend is zero.
Both coordinates are divided by the same length,
@tt{min(extent.x, extent.y)}, so a coordinate distance has the same scale in
both directions. The pattern does not stretch a circular construction into an
ellipse merely because the rectangle is wide.

@section{Bend the Bands}

Now add a sine displacement that depends on the vertical coordinate:

@verbatim{
float field = q.x + bend * sin(3.5 * q.y + phase);
}

The horizontal displacement varies smoothly from row to row. The same compiled
effect can produce all three examples below; only the bend uniform changes:

@(wave-variants)

The Racket helper supplies every uniform required by the source:

@codeblock[(source-definition program-source 'make-wave-shader)]

The bindings hash may use symbol or string names. Missing or unknown uniforms
are errors rather than silently chosen defaults. The defaults shown here belong
to our Racket helper, which constructs a complete hash before calling Skia.

@section{Change a Uniform, Not the Compiled Program}

The phase shifts the vertical displacement. Create another shader instance
from the existing effect:

@shaders-racketblock+eval[
(define shifted-shader (make-wave-shader effect 480 210 #:phase 1))
(shader? shifted-shader)
]

@(waves-pict #:phase 1)

An instance snapshots its uniform values. Mutating the original hash later does
not update it. For animation, reuse the compiled effect and create an instance
with the new phase for each frame; do not recompile the source for each frame.
There is no hidden clock in the shader. This tutorial uses fixed phases so each
example has a definite result.

@section{Return the Right Kind of Color}

The two palette uniforms have a @tt{layout(color)} annotation. Their inputs are
unpremultiplied sRGB colors expressed as floating-point components. Skia can
convert those inputs to the working color space. An ordinary numeric uniform,
such as @tt{phase}, is not color-converted.

The shader's return value must instead be premultiplied: its RGB components are
multiplied by its alpha. That is why the final line is:

@verbatim{
return half4(color.rgb * color.a, color.a);
}

The poster's colors have alpha 1, so this multiplication changes nothing there.
It becomes necessary when a palette color is translucent. A color obtained by
sampling a child shader would already be premultiplied; multiplying that result
again would be a different operation. Child shaders are outside this example.

@section{Place the Pattern in the Poster}

The pattern's local origin should be the panel's upper-left corner. Translate
the canvas before drawing the rounded rectangle, rather than using page
coordinates with a panel-sized extent:

@codeblock[(source-definition program-source 'draw-wave-panel)]

The shape clips the shader's contribution naturally: the program computes the
paint color, but it does not paint outside the rounded rectangle. The title and
caption are ordinary text drawn with separate paints.

@(wave-poster-pict)

The complete program compiles the effect once, calls @racket[draw-wave-poster],
and saves @filepath{contour-waves.png}. The same drawing function can receive a
GPU-backed canvas from the preceding tutorials. That changes the execution
backend, not the SkSL parameter model.

For PDF or SVG output, treat a general runtime shader as a bounded raster effect,
as in Tutorial 12. The exporter does not translate this SkSL program into
editable SVG paths or certify vector preservation.

@section{The Complete Program}

Run the file with @tt{racket waves.rkt}. No external image assets are needed.

@codeblock[(file->string program-source)]

@section{Try It}

Change the frequency from 5 to 3 while keeping the bend fixed. Then restore the
frequency and increase the bend. These edits change different features of the
pattern, so compare them separately.

Try a translucent light color over a white surface. Keep the final alpha
multiplication in place. Very high frequencies can alias; rendering the example
at a larger size is an experiment, not a substitute for proper shader filtering.

@section{Where to Go From Here}

A runtime effect is compiled application code, not a sandbox for untrusted shader
source. Compilation can fail, and a complicated shader can take substantial
work to execute. Skia exposes compiler diagnostics through
@racket[exn:fail:skia-sksl-diagnostics]. The Guide covers diagnostics, child
shaders, color filters, and blenders in detail.

The upstream @hyperlink["https://skia.org/docs/user/sksl/"]{SkSL and Runtime Effects}
guide explains how runtime effects fit into Skia's drawing pipeline.
