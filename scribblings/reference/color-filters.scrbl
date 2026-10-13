#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/color-filters))

@title[#:tag "skia-color-filters"]{Color Filters}

@(declare-exporting skia)

A @deftech{color filter} changes colors without resampling neighboring
pixels. Attach one to a paint, wrap a shader with
@racket[shader-with-color-filter], or use @racket[make-color-filter-image-filter]
inside an image-filter graph.

Constructors return owned resources and retain any input filters independently
of the caller's wrappers. Numeric coefficients must be drawing scalars. Native
construction failure raises an exception. Applying a filter does not change
the input image's stored pixels or its color-space metadata.

@defproc[(color-filter? [v any/c]) boolean?]{
Returns @racket[#t] for a color-filter resource and @racket[#f] otherwise.
The predicate remains true after closure.
}

@defproc[(make-color-matrix-filter [matrix (or/c list? vector?)]) color-filter?]{
Returns a color filter using 20 row-major coefficients: four rows with five
coefficients each. Each row computes one output channel from the input RGBA
channels plus a constant term. The operation works on unpremultiplied,
normalized RGBA; the fifth coefficient in a row is an additive offset, not
an eight-bit channel value. Results are clamped and returned to premultiplied
form for drawing. The input coefficients are copied.

@racketblock[
(with-skia ([filter
             (make-color-matrix-filter
              '(0 0 0 0 1
                0 0 0 0 0
                0 0 0 0 0
                0 0 0 1 0))]
            [paint (make-paint #:color 'blue #:color-filter filter)]
            [surface (make-surface 4 4)])
  (draw-paint (surface-canvas surface) paint)
  (surface-pixel surface 1 1))
]

The constant term makes the result red while preserving the input alpha.
}

@defproc[(make-blend-color-filter
          [color color?]
          [mode
           (or/c 'clear 'src 'src-over 'dst-over 'src-in 'dst-in 'src-out 'dst-out 'src-atop
            'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten 'color-dodge
            'color-burn 'hard-light 'soft-light 'difference 'exclusion 'multiply 'hue 'saturation
            'color 'luminosity)]) color-filter?]{
Returns a filter that blends a constant source color with each incoming
color as the destination. The blend modes have the meanings specified in
@secref["skia-blend-modes"]. The mode @racket['dst] is rejected because it is
an identity operation with no native filter object. Other combinations may
also be rejected when the native factory cannot produce a filter.
This operation is separate from blending the final paint into the drawing target.
}

@defproc[(make-compose-color-filter [outer color-filter?] [inner color-filter?]) color-filter?]{
Returns a filter applying @racket[inner] before @racket[outer]. Each stage
sees the preceding stage's output, including its clamping. Both filters are
retained. Their caller-owned wrappers may subsequently be closed.
}

@section{Additional Color Operations}

@defmodule[skia/color-filters #:no-declare]
@(declare-exporting skia skia/color-filters #:use-sources (skia/color-filters))

@defproc[(make-hsla-matrix-filter [matrix (or/c list? vector?)]) color-filter?]{
Returns a filter that converts unpremultiplied RGB to hue, saturation, and
lightness, applies a four-row, five-column matrix to HSLA, then converts back
to RGB. The 20 row-major coefficients are copied and require 80 bytes within
the byte limit. Hue uses a normalized turn, not degrees. This is an HSLA
operation, not HSV and not a change of RGB color-space metadata.
}

@defproc[(make-linear-to-srgb-gamma-color-filter) color-filter?]{
Returns a filter applying the sRGB encoding transfer function to RGB channels.
Alpha is unchanged. This is a channel operation, not a full gamut conversion;
it does not inspect or replace the source image's color-space tag.
}

@defproc[(make-srgb-to-linear-gamma-color-filter) color-filter?]{
Returns a filter applying the inverse sRGB transfer function to RGB channels.
Alpha is unchanged. It changes channel values rather than merely marking an
image as linear. Applying it to already-linear values performs another conversion.
}

@defproc[(make-lerp-color-filter
          [weight (real-in 0 1)]
          [filter0 color-filter?]
          [filter1 color-filter?]) color-filter?]{
Returns a filter interpolating between the two filters' results for the same
input color. Weight zero selects the first result and weight one selects the
second. This is not composition. Both input filters must be supplied and open,
including at the endpoints; they are retained independently.
}

@defproc[(make-luma-color-filter) color-filter?]{
Returns a filter with black RGB and alpha derived from the incoming color's
luminance and alpha. It turns color information into coverage; it does not
produce an ordinary grayscale RGB image.
}

@defproc[(make-high-contrast-color-filter
          [#:grayscale? grayscale? boolean? #f]
          [#:invert-style invert-style (or/c 'none 'brightness 'lightness) 'none]
          [#:contrast contrast (real-in -1 1) 0]) color-filter?]{
Returns a high-contrast color filter. Optional grayscale conversion precedes
inversion and contrast adjustment. Brightness inversion complements the RGB
channels; lightness inversion operates on HSL lightness. None disables inversion.
Negative contrast reduces channel contrast and positive contrast increases it;
zero leaves that adjustment neutral. Alpha is preserved. The configuration
payload must fit the current byte limit.
}

@defproc[(make-table-color-filter
          [table (or/c bytes? (listof byte?) (vectorof byte?))]) color-filter?]{
Returns a filter applying the same 256-entry table to alpha, red, green, and
blue. Each entry is an exact byte. The input may be a byte string, list, or
vector and is copied. Table lookup operates on unpremultiplied channel values;
recombination into premultiplied drawing colors can introduce rounding.
The 256-byte table must fit the byte limit.
}

@defproc[(make-table-argb-color-filter
          [#:alpha alpha (or/c #f bytes? (listof byte?) (vectorof byte?)) #f]
          [#:red red (or/c #f bytes? (listof byte?) (vectorof byte?)) #f]
          [#:green green (or/c #f bytes? (listof byte?) (vectorof byte?)) #f]
          [#:blue blue (or/c #f bytes? (listof byte?) (vectorof byte?)) #f]) color-filter?]{
Returns a filter with a separate table for each channel. A false table leaves
that channel unchanged. Each supplied table has exactly 256 byte entries;
the aggregate copied table payload must fit @racket[current-skia-byte-limit].
Supplying no tables returns an owned identity filter, not @racket[#f].

@racketblock[
(with-skia ([filter (make-table-argb-color-filter)]
            [paint (make-paint #:color "#326DE6" #:color-filter filter)]
            [surface (make-surface 4 4)])
  (draw-paint (surface-canvas surface) paint)
  (equal? (surface-pixel surface 1 1) (color->rgba "#326DE6")))
]
}

@defproc[(make-lighting-color-filter [multiply color?] [add color?]) color-filter?]{
Returns a filter that multiplies RGB by the normalized RGB channels of
@racket[multiply], adds those of @racket[add], and clamps the result. The alpha
components of the two arguments are ignored; the incoming color's alpha is
preserved. This operation does not model a spatial light source or surface normals.
}
