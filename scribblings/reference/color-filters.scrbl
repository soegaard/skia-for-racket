#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/color-filters))

@title[#:tag "skia-color-filters"]{Color Filters}

@(declare-exporting skia)

Use a color filter to tint artwork, make it grayscale, or adjust its contrast
while keeping the same geometry. It is suitable for changes computed from
each input color independently. For blur, shadows, or other effects that need
neighboring pixels, use an @tech{image filter} instead.

A @deftech{color filter} changes colors without resampling neighboring
pixels. Attach one to a @tech{paint}, wrap a @tech{shader} with
@racket[shader-with-color-filter], or use @racket[make-color-filter-image-filter]
inside a @tech{filter graph}.

Constructors return @tech{owned resources} that keep their own native references
to any input filters, independently of the caller's wrappers. Native construction
failure raises an exception.
Applying a filter does not change the input image's stored pixels or its
color-space metadata.

@section{Core Color Filters}

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
            [source (make-paint #:color 'blue)]
            [filtered (make-paint #:color 'blue #:color-filter filter)]
            [surface (make-surface 160 70 #:background 'white)])
  (define canvas (surface-canvas surface))
  (draw-rect canvas 20 15 45 40 source)
  (draw-rect canvas 95 15 45 40 filtered)
  (surface-pixel surface 110 30))
]

The constant term makes the filtered rectangle red while preserving the input
alpha. The unfiltered rectangle remains blue.

@reference-figure["color-filter.png"
                  "A blue rectangle beside a red rectangle produced from the same blue paint by a color-matrix filter."]
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
sees the preceding stage's output, including its clamping. The result keeps its
own native references to both filters. Their caller-owned wrappers may
subsequently be closed.
}

@section{Additional Color Filters}

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
Returns a filter applying the sRGB encoding @tech{transfer function} to RGB channels.
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
including at the endpoints; the result keeps its own native references to both filters.
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
data must fit the current byte limit.
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
the combined size of the copied tables must fit @racket[current-skia-byte-limit].
Supplying no tables returns an owned identity filter, not @racket[#f].

@racketblock[
(with-skia ([filter (make-table-argb-color-filter)]
            [paint (make-paint #:color "#326DE6" #:color-filter filter)]
            [surface (make-surface 4 4)])
  (draw-paint (surface-canvas surface) paint)
  (equal? (surface-pixel surface 1 1) (color->rgba "#326DE6")))
]
}

@racketblock[
(with-skia ([color-source (make-surface 120 50)]
            [gray-source (make-surface 120 50)]
            [spectrum (make-linear-gradient-shader 0 0 120 0 '(red yellow green cyan blue))]
            [gray (make-linear-gradient-shader 0 0 120 0 '(black white))]
            [spectrum-paint (make-paint #:shader spectrum)]
            [gray-paint (make-paint #:shader gray)])
  (draw-rect (surface-canvas color-source) 0 0 120 50 spectrum-paint)
  (draw-rect (surface-canvas gray-source) 0 0 120 50 gray-paint)
  (with-skia ([color-image (surface-snapshot color-source)]
              [gray-image (surface-snapshot gray-source)]
              [hsla (make-hsla-matrix-filter
                     '(1 0 0 0 0.18
                       0 0.55 0 0 0
                       0 0 1 0 0
                       0 0 0 1 0))]
              [to-linear (make-srgb-to-linear-gamma-color-filter)]
              [to-srgb (make-linear-to-srgb-gamma-color-filter)]
              [blue-table (make-table-argb-color-filter
                           #:blue (apply bytes (for/list ([v (in-range 256)]) (- 255 v))))]
              [plain (make-paint)]
              [hsla-paint (make-paint #:color-filter hsla)]
              [linear-paint (make-paint #:color-filter to-linear)]
              [srgb-paint (make-paint #:color-filter to-srgb)]
              [blue-paint (make-paint #:color-filter blue-table)]
              [surface (make-surface 420 180 #:background 'white)]
              [font (make-font #:size 11)]
              [label (make-paint #:color "#20344E")])
    (define canvas (surface-canvas surface))
    (for ([text '("source strip" "HSLA hue + desaturate" "blue table inverted")]
          [x '(15 150 285)])
      (draw-simple-text canvas text x 17 font label))
    (for ([paint (list plain hsla-paint blue-paint)] [x '(15 150 285)])
      (draw-image canvas color-image x 28 #:paint paint))
    (for ([text '("sRGB -> linear" "linear -> sRGB")] [x '(80 220)])
      (draw-simple-text canvas text x 103 font label))
    (draw-image canvas gray-image 80 114 #:paint linear-paint)
    (draw-image canvas gray-image 220 114 #:paint srgb-paint)))
]

@reference-figure["color-filter-channel-curves.png"
                  "A common multicolor strip and grayscale ramp passed through actual color filters: an HSLA hue/saturation matrix, an inverted blue-only table, sRGB-to-linear RGB channels, and linear-to-sRGB RGB channels."]

These filters change channels. They do not retag an image or perform a full color-space or
gamut conversion.

@defproc[(make-lighting-color-filter [multiply color?] [add color?]) color-filter?]{
Returns a filter that multiplies RGB by the normalized RGB channels of
@racket[multiply], adds those of @racket[add], and clamps the result. The alpha
components of the two arguments are ignored; the incoming color's alpha is
preserved. This operation does not model a spatial light source or surface normals.

@racketblock[
(with-skia ([filter (make-lighting-color-filter "#808080" "#500000")]
            [plain (make-paint #:color "#326DE6")]
            [filtered (make-paint #:color "#326DE6" #:color-filter filter)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 15 18 60 44 8 8 plain)
  (draw-rounded-rect (surface-canvas surface) 105 18 60 44 8 8 filtered))
]

@reference-figure["lighting-color-filter.png"
                  "Two blue rounded rectangles, with the right one darkened and shifted toward red by a lighting color filter."]
}

@section{Additional Visual Examples}

These examples compare several color-filter constructions using simple source colors or gradients.

@racketblock[
(with-skia ([filter (make-blend-color-filter 'orange 'screen)]
            [plain (make-paint #:color "#326DE6")]
            [filtered (make-paint #:color "#326DE6" #:color-filter filter)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 18 18 60 44 8 8 plain)
  (draw-rounded-rect (surface-canvas surface) 102 18 60 44 8 8 filtered))
]
@reference-figure["blend-color-filter.png"
                  "An unfiltered blue rounded rectangle beside the lighter result of screening orange into the same input color."]

@racketblock[
(with-skia ([inner (make-blend-color-filter 'red 'src)]
            [outer (make-blend-color-filter 'blue 'screen)]
            [filter (make-compose-color-filter outer inner)]
            [paint (make-paint #:color "#EFA02B" #:color-filter filter)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 35 18 110 44 8 8 paint))
]
@reference-figure["compose-color-filter.png"
                  "A rounded rectangle colored by a two-stage composition of color filters."]

@racketblock[
(with-skia ([red-filter (make-blend-color-filter 'red 'src)]
            [blue-filter (make-blend-color-filter 'blue 'src)]
            [filter (make-lerp-color-filter 0.5 red-filter blue-filter)]
            [paint (make-paint #:color 'white #:color-filter filter)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 35 16 110 48 10 10 paint))
]
@reference-figure["lerp-color-filter.png"
                  "A purple rounded rectangle produced by interpolating halfway between constant red and blue color filters."]

@racketblock[
(with-skia ([shader (make-linear-gradient-shader 0 0 180 0 '(red yellow green cyan blue))]
            [filter (make-luma-color-filter)]
            [paint (make-paint #:shader shader #:color-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rect (surface-canvas surface) 0 0 180 90 paint))
]
@reference-figure["luma-color-filter.png"
                  "A colored gradient converted into black coverage whose opacity follows luminance."]

@racketblock[
(with-skia ([shader (make-linear-gradient-shader 0 0 180 0 '(black white))]
            [filter (make-high-contrast-color-filter #:contrast 0.8)]
            [paint (make-paint #:shader shader #:color-filter filter)]
            [surface (make-surface 180 80)])
  (draw-rect (surface-canvas surface) 0 0 180 80 paint))
]
@reference-figure["high-contrast-color-filter.png"
                  "A black-to-white gradient with strong contrast enhancement around its middle tones."]

@racketblock[
(define table (for/vector ([i (in-range 256)]) (min 255 (* 2 i))))
(with-skia ([filter (make-table-color-filter table)]
            [plain (make-paint #:color "#326DE6")]
            [filtered (make-paint #:color "#326DE6" #:color-filter filter)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 18 18 60 44 8 8 plain)
  (draw-rounded-rect (surface-canvas surface) 102 18 60 44 8 8 filtered))
]
@reference-figure["table-color-filter.png"
                  "A blue rounded rectangle beside a brighter result produced by a channel lookup table."]
