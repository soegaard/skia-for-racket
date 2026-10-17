#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-paints"]{Paints}

A @deftech{paint} supplies the appearance of a drawing operation. It holds values such
as a color and stroke width, and may retain @tech{shaders}, effects, or filters.
It does not contain the shape being drawn or the current @tech{canvas transform}.

@local-table-of-contents[#:style 'immediate-only]

@section{Construction}

@defproc[(paint? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia paint and @racket[#f] otherwise. The result does
not indicate whether the paint is open or whether it retains GPU-dependent
content.
}

@defproc[(make-paint
          [#:color color color? 'black]
          [#:style style (or/c 'fill 'stroke 'stroke-and-fill) 'fill]
          [#:stroke-width width (and/c real? (>=/c 0)) 1]
          [#:antialias? antialias? boolean? #t]
          [#:cap cap (or/c 'butt 'round 'square) 'butt]
          [#:join join (or/c 'miter 'round 'bevel) 'miter]
          [#:miter-limit miter (and/c real? (>=/c 0)) 4]
          [#:blend-mode blend
           (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity)
           'src-over]
          [#:shader shader (or/c shader? #f) #f]
          [#:path-effect effect (or/c path-effect? #f) #f]
          [#:color-filter color-filter (or/c color-filter? #f) #f]
          [#:mask-filter mask-filter (or/c mask-filter? #f) #f]
          [#:image-filter image-filter (or/c image-filter? #f) #f]) paint?]{
Creates an owned mutable paint with the specified settings. Numeric stroke
width and miter limit must also be @tech{drawing scalar}s.

The style selects filling, stroking, or both. Stroke width is measured in local
drawing units; zero requests a @tech{hairline} rather than no stroke. The
@tech{stroke cap} controls open stroke ends, while the @tech{stroke join}
controls corners. The @tech{miter limit} bounds sharp miter joins.
@deftech{Antialiasing} smooths shape edges by allowing fractional pixel coverage.
It does not control image resampling.

A shader supplies the drawing colors when present; the paint's color alpha
still modulates the result. Without a shader, the color supplies the paint's
solid RGBA value. The default @tech{blend mode} places source content over the
existing destination, taking alpha into account. The other accepted modes are
specified in @secref["skia-blend-modes"].

Each supplied shader, path effect, or filter must be open when attached. The
paint retains its own native reference; it does not take ownership of the
caller's wrapper. Closing that wrapper after attachment does not remove the
attached effect. A supplied GPU-dependent resource also makes the paint subject
to its context's lifetime and activation rules.

The constructor checks options before allocating the native paint.

@racketblock[
(with-skia ([surface (make-surface 180 80 #:background 'white)]
            [fill (make-paint #:color "#326DE6")]
            [outline (make-paint #:color 'black #:style 'stroke #:stroke-width 3)])
  (define canvas (surface-canvas surface))
  (draw-rounded-rect canvas 15 15 60 50 8 8 fill)
  (draw-rounded-rect canvas 105 15 60 50 8 8 outline))
]

The first paint fills geometry; the second draws its outline.

@reference-figure["paint-styles.png"
                  "A blue filled rounded rectangle beside a black outlined rounded rectangle on a white background."]

Effects may require rasterization in document output even though the same drawing
function accepts the paint.


@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([orange (make-paint #:color "#EFA02B")]
              [blue (make-paint #:color (rgba 50 109 230 145))])
    (draw-circle canvas 78 50 34 orange)
    (draw-circle canvas 120 50 34 blue))
)
]
@reference-figure["paint-alpha-stage9.png"
                  "A translucent blue circle overlaps an opaque orange circle, revealing source-over alpha blending in the overlap."]
}

@section[#:tag "skia-blend-modes"]{Blend Modes}

A @deftech{blend mode} combines the incoming source color with the destination
color already in the drawing target. The paint's @racket[#:blend-mode] selects
this operation. The source includes the paint's color or shader output and its
alpha; the destination is not necessarily the surface's original background.

The equations in this section describe fully covered pixels with color channels
and alpha
in the range 0 through 1. They do not include clipping, partial edge coverage,
rounding, or extended-range floating-point storage. Blending does not by itself
convert encoded RGB values to linear light. The drawing target's color space
and pixel format also matter.

@subsection{Compositing and Component Multiplication}

Let @math{S} and @math{D} be source and destination RGBA vectors with RGB
stored with @tech{premultiplied alpha}. Let @math{a} and @math{b} be their respective alpha
components. The result @math{R} is also premultiplied RGBA. Addition and
multiplication of vectors operate on each component, including alpha.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Mode} @bold{Result R} @bold{Effect})
  (list @indexed-racket['clear] @math{0} "Clear the covered area to transparent.")
  (list @indexed-racket['src] @math{S} "Replace destination with source.")
  (list @indexed-racket['dst] @math{D} "Leave destination unchanged.")
  (list @indexed-racket['src-over] @math{S + (1 - a) D} "Place source over destination.")
  (list @indexed-racket['dst-over] @math{D + (1 - b) S} "Place source behind destination.")
  (list @indexed-racket['src-in] @math{b S} "Keep source according to destination alpha.")
  (list @indexed-racket['dst-in] @math{a D} "Keep destination according to source alpha.")
  (list @indexed-racket['src-out] @math{(1 - b) S} "Keep source outside destination.")
  (list @indexed-racket['dst-out] @math{(1 - a) D} "Remove source-covered destination.")
  (list @indexed-racket['src-atop] @math{b S + (1 - a) D} "Preserve destination alpha.")
  (list @indexed-racket['dst-atop] @math{a D + (1 - b) S} "Preserve source alpha.")
  (list @indexed-racket['xor] @math{(1 - b) S + (1 - a) D} "Exclude the overlap.")
  (list @indexed-racket['plus] @math{min(S + D, 1)} "Add and clamp each component.")
  (list @indexed-racket['modulate] @math{S D} "Multiply premultiplied components."))]

The words inside and outside describe alpha weighting, not binary geometry
selection. The default @racket['src-over] gives alpha @math{a + b - a b}.
The @racket['modulate] mode instead gives alpha @math{a b}; it is not the same
operation as the @racket['multiply] mode when either input is translucent.

@subsection{Separable Color Blending}

These modes blend RGB channels separately and use source-over alpha. Let
@math{s} and @math{d} be unpremultiplied source and destination RGB, and let
@math{B(s, d)} be the mode's RGB blend function. The premultiplied result is:

@centered{@math{Rrgb = (1 - b) Srgb + (1 - a) Drgb + a b B(s, d)}}
@centered{@math{Ralpha = a + b - a b}}

The terms @math{Srgb} and @math{Drgb} denote the RGB components of @math{S} and
@math{D}. An input with zero alpha contributes zero to the blend term; it need
not be divided by zero to obtain an unpremultiplied color. In the following
formulas, @math{s} and @math{d} denote one channel at a time.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Mode} @bold{Channel blend B(s, d)})
  (list @indexed-racket['multiply] @math{s d})
  (list @indexed-racket['screen] @math{s + d - s d})
  (list @indexed-racket['darken] @math{min(s, d)})
  (list @indexed-racket['lighten] @math{max(s, d)})
  (list @indexed-racket['difference] @math{abs(d - s)})
  (list @indexed-racket['exclusion] @math{s + d - 2 s d})
  (list @indexed-racket['overlay]
        @elem{@math{2 s d} when @math{d <= 1/2}, otherwise @math{1 - 2 (1 - s) (1 - d)}.})
  (list @indexed-racket['hard-light]
        @elem{@math{2 s d} when @math{s <= 1/2}, otherwise @math{1 - 2 (1 - s) (1 - d)}.}))]

The @racket['multiply] mode darkens normalized colors; @racket['screen] lightens
them. Overlay switches between doubled multiplication and its complementary
form according to the destination, while hard light switches according to the
source. Exclusion gives a lower-contrast alternative to difference.

The remaining separable modes use these piecewise functions, with conditions
checked in the stated order:

@itemlist[
 @item{@indexed-racket['color-dodge]: The result is 0 when @math{d = 0}, 1 when
       @math{s = 1}, and @math{min(1, d / (1 - s))} otherwise. This brightens the
       destination according to the source.}
 @item{@indexed-racket['color-burn]: The result is 1 when @math{d = 1}, 0 when
       @math{s = 0}, and @math{1 - min(1, (1 - d) / s)} otherwise. This darkens the
       destination according to the source.}
 @item{@indexed-racket['soft-light]: The result is
       @math{d - (1 - 2 s) d (1 - d)} when @math{s <= 1/2}, and
       @math{d + (2 s - 1) (g(d) - d)} otherwise. Here @math{g(d)} is
       @math{((16 d - 12) d + 4) d} when @math{d <= 1/4}, and @math{sqrt(d)}
       otherwise. This changes contrast more gradually than hard light.}]

@subsection{Hue, Saturation, and Luminosity}

These four modes combine all three RGB channels; they use the same source-over
result equations as the separable modes. Their luminosity is the weighted value
@math{Lum(C) = 0.30 Cr + 0.59 Cg + 0.11 Cb}, and their saturation is
@math{Sat(C) = max(Cr, Cg, Cb) - min(Cr, Cg, Cb)}. These definitions are not an
HSV conversion or a claim of physical luminance in the target color space.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Mode} @bold{RGB blend B(s, d)})
  (list @indexed-racket['hue] @math{SetLum(SetSat(s, Sat(d)), Lum(d))})
  (list @indexed-racket['saturation] @math{SetLum(SetSat(d, Sat(s)), Lum(d))})
  (list @indexed-racket['color] @math{SetLum(s, Lum(d))})
  (list @indexed-racket['luminosity] @math{SetLum(d, Lum(s))}))]

The @racket['hue] mode takes hue from the source and saturation and luminosity
from the destination. Saturation takes only saturation from the source. Color
takes source hue and saturation. Luminosity takes only source luminosity.
The other components come from the destination, subject to gamut clipping.

The helper @math{SetSat(C, t)} rescales the channel spread while preserving
channel order. For original minimum @math{n}, middle @math{m}, and maximum
@math{x}, it sets those channels to 0, @math{(m - n) t / (x - n)}, and @math{t}.
When @math{x = n}, it sets all channels to zero.

The helper @math{SetLum(C, l)} first adds @math{l - Lum(C)} to every channel,
then clips around the requested luminosity. Let @math{n} and @math{x} be the
shifted minimum and maximum. If @math{n < 0}, replace each channel @math{c} by
@math{l + (c - l) l / (l - n)}. If @math{x > 1}, replace each channel by
@math{l + (c - l) (1 - l) / (x - l)}. These operations bring the channels into
the normalized range while retaining luminosity.

The upstream
@hyperlink["https://api.skia.org/SkBlendMode_8h.html"]{Skia blend-mode definitions}
and the
@hyperlink["https://www.w3.org/TR/compositing-1/#blending"]{color-blending equations}
provide additional background. A blend mode's definition does not imply that
PDF or SVG output can preserve it without rasterization; see
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/vector-raster/vector-raster.scrbl")]{
Vector Output and Raster Fallbacks}.

@section[#:tag "skia-paint-inspection"]{Copying and Inspecting Paints}

These operations require an open paint on its owning thread. A paint that
retains GPU-dependent content also carries that content's context restrictions.
Reading a retained shader or filter returns an owned wrapper, not a borrowed
field of the paint.

@defproc[(paint-copy [paint paint?]) paint?]{
Returns a new owned paint with the same settings. Later mutation of either
paint does not change the other's settings. Native shader, effect, and filter
objects may be shared through retained references; this is not a deep copy of
all backing pixels. The copy preserves any GPU-context dependency.
}

@defproc[(paint-color [paint paint?]) rgba?]{
Returns the paint's color as a detached eight-bit @racket[rgba] value. It does
not sample an attached shader or apply the paint's color filter. For paints
configured through extended-color APIs, this byte-valued query is not a
precision-preserving substitute for the corresponding extended-color query.
}

@defproc[(paint-shader [paint paint?]) (or/c shader? #f)]{
Returns an independently owned reference to the attached shader, or
@racket[#f] when no shader is attached. Changing or closing the paint does not
close this returned wrapper. Any GPU-context dependency remains in force.
}

@defproc[(paint-path-effect [paint paint?]) (or/c path-effect? #f)]{
Returns an independently owned reference to the attached path effect, or
@racket[#f]. The result must be released according to its own resource lifetime.
}

@defproc[(paint-color-filter [paint paint?]) (or/c color-filter? #f)]{
Returns an independently owned reference to the attached color filter, or
@racket[#f]. Replacing the paint's filter does not invalidate this reference.
}

@defproc[(paint-mask-filter [paint paint?]) (or/c mask-filter? #f)]{
Returns an independently owned reference to the attached mask filter, or
@racket[#f]. A shader-backed mask can retain a GPU-context dependency.
}

@defproc[(paint-image-filter [paint paint?]) (or/c image-filter? #f)]{
Returns an independently owned reference to the attached image filter, or
@racket[#f]. The result retains its own dependencies rather than borrowing the paint.
}

@section[#:tag "skia-paint-mutation"]{Changing Paints}

Each setter changes subsequent uses of the supplied paint and returns
@racket[(void)]. It does not change pixels already drawn or alter a previously
recorded operation. An invalid setting raises an exception. These setters use
the same option meanings as @racket[make-paint].

@defproc[(paint-set-color! [paint paint?] [color color?]) void?]{
Sets the paint's byte-valued color, including its alpha. It does not detach an
existing shader. When a shader supplies RGB, the paint's alpha still modulates
its output.
}

@defproc[(paint-set-style! [paint paint?]
                          [style (or/c 'fill 'stroke 'stroke-and-fill)]) void?]{
Selects filling, stroking, or both for geometry that uses the paint's style.
Some primitives, such as @racket[draw-line], always use stroke behavior.
}

@defproc[(paint-set-stroke-width! [paint paint?]
                                 [width (and/c real? (>=/c 0))]) void?]{
Sets the stroke width in local drawing units. Zero selects a @deftech{hairline},
a stroke whose width is one device pixel regardless of the canvas transform;
it does not disable stroking. The width must be a nonnegative
@tech{drawing scalar}.


@racketblock[
(with-skia ([surface (make-surface 200 90 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                 #:stroke-width 0 #:antialias? #t)])
    (draw-line canvas 15 20 185 20 paint)
    (draw-line canvas 15 45 185 55 paint)
    (draw-line canvas 15 75 185 60 paint))
)
]
@reference-figure["paint-hairline-stage9.png"
                  "Several one-device-pixel blue hairlines cross a white background at different angles."]
}

@defproc[(paint-set-antialias! [paint paint?] [antialias? boolean?]) void?]{
Sets whether the paint requests antialiased shape edges. Image resampling is
controlled separately by the sampling option of an image operation. A setting
does not guarantee that every destination or operation implements antialiasing.


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([hard (make-paint #:color "#326DE6" #:style 'stroke
                                #:stroke-width 7 #:antialias? #f)]
              [smooth (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 7 #:antialias? #t)]
              [separator (make-paint #:color "#BCC5CF" #:style 'stroke #:stroke-width 1)])
    (draw-line canvas 18 82 94 18 hard)
    (draw-line canvas 128 82 204 18 smooth)
    (draw-line canvas 110 8 110 92 separator))
)
]
@reference-figure["paint-antialias-stage9.png"
                  "Two diagonal blue strokes compare antialiasing disabled on the left with antialiasing enabled on the right."]
}

@defproc[(paint-set-cap! [paint paint?] [cap (or/c 'butt 'round 'square)]) void?]{
Sets the @deftech{stroke cap}, the shape of open stroke ends. A butt cap stops at
the endpoint; round and square caps extend beyond it by half the stroke width.
Closed contours have
joins rather than open end caps.
}

@defproc[(paint-set-join! [paint paint?] [join (or/c 'miter 'round 'bevel)]) void?]{
Sets the @deftech{stroke join}, the connection between adjacent stroked segments.
A miter extends the outer edges to their intersection, a round join uses a circular connection,
and a bevel connects the outer corners directly. Excessively long miters are
limited by @racket[paint-set-miter-limit!].
}

@defproc[(paint-set-miter-limit! [paint paint?]
                                [limit (and/c real? (>=/c 0))]) void?]{
Sets the dimensionless @deftech{miter limit}. It limits how far a sharp miter join can
extend relative to the stroke width; a join that exceeds the limit is beveled.
The limit must be a nonnegative @tech{drawing scalar}.
}

@defproc[(paint-set-blend-mode! [paint paint?]
          [mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity)]) void?]{
Selects one of the modes in @secref["skia-blend-modes"]. Other symbols are
rejected. Setting an ordinary blend mode replaces a custom blender previously
attached through the advanced blending API.
}

@defproc[(paint-set-shader! [paint paint?] [shader (or/c shader? #f)]) void?]{
Attaches @racket[shader], retaining the native shader independently of the
argument's wrapper. Passing @racket[#f] removes it. Explicitly closing the
argument wrapper afterward does not remove the paint's reference. GPU-dependent
content is not detached by this retention and must be used in its own context.
}

@defproc[(paint-set-path-effect! [paint paint?] [effect (or/c path-effect? #f)]) void?]{
Attaches a retained reference to @racket[effect], or removes the path effect
when @racket[effect] is @racket[#f]. It does not mutate the caller's path.
}

@defproc[(paint-set-color-filter! [paint paint?] [filter (or/c color-filter? #f)]) void?]{
Attaches a retained reference to @racket[filter], or removes the color filter
when @racket[filter] is @racket[#f].
}

@defproc[(paint-set-mask-filter! [paint paint?] [filter (or/c mask-filter? #f)]) void?]{
Attaches a retained reference to @racket[filter], or removes the mask filter
when @racket[filter] is @racket[#f]. Retained shader-backed masks preserve their
GPU-context dependencies.
}

@defproc[(paint-set-image-filter! [paint paint?] [filter (or/c image-filter? #f)]) void?]{
Attaches a retained reference to @racket[filter], or removes the image filter
when @racket[filter] is @racket[#f]. The caller's wrapper is not transferred to
the paint.

@racketblock[
(with-skia ([paint (make-paint #:color 'red)]
            [copy (paint-copy paint)])
  (paint-set-color! paint 'blue)
  (equal? (paint-color copy) (color->rgba 'red)))
]
}

@section[#:tag "skia-paint-settings"]{Reading Settings and Expanding Strokes}

@defmodule[skia/geometry #:no-declare]
@(declare-exporting skia skia/geometry #:use-sources (skia/geometry))

The following operations are also exported by @racketmodname[skia/geometry].
They require the same open-resource and thread conditions as the other paint
operations. Reading a setting is not a pixel readback.

@defproc[(paint-style [paint paint?]) (or/c 'fill 'stroke 'stroke-and-fill)]{
Returns the paint's current geometry style.
}
@defproc[(paint-stroke-width [paint paint?]) real?]{
Returns the current stroke width. A result of zero denotes a hairline.
}
@defproc[(paint-cap [paint paint?]) (or/c 'butt 'round 'square)]{
Returns the current stroke-cap setting.
}
@defproc[(paint-join [paint paint?]) (or/c 'miter 'round 'bevel)]{
Returns the current stroke-join setting.
}
@defproc[(paint-miter-limit [paint paint?]) real?]{
Returns the current dimensionless miter limit.
}
@defproc[(paint-antialias? [paint paint?]) boolean?]{
Reports whether the paint requests antialiased shape edges. This is a setting
query, not a predicate for recognizing paint values.
}
@defproc[(paint-dither? [paint paint?]) boolean?]{
Reports whether the paint requests dithering when reducing color precision.
The setting does not guarantee that a particular destination applies dithering.
}

@defproc[(paint-set-dither! [paint paint?] [enabled? boolean?]) void?]{
Sets the dithering request. It does not change the stored paint color.
}

@defproc[(paint-blend-mode-or-src-over [paint paint?]) symbol?]{
Returns the ordinary blend mode when the paint has one. For a custom blender,
the native query substitutes @racket['src-over]. Consequently, that result does
not establish that the paint actually uses ordinary source-over blending.
}

@defproc[(paint-reset! [paint paint?]) void?]{
Resets the paint to native Skia defaults and removes attached shader, effect,
filter, and blender references. The paint wrapper remains open. Native defaults
include opaque black, fill style, hairline stroke width, butt caps, miter joins
with limit four, source-over blending, and disabled antialiasing and dithering.

These are not exactly the defaults of @racket[make-paint], which explicitly
selects stroke width one and enables antialiasing. Resetting a paint therefore
is not interchangeable with constructing a paint using no arguments.

@racketblock[
(with-skia ([paint (make-paint)])
  (define constructed
    (list (paint-stroke-width paint) (paint-antialias? paint)))
  (paint-reset! paint)
  (list constructed
        (list (paint-stroke-width paint) (paint-antialias? paint))))
]

The first list contains a stroke width of 1 and @racket[#t]; the second
contains a stroke width of 0 and @racket[#f].
}

@defproc[(paint->fill-path [paint paint?] [path skia-path?]
                          [#:cull cull (or/c list? vector? #f) #f]
                          [#:matrix matrix matrix? matrix-identity])
         (values skia-path? boolean?)]{
Returns a new owned path for the geometry produced by the paint's style, stroke
settings, and path effect, together with a boolean indicating whether the
result is fillable. A @racket[#f] flag denotes hairline geometry, not allocation
failure: the returned path still has its own lifetime and must be released.

The optional cull rectangle is a four-element list or vector of x, y, width,
and height in local coordinates. Extents must be nonnegative, and positive
extents must remain positive after native rounding. It is a culling hint, not
a promise that the result is clipped to that rectangle. The matrix supplies
the local-to-device context used by native stroke/path-effect calculation;
it is not an instruction to apply @racket[path-transform] to the returned path.
Color, shaders, mask/image/color filters, and blending are not baked into the
result. The source path and paint are unchanged.

@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)]
            [path (make-path '((move 10 20) (line 90 20)))]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 6 #:cap 'round)]
            [fill (make-paint #:color "#326DE6")]
            [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
            [font (make-font #:size 13)]
            [label (make-paint #:color "#20344E")])
  (define-values (outline fillable?) (paint->fill-path paint path))
  (call-with-skia-resource outline
    (lambda (outline)
      (define canvas (surface-canvas surface))
      (draw-simple-text canvas "original stroke" 10 18 font label)
      (with-canvas-state canvas
        (canvas-translate! canvas 10 15)
        (draw-path canvas path paint))
      (draw-simple-text canvas "returned fill path" 10 68 font label)
      (with-canvas-state canvas
        (canvas-translate! canvas 10 65)
        (draw-path canvas outline fill)
        (draw-path canvas outline boundary))
      (and fillable? (path-contains? outline 50 20)))))
]

@reference-figure["paint-fill-path.png"
                  "The original blue round-capped stroke and the blue fill path returned for the same line, in separate rows. A dark outline marks the returned path boundary."]

Both rows have the same capsule geometry. The returned path contains the stroke expansion,
not the paint's color, filters, shader, or blend settings.
}

@section{Additional Visual Examples}

The following examples show settings whose effect is easiest to recognize in rendered geometry.

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (for ([cap '(butt round square)] [y '(20 50 80)])
    (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width 18 #:cap cap)])
      (draw-line (surface-canvas surface) 35 y 145 y paint))))
]
@reference-figure["paint-caps.png"
                  "Three thick blue horizontal strokes showing butt, round, and square caps."]

@racketblock[
(with-skia ([surface (make-surface 210 100 #:background 'white)])
  (for ([join '(miter round bevel)] [x '(10 80 150)])
    (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width 12 #:join join)])
      (draw-polygon (surface-canvas surface)
                    (list (list (+ x 5) 80) (list (+ x 30) 20) (list (+ x 55) 80))
                    paint #:closed? #f))))
]
@reference-figure["paint-joins.png"
                  "Three blue V-shaped strokes comparing miter, round, and bevel joins."]

@racketblock[
(with-skia ([surface (make-surface 420 250 #:background 'white)]
            [high-miter (make-paint #:color "#326DE6" #:style 'stroke
                                    #:stroke-width 16 #:join 'miter)]
            [low-miter (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width 16 #:join 'miter)]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
            [checker-light (make-paint #:color "#F5F6F8")]
            [checker-dark (make-paint #:color "#D9DEE6")])
  (define canvas (surface-canvas surface))
  (paint-set-miter-limit! high-miter 8)
  (paint-set-miter-limit! low-miter 1.2)
  (for ([paint (list high-miter low-miter)] [x '(20 230)]
        [caption '("miter limit 8" "miter limit 1.2 -> bevel")])
    (draw-simple-text canvas caption x 17 font label)
    (draw-polygon canvas (list (list (+ x 55) 115) (list (+ x 85) 42)
                               (list (+ x 115) 115)) paint #:closed? #f))
  (draw-simple-text canvas "declared D: 55% azure; incoming S: 65% orange" 18 137 font label)
  (define (draw-checker x)
    (for* ([row (in-range 3)] [column (in-range 6)])
      (draw-rect canvas (+ x (* 20 column)) (+ 150 (* 20 row)) 20 20
                 (if (even? (+ row column)) checker-light checker-dark))))
  (define (blend-pane mode)
    (with-skia ([pane (make-surface 110 58)]
                [destination (make-paint #:color (rgba 23 105 224 140))]
                [source (make-paint #:color (rgba 239 79 55 166) #:blend-mode mode)])
      (draw-rounded-rect (surface-canvas pane) 6 6 82 44 8 8 destination)
      (draw-circle (surface-canvas pane) 72 29 22 source)
      (surface-snapshot pane)))
  (for ([mode '(src-over modulate multiply)] [x '(18 155 292)])
    (draw-simple-text canvas (symbol->string mode) x 225 font label)
    (draw-checker x)
    (with-skia ([result (blend-pane mode)])
      (draw-image canvas result x 150))
    (draw-rect canvas x 150 110 58 outline))
  surface)
]
@reference-figure["paint-miter-and-translucent-blends.png"
                  "Top: matching acute blue V strokes use miter limits 8 and 1.2; the low limit bevels the otherwise long miter. Bottom: a 55-percent opaque azure destination and 65-percent opaque orange source are combined over the same gray checkerboard by source-over, modulate, and multiply; the latter two visibly differ with translucency."]

The first row exercises @racket[paint-set-miter-limit!] after paint construction.
The lower row declares its translucent destination rather than treating the
white page as the destination: @racket['modulate] multiplies premultiplied
components, while @racket['multiply] uses source-over alpha with an RGB
multiply blend.  It is a compact complement to the cap, join, alpha,
multiply, and screen examples above, not a gallery of every blend mode.

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (for ([width '(2 8 18)] [y '(20 50 80)])
    (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width width #:cap 'round)])
      (draw-line (surface-canvas surface) 20 y 160 y paint))))
]
@reference-figure["paint-stroke-widths.png"
                  "Three blue horizontal strokes with increasingly large stroke widths."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [background (make-paint #:color "#326DE6")]
            [source (make-paint #:color "#EFA02B" #:blend-mode 'multiply)])
  (draw-rect (surface-canvas surface) 25 20 95 60 background)
  (draw-circle (surface-canvas surface) 115 50 36 source))
]
@reference-figure["blend-multiply.png"
                  "An orange circle overlaps a blue rectangle using multiply blending, darkening the overlap."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [background (make-paint #:color "#326DE6")]
            [source (make-paint #:color "#EFA02B" #:blend-mode 'screen)])
  (draw-rect (surface-canvas surface) 25 20 95 60 background)
  (draw-circle (surface-canvas surface) 115 50 36 source))
]
@reference-figure["blend-screen.png"
                  "An orange circle overlaps a blue rectangle using screen blending, lightening the overlap."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [under (make-paint #:color "#EFA02B")]
            [paint (make-paint #:color (rgba 50 109 230 190)
                               #:style 'stroke-and-fill #:stroke-width 10)])
  (draw-circle (surface-canvas surface) 90 50 34 under)
  (draw-rounded-rect (surface-canvas surface) 45 22 90 56 14 14 paint))
]
@reference-figure["paint-stroke-and-fill.png"
                  "A translucent blue rounded rectangle is both filled and stroked over an orange circle."]
