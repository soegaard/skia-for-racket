#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract skia skia/color4f skia/float-colors))
@(define float-color-eval (make-base-eval))
@(float-color-eval '(require skia/color4f skia/color))

@title[#:tag "skia-float-colors"]{Floating-Point Colors}

@defmodule[skia/color4f #:no-declare]
@(declare-exporting skia skia/color4f #:use-sources (skia/color4f))

Floating-point colors are useful for color-managed or higher-precision drawing.
Use them when you need to:

@itemlist[
 @item{specify a color in a particular source color space, such as linear sRGB;}
 @item{preserve fractional or extended RGB values instead of immediately
       reducing them to eight-bit channels; or}
 @item{create color-managed paints with @racket[make-paint/color4f] or
       @seclink["skia-float-shaders"]{floating-point gradients}.}]

The source space matters. An opaque gray with RGB components of 0.5 in linear
sRGB becomes approximately 188 per channel when drawn to an eight-bit sRGB
surface. The same components interpreted as sRGB become 128.

For ordinary UI drawing, the byte-valued @tech{color specification}s, such as
@racket['red] or @racket["#326DE6"], are usually simpler. Floating-point colors
do not themselves enable HDR output or make an eight-bit target higher
precision; the target surface's format still determines the stored precision.

A @deftech{floating-point color} is an immutable Racket structure with red, green,
blue, and alpha components. It uses @tech{unpremultiplied alpha}: RGB values are not
multiplied by alpha and need not lie between zero and alpha. RGB may be negative
or greater than one. A value does not carry a color space or choose a pixel
format.

Floating-point colors are distinct from the byte-valued @tech{color specification}s
accepted by @racket[color?]. Operations whose names end in @tt{color4f} or
contain @tt{color4f-shader} use this representation. Numerical conversion between
representations is separate from @secref["skia-color-management"].

@local-table-of-contents[#:style 'immediate-only]

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

The target's color space and storage determine color conversion, clipping,
and quantization. Native resources must
be open and used according to their thread and GPU-context lifetime rules.

@defproc[(make-paint/color4f [color color4f?]
                            [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]
                            [#:style style (or/c 'fill 'stroke 'stroke-and-fill) 'fill]
                            [#:stroke-width width (and/c real? (>=/c 0)) 1]
                            [#:antialias? antialias? boolean? #t]) paint?]{
Creates a paint using @racket[color], interpreted in the color space given by
@racket[space].

The paint is mutable and is an owned resource. The supplied style, stroke width,
and antialiasing settings control its drawing behavior. Other settings use
@racket[make-paint]'s defaults; this constructor does not accept its complete
keyword set. Set additional settings through the documented paint mutators.

The native paint stores the converted color in extended sRGB, not the supplied
source space. It does not store a reference to the caller's ICC byte string.
On failure after paint allocation, the new paint is released before the exception is raised.

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [surface (make-surface 1 1 #:color-space srgb)]
            [paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                      #:color-space 'linear-srgb)])
  (draw-paint (surface-canvas surface) paint)
  (surface-pixel surface 0 0))
]

The pixel has RGB bytes of approximately 188 and alpha 255.


@racketblock[
(with-skia ([surface (make-surface 210 80 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([srgb-paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                               #:color-space 'srgb)]
              [linear-paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                                 #:color-space 'linear-srgb)])
    (draw-rect canvas 15 15 80 50 srgb-paint)
    (draw-rect canvas 115 15 80 50 linear-paint)))
]
@reference-figure["float-source-space-stage10.png"
                  "Two mid-gray rectangles compare the same numeric components interpreted as sRGB and linear sRGB."]
}

@defproc[(paint-color4f [paint paint?]) color4f?]{
Returns the paint's stored unpremultiplied extended-sRGB color as a
@tech{floating-point color}. This is not the original color in the setter's
source space, and it does not sample the paint's shader or apply its filters. Unlike
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

@(declare-exporting skia skia/float-colors #:use-sources (skia/float-colors))

The shaders copy their color data. Later changes to caller-supplied vectors or
ICC byte strings do not affect the shader's colors or source interpretation.
Their wrappers are owned resources.
Native construction failure raises an exception. The floating-point gradient
interface uses @racket[#:stops] rather than the byte-color interface's
@racket[#:positions], and its positions must increase strictly.

A color list or vector contains at least two @tech{floating-point colors}.
Its count must fit a signed native integer. The byte-limit check counts 64 bytes
per color, and the total must fit @racket[current-skia-byte-limit]. A
nonfalse stops list or vector must have the same length. @tech{Gradient stop} positions lie between
zero and one and must remain strictly increasing after binary32 conversion;
two distinct Racket numbers that round to the same stop are rejected. Omitted
stops are evenly distributed. This interface therefore does not accept equal
stops for abrupt color transitions.

@tech{Tile modes} have the meanings described for the basic gradient shaders. An
optional @racket[#:matrix] is a local affine transform of the shader. The wrapper
does not require an invertible local matrix; native rejection can still raise
an exception, and a singular matrix has no promised useful sampling behavior.
The shared @racket[#:color-space] argument describes all supplied colors.

@defproc[(make-color4f-shader [color color4f?]
                             [#:color-space space (or/c 'srgb 'linear-srgb bytes?)]) shader?]{
Returns an owned constant-color shader with the explicit source interpretation.
The color is not first reduced to a packed eight-bit value.
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
must be distinct after native point conversion.
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

@reference-figure["float-gradient.png"
                  "A horizontal floating-point gradient from red on the left to blue on the right."]
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
The radius must be positive. The shared gradient rules are specified in
@secref["skia-float-shaders"].


@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([shader
               (make-radial-gradient-color4f-shader
                '(90 50) 55
                (list (make-color4f 1 1 1) (make-color4f 0.2 0.43 0.9))
                #:color-space 'srgb)]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 180 100 paint)))
]
@reference-figure["float-radial-stage10.png"
                  "A floating-point radial gradient changes from white at the center to blue at the edge."]
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
rotation in downward-positive drawing coordinates. Stops, tiling, and the local
matrix follow @secref["skia-float-shaders"].


@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([shader
               (make-sweep-gradient-color4f-shader
                '(90 50)
                (list (make-color4f 1 0 0)
                      (make-color4f 0 1 0)
                      (make-color4f 0 0 1)
                      (make-color4f 1 0 0))
                #:color-space 'srgb)]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 180 100 paint)))
]
@reference-figure["float-sweep-stage10.png"
                  "A floating-point sweep gradient rotates through red, green, blue, and back to red."]
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
radii. The native circles must differ.
The constructor can reject a configuration that the native backend cannot
represent. The remaining rules follow @secref["skia-float-shaders"].


@racketblock[
(with-skia ([surface (make-surface 190 105 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([shader
               (make-two-point-conical-gradient-color4f-shader
                '(55 52) 5 '(135 52) 58
                (list (make-color4f 1 0.63 0.17) (make-color4f 0.2 0.43 0.9))
                #:color-space 'srgb)]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 190 105 paint)))
]
@reference-figure["float-conical-stage10.png"
                  "A floating-point conical gradient grows from a small orange circle toward a larger blue circle."]
}
