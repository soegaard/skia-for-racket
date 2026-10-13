#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/color4f skia/float-colors))
@(define float-color-eval (make-base-eval))
@(float-color-eval '(require skia/color4f skia/color))

@title[#:tag "skia-float-colors"]{Floating-Point Colors}

@defmodule[skia/color4f #:no-declare]
@(declare-exporting skia skia/color4f #:use-sources (skia/color4f))

A @deftech{floating-point color} is a detached immutable value with red, green,
blue, and alpha components. Its RGB values are unpremultiplied: they are not
multiplied by alpha and need not lie between zero and alpha. RGB may be negative
or greater than one. A value does not carry a color space, choose a pixel
format, or enable HDR output merely by containing extended components.

Floating-point colors are distinct from the byte-valued @tech{color specification}s
accepted by @racket[color?]. Operations whose names end in @tt{color4f} or
contain @tt{color4f-shader} use this representation. Numerical conversion between
representations is separate from @secref["skia-color-management"].

@section{Construction and Conversion}

@defproc[(color4f? [v any/c]) boolean?]{
Returns @racket[#t] for a floating-point color and @racket[#f] otherwise. A raw
four-element vector and an RGBA byte color are not floating-point color values.
This predicate and the other operations exported by @racketmodname[skia/color4f]
do not load native Skia.
}

@defproc[(make-color4f [red real?] [green real?] [blue real?]
                      [alpha real? 1]) color4f?]{
Returns a color with the supplied unpremultiplied components. RGB inputs must
be finite and lie between minus and plus
@math{(2 - 2^(-23)) 2^127}, the largest finite IEEE binary32 magnitude.
After conversion to an inexact Racket number, alpha
must lie between zero and one, inclusive. Negative and extended RGB values
are retained, not clipped.

The constructor converts components to inexact Racket numbers but does not
round the stored RGB to binary32. Native drawing operations perform that
conversion later. Construction changes neither color space nor alpha convention.
The result is detached and must not be passed to @racket[skia-close!].

@examples[#:eval float-color-eval
(define extended (make-color4f 1.25 -0.25 0.5 0.5))
(eval:check (color4f->vector extended) (vector-immutable 1.25 -0.25 0.5 0.5))
(eval:check (color? extended) #f)
]
}

@defproc[(color4f-red [color color4f?]) real?]{
Returns the stored, unpremultiplied red component as an inexact number.
}
@defproc[(color4f-green [color color4f?]) real?]{
Returns the stored, unpremultiplied green component as an inexact number.
}
@defproc[(color4f-blue [color color4f?]) real?]{
Returns the stored, unpremultiplied blue component as an inexact number.
}
@defproc[(color4f-alpha [color color4f?]) (real-in 0 1)]{
Returns the stored inexact alpha. Zero is transparent and one is opaque.
}

@defproc[(color4f->vector [color color4f?])
         (and/c (vector/c real? real? real? real?) immutable?)]{
Returns an immutable vector in red, green, blue, alpha order. The operation does
not round the components to native floats, premultiply them, or attach a color space.
}

@defproc[(color->color4f [color color?]) color4f?]{
Returns a floating-point color obtained by dividing each RGBA byte component
by 255. This normalizes the numerical range; it does not decode the sRGB
transfer function or otherwise convert between color spaces.

@examples[#:eval float-color-eval
(eval:check (color4f->vector (color->color4f 'red))
            (vector-immutable 1.0 0.0 0.0 1.0))
(eval:check (color4f->rgba (color->color4f (rgba 50 109 230 128)))
            (rgba 50 109 230 128))
]
}

@defproc[(color4f->rgba [color color4f?]
                       [#:out-of-range policy (or/c 'error 'clip) 'error]) rgba?]{
Returns a byte-valued RGBA color. The default policy raises an exception when
an RGB component lies outside zero through one. The @racket['clip] policy
explicitly clamps extended components to that interval. Each component is
quantized with @math{floor(255 v + 0.5)} after clamping; alpha is quantized in
the same way. RGB remains unpremultiplied. This is not a color-space conversion,
gamut-mapping strategy, or tone mapper.

@examples[#:eval float-color-eval
(eval:check (color4f->rgba (make-color4f 1.2 -0.1 0.5 0.25) #:out-of-range 'clip)
            (rgba 255 0 128 64))
]
}

@close-eval[float-color-eval]

@section[#:tag "skia-float-drawing"]{Floating-Point Paints and Canvas Colors}

@defmodule[skia/float-colors #:no-declare]
@(declare-exporting skia skia/float-colors #:use-sources (skia/float-colors))

The constructors with a required @racket[#:color-space] keyword accept
@racket['srgb], @racket['linear-srgb], or complete ICC bytes. They reject both
@racket[#f] and a live color-space resource. Mutable ICC bytes are accepted by
copying them. A valid-looking header is not sufficient: native interpretation
must also succeed. See @secref["skia-color-space-descriptors"].

These operations convert color components to binary32 at the native boundary.
The target's color space and storage determine further conversion, clipping,
and quantization. Drawing a floating-point color into an eight-bit surface
does not turn that surface into floating-point storage. Native resources must
be open and used according to their thread and GPU-context lifetime rules.

@defproc[(make-paint/color4f [color color4f?]
                            [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
                            [#:style style (or/c 'fill 'stroke 'stroke-and-fill) 'fill]
                            [#:stroke-width width (and/c real? (>=/c 0)) 1]
                            [#:antialias? antialias? boolean? #t]) paint?]{
Returns an owned mutable paint with the specified color, its source
interpretation, and the displayed drawing settings. Stroke width must also be
a drawing scalar. Other settings use @racket[make-paint]'s defaults; this
constructor does not accept its complete keyword set. Set additional settings
through the documented paint mutators.

The native paint stores the converted color in extended sRGB, not the supplied
source space. It does not retain the caller's ICC byte string. On failure after
paint allocation, the new paint is released before the exception is raised.

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [surface (make-surface 1 1 #:color-space srgb)]
            [paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                      #:color-space 'linear-srgb)])
  (draw-paint (surface-canvas surface) paint)
  (surface-pixel surface 0 0))
]

The RGB bytes are approximately 188, not 128: the supplied components describe
linear light, while the destination stores sRGB-encoded bytes. Alpha is 255.
}

@defproc[(paint-color4f [paint paint?]) color4f?]{
Returns the paint's stored unpremultiplied extended-sRGB color as a detached
value. This is not the original color in the setter's source space, and it
does not sample the paint's shader or apply its filters. Unlike
@racket[paint-color], this query does not quantize the result to RGBA bytes.
}

@defproc[(paint-set-color4f! [paint paint?] [color color4f?]
                            [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]) void?]{
Sets the paint's color after interpreting it in the explicitly supplied source
space. The stored result is extended sRGB. Other paint settings, including an
attached shader, remain in place. With a shader attached, changing the color
still changes the alpha used to modulate that shader; it does not replace the
shader with a solid color.
}

@defproc[(canvas-clear-color4f! [canvas canvas?] [color color4f?]) void?]{
Fills the current clip with the supplied unpremultiplied color using source
replacement. The source is interpreted as extended sRGB; there is no
@racket[#:color-space] argument. The current geometric transform does not move
the fill, but the existing clip restricts it. Paint settings are not consulted.
The operation changes pixels, not the canvas state or the surface's color-space tag.
}

@defproc[(draw-color4f [canvas canvas?] [color color4f?]
                      [#:blend-mode mode
                       (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                             'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                             'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                             'hard-light 'soft-light 'difference 'exclusion 'multiply
                             'hue 'saturation 'color 'luminosity) 'src-over]) void?]{
Fills the current clip with the extended-sRGB color, combined with the destination
using the selected @tech{blend mode}. The default is source-over rather than
source replacement. There is no paint argument or source-space descriptor;
use a floating-point paint for an explicitly different source interpretation.
The geometric transform does not change the filled region.
}

@section[#:tag "skia-float-shaders"]{Floating-Point Shaders and Gradients}

The shaders retain their colors and source interpretation independently of
caller-owned input arrays or ICC bytes. Their wrappers are owned resources.
Native construction failure raises an exception. The floating-point gradient
interface uses @racket[#:stops] rather than the byte-color interface's
@racket[#:positions], and its positions must increase strictly.

A color sequence contains at least two floating-point colors, in a list or
vector. Its count must fit a signed native integer, and its charged input
payload of 64 bytes per color must fit @racket[current-skia-byte-limit]. A
nonfalse stops list or vector must have the same length. Stops lie between
zero and one and must remain strictly increasing after binary32 conversion;
two distinct Racket numbers that round to the same stop are rejected. Omitted
stops are evenly distributed. This interface therefore does not accept equal
stops for abrupt color transitions.

Tile modes have the meanings described for the basic gradient shaders. An
optional @racket[#:matrix] is a local affine transform of the shader. The wrapper
does not require an invertible local matrix; native rejection can still raise
an exception, and a singular matrix has no promised useful sampling behavior.
The shared @racket[#:color-space] argument describes all supplied colors.

@defproc[(make-color4f-shader [color color4f?]
                             [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]) shader?]{
Returns an owned constant-color shader with the explicit source interpretation.
The color is not first reduced to a packed eight-bit value. Its native color
space is retained independently of the temporary resource used during construction.
}

@defproc[(make-linear-gradient-color4f-shader
          [start (or/c (list/c real? real?) (vector/c real? real?))]
          [end (or/c (list/c real? real?) (vector/c real? real?))]
          [colors (or/c (listof color4f?) (vectorof color4f?))]
          [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
          [#:stops stops (or/c #f (listof real?) (vectorof real?)) #f]
          [#:tile-mode tile-mode (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
          [#:matrix matrix (or/c matrix? #f) #f]) shader?]{
Returns a linear gradient from @racket[start] to @racket[end]. The endpoints
contain drawing scalars and must be distinct after native point conversion.
The color, stop, tile, and local-matrix rules are specified in
@secref["skia-float-shaders"].

@racketblock[
(with-skia ([shader
             (make-linear-gradient-color4f-shader
              '(0 0) '(64 0) (list (make-color4f 1 0 0) (make-color4f 0 0 1))
              #:color-space 'srgb #:stops '(0 1))]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 64 16)])
  (draw-paint (surface-canvas surface) paint)
  (save-png surface "float-gradient.png" #:exists 'replace))
]
}

@defproc[(make-radial-gradient-color4f-shader
          [center (or/c (list/c real? real?) (vector/c real? real?))]
          [radius (and/c real? (>/c 0))]
          [colors (or/c (listof color4f?) (vectorof color4f?))]
          [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
          [#:stops stops (or/c #f (listof real?) (vectorof real?)) #f]
          [#:tile-mode tile-mode (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
          [#:matrix matrix (or/c matrix? #f) #f]) shader?]{
Returns a radial gradient from @racket[center] outward to @racket[radius].
The center and positive radius must be drawing scalars. The shared gradient
rules are specified in @secref["skia-float-shaders"].
}

@defproc[(make-sweep-gradient-color4f-shader
          [center (or/c (list/c real? real?) (vector/c real? real?))]
          [colors (or/c (listof color4f?) (vectorof color4f?))]
          [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
          [#:start-angle start-angle real? 0] [#:end-angle end-angle real? 360]
          [#:stops stops (or/c #f (listof real?) (vectorof real?)) #f]
          [#:tile-mode tile-mode (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
          [#:matrix matrix (or/c matrix? #f) #f]) shader?]{
Returns an angular gradient around @racket[center]. Angles are in degrees;
the end angle must exceed the start angle. Positive angles follow clockwise
rotation in downward-positive drawing coordinates. The center and angles must
be drawing scalars. Stops, tiling, and the local matrix follow
@secref["skia-float-shaders"].
}

@defproc[(make-two-point-conical-gradient-color4f-shader
          [start (or/c (list/c real? real?) (vector/c real? real?))]
          [start-radius (and/c real? (>=/c 0))]
          [end (or/c (list/c real? real?) (vector/c real? real?))]
          [end-radius (and/c real? (>=/c 0))]
          [colors (or/c (listof color4f?) (vectorof color4f?))]
          [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
          [#:stops stops (or/c #f (listof real?) (vectorof real?)) #f]
          [#:tile-mode tile-mode (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
          [#:matrix matrix (or/c matrix? #f) #f]) shader?]{
Returns a gradient between circles with the given centers and nonnegative
radii. Centers and radii must be drawing scalars; the native circles must differ.
The constructor can reject a configuration that the native backend cannot
represent. The remaining rules follow @secref["skia-float-shaders"].
}
