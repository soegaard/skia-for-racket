#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/effects))

@title[#:tag "skia-path-effects"]{Path Effects and Mask Filters}

@(declare-exporting skia)

Use a path effect for dashed strokes or repeated shapes along an outline.
Use a mask filter to soften a shape's coverage, as with a blurred edge. These
settings belong to the paint, so the same effect can be reused on different
shapes without rebuilding their paths.

A @deftech{path effect} changes the geometry used for drawing without mutating
its input path. A @deftech{mask filter} changes the coverage of a shape rather
than the colors inside an image. Attach them with @racket[make-paint],
@racket[paint-set-path-effect!], or @racket[paint-set-mask-filter!].

The constructors return owned resources. A paint or composed effect retains
its own native references to its inputs; it does not take ownership of the
caller's wrappers. Inputs must be open on the appropriate owning thread when
used. GPU-dependent inputs retain their context restrictions. Native rejection
raises an exception.

@section{Path Effects}

@defproc[(path-effect? [v any/c]) boolean?]{
Returns @racket[#t] for a path-effect resource and @racket[#f] otherwise.
The predicate remains true after the resource is closed.
}

@defproc[(make-dash-path-effect [intervals (or/c list? vector?)] [phase real? 0]) path-effect?]{
Returns an effect that alternates drawn and skipped distances along a stroke.
The first interval is drawn, the second is skipped, and the pattern repeats.
Intervals are nonnegative real numbers in a list or vector of even length,
with at least two entries and a positive sum. Zero entries are allowed, but
an all-zero pattern is rejected. The copied interval array must fit
@racket[current-skia-byte-limit].

The phase shifts the start within the repeating pattern and may be negative.
Distances use local drawing units, not a fixed number of device pixels.
Dashing is intended for stroked geometry; it does not turn a filled area into
alternating bands.

@racketblock[
(with-skia ([surface (make-surface 100 30 #:background 'white)]
            [dash (make-dash-path-effect '(8 4))]
            [paint (make-paint #:color 'blue #:style 'stroke
                               #:stroke-width 3 #:path-effect dash)])
  (skia-close! dash)
  (draw-line (surface-canvas surface) 10 15 90 15 paint)
  (save-png surface "dashed-line.png" #:exists 'replace))
]

@reference-figure["dashed-line.png"
                  "A blue horizontal dashed line on a white background."]

Closing the caller's dash wrapper does not remove the paint's retained effect.


@racketblock[
(with-skia ([surface (make-surface 200 90 #:background 'white)]
            [a (make-dash-path-effect '(12 7) 0)]
            [b (make-dash-path-effect '(12 7) 8)]
            [pa (make-paint #:color "#326DE6" #:style 'stroke
                            #:stroke-width 5 #:path-effect a)]
            [pb (make-paint #:color "#E94F37" #:style 'stroke
                            #:stroke-width 5 #:path-effect b)])
  (draw-line (surface-canvas surface) 15 30 185 30 pa)
  (draw-line (surface-canvas surface) 15 62 185 62 pb))
]
@reference-figure["dash-phase-stage8.png"
                  "Two equal dash patterns start at different phases, shifting the red row relative to the blue row."]
}

@defproc[(make-corner-path-effect [radius (and/c real? (>/c 0))]) path-effect?]{
Returns an effect that replaces sharp path corners with rounded transitions
of the requested radius. The input path is unchanged. The radius is measured
in local drawing units and must remain positive at native precision; native
rejection raises an exception.

@racketblock[
(with-skia ([effect (make-corner-path-effect 12)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 5
                               #:path-effect effect)]
            [surface (make-surface 160 90 #:background 'white)])
  (draw-polygon (surface-canvas surface)
                '((15 70) (55 20) (95 70) (145 20))
                paint
                #:closed? #f))
]

@reference-figure["corner-path-effect.png"
                  "A thick blue polyline whose sharp corners are replaced by rounded transitions."]
}

@defproc[(make-discrete-path-effect
          [segment-length (and/c real? (>/c 1/4096))]
          [deviation (and/c real? (>=/c 0))]
          [seed (integer-in 0 #xffffffff) 0]) path-effect?]{
Returns an effect that subdivides a path and perturbs the resulting vertices.
The segment length controls subdivision; deviation controls displacement.
The segment length must exceed 1/4096, not merely zero. The seed selects the
perturbation pattern. Reusing it permits repeatable results within the same
backend, but does not promise identical geometry across Skia versions.

@racketblock[
(with-skia ([effect (make-discrete-path-effect 12 5 7)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 4
                               #:path-effect effect)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-line (surface-canvas surface) 15 45 165 45 paint))
]

@reference-figure["discrete-path-effect.png"
                  "A blue horizontal stroke broken into a repeatable irregular zigzag by a discrete path effect."]
}

@defproc[(make-trim-path-effect
          [start (real-in 0 1)]
          [stop (real-in 0 1)]
          [#:mode mode (or/c 'normal 'inverted) 'normal]) path-effect?]{
Returns an effect selecting the interval from @racket[start] to @racket[stop]
in the path's length parameterization, or its complement in inverted mode.
The arguments must satisfy @math{start < stop}. Normal mode rejects the full
interval from 0 to 1 because it produces no native effect object. Inverted
mode permits that interval and removes the whole path. These fractions are
not x coordinates or individual curve parameters.

@racketblock[
(with-skia ([path (make-path)]
            [effect (make-trim-path-effect 0.10 0.72)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 6
                               #:cap 'round
                               #:path-effect effect)]
            [surface (make-surface 160 110 #:background 'white)])
  (path-add-circle! path 80 55 38)
  (draw-path (surface-canvas surface) path paint))
]

@reference-figure["trim-path-effect.png"
                  "Only a portion of a blue circular stroke remains after applying a trim path effect."]


@racketblock[
(with-skia ([surface (make-surface 160 110 #:background 'white)]
            [path (make-path)]
            [effect (make-trim-path-effect 0.20 0.70 #:mode 'inverted)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 7 #:cap 'round
                               #:path-effect effect)])
  (path-add-circle! path 80 55 38)
  (draw-path (surface-canvas surface) path paint))
]
@reference-figure["trim-inverted-stage8.png"
                  "An inverted trim removes the middle portion of a thick blue circular stroke and keeps the complementary arcs."]
}

@defproc[(make-compose-path-effect [outer path-effect?] [inner path-effect?]) path-effect?]{
Returns an effect that applies @racket[inner] first, then @racket[outer].
The result retains both effects; closing either input wrapper does not
invalidate the result. Composition is not generally commutative.


@racketblock[
(with-skia ([surface (make-surface 210 100 #:background 'white)]
            [dash (make-dash-path-effect '(15 7))]
            [corner (make-corner-path-effect 10)]
            [effect (make-compose-path-effect dash corner)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 5 #:path-effect effect)])
  (draw-polygon (surface-canvas surface)
                '((15 80) (65 20) (115 80) (195 25))
                paint #:closed? #f))
]
@reference-figure["compose-path-effects-stage8.png"
                  "A composed path effect rounds a zigzag and then breaks the rounded result into blue dashes."]
}

@defproc[(make-sum-path-effect [first path-effect?] [second path-effect?]) path-effect?]{
Returns an effect that applies both effects to the original geometry and
combines the resulting paths. Unlike composition, neither effect receives
the other's output. Both input effects are retained.


@racketblock[
(with-skia ([surface (make-surface 210 100 #:background 'white)]
            [wide (make-dash-path-effect '(22 12))]
            [fine (make-dash-path-effect '(5 9) 3)]
            [effect (make-sum-path-effect wide fine)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 5 #:path-effect effect)])
  (draw-line (surface-canvas surface) 15 50 195 50 paint))
]
@reference-figure["sum-path-effects-stage8.png"
                  "A summed path effect overlays two blue dash patterns with different rhythms along one line."]
}

@subsection{Repeated Shapes and Lattices}

@defmodule[skia/effects #:no-declare]
@(declare-exporting skia skia/effects #:use-sources (skia/effects))

@defproc[(make-1d-path-effect
          [path skia-path?]
          [advance (and/c real? (>/c 0))]
          [phase real? 0]
          [#:style style (or/c 'translate 'rotate 'morph) 'translate]) path-effect?]{
Returns an effect that repeats the supplied stamp path along the drawn path.
The stamp must contain at least one point, and its copied point payload must
fit @racket[current-skia-byte-limit]. The advance must remain positive after
single-precision rounding. Phase offsets the repetitions.

Translate mode moves each stamp without rotating it. Rotate mode aligns it
with the path tangent. Morph mode bends the stamp to follow the path.
The stamp geometry is copied; later mutation or closure of @racket[path]
does not change the effect.

@racketblock[
(with-skia ([stamp (make-path '((move 0 -5) (line 10 0) (line 0 5) (close)))]
            [line (make-path '((move 15 45) (cubic 60 10 130 80 175 45)))]
            [effect (make-1d-path-effect stamp 18 0 #:style 'rotate)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 2
                               #:path-effect effect)]
            [surface (make-surface 190 90 #:background 'white)])
  (draw-path (surface-canvas surface) line paint))
]

@reference-figure["stamp-path-effect.png"
                  "Small blue triangular stamps rotate along a curved path."]


@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)]
            [stamp (make-path '((move 0 -6) (line 12 0) (line 0 6) (close)))]
            [guide (make-path '((move 15 70) (cubic 70 10 150 100 205 35)))]
            [effect (make-1d-path-effect stamp 20 0 #:style 'morph)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 2 #:path-effect effect)])
  (draw-path (surface-canvas surface) guide paint))
]
@reference-figure["stamp-morph-stage8.png"
                  "Repeated triangular stamps bend to follow a cubic curve when the one-dimensional path effect uses morph mode."]
}

@defproc[(make-2d-line-path-effect [width (and/c real? (>/c 0))] [matrix matrix?]) path-effect?]{
Returns an effect that covers the input region with parallel strokes using
the lattice defined by @racket[matrix]. Width must remain positive after
rounding. The affine lattice matrix must have a representable inverse.
Its coefficients are copied; it is not the canvas's current transform.
}

@defproc[(make-2d-path-effect [matrix matrix?] [path skia-path?]) path-effect?]{
Returns an effect that places copies of a stamp path on a two-dimensional
lattice within the input region. The matrix must have a representable inverse.
The stamp must contain points, and its copied point payload must fit the byte
limit. Later mutation or closure of the stamp does not change the effect.
}

@racketblock[
(with-skia ([surface (make-surface 300 150 #:background 'white)]
            [stamp (make-path '((move -5 -4) (line 6 0) (line -5 4) (close)))]
            [line-effect (make-2d-line-path-effect 3 (matrix-scale 14 14))]
            [stamp-effect (make-2d-path-effect (matrix-scale 18 18) stamp)]
            [line-paint (make-paint #:color "#326DE6" #:style 'stroke
                                    #:stroke-width 2 #:path-effect line-effect)]
            [stamp-paint (make-paint #:color "#E94F37" #:style 'stroke
                                     #:stroke-width 2 #:path-effect stamp-effect)]
            [font (make-font #:size 12)]
            [label (make-paint #:color "#20344E")]
            [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
  (define canvas (surface-canvas surface))
  (draw-simple-text canvas "parallel-line lattice" 20 20 font label)
  (draw-simple-text canvas "asymmetric stamp lattice" 165 20 font label)
  (draw-rect canvas 20 35 115 95 line-paint)
  (draw-rect canvas 165 35 115 95 stamp-paint)
  (draw-rect canvas 20 35 115 95 boundary)
  (draw-rect canvas 165 35 115 95 boundary))
]

@reference-figure["path-effect-2d-lattices.png"
                  "The same bounded rectangle covered by a blue parallel-line path-effect lattice and an orange asymmetric-stamp lattice. Dark outlines mark the input regions."]

The matrices define each effect's repeated local lattice; they do not transform the canvas or
the outlined input rectangles.

@section[#:tag "skia-mask-filters"]{Mask Filters}

@(declare-exporting skia)

@defproc[(mask-filter? [v any/c]) boolean?]{
Returns @racket[#t] for a mask-filter resource and @racket[#f] otherwise.
The result does not indicate liveness or independence from a GPU context.
}

@defproc[(make-blur-mask-filter
          [sigma (and/c real? (>/c 0))]
          [#:style style (or/c 'normal 'solid 'outer 'inner) 'normal]
          [#:respect-ctm? respect-ctm? boolean? #t]) mask-filter?]{
Returns a Gaussian blur of the shape's coverage. Sigma is the standard
deviation, not a radius specifying an exact support boundary. Normal style
blurs inside and outside the shape. Solid style preserves its interior and
adds an outer blur. Outer style keeps only the exterior blur. Inner style
keeps only the interior blur.

When @racket[respect-ctm?] is true, the current canvas transform affects the
blur size; otherwise the blur size is interpreted in device space.
This filter blurs shape coverage, not arbitrary neighboring image colors.
For that operation use @racket[make-blur-image-filter].

@racketblock[
(with-skia ([mask (make-blur-mask-filter 8)]
            [paint (make-paint #:color "#326DE6" #:mask-filter mask)]
            [surface (make-surface 160 90 #:background 'white)])
  (draw-circle (surface-canvas surface) 80 45 24 paint))
]

@reference-figure["blur-mask-filter.png"
                  "A blue circle with softly blurred coverage around its edge."]


@racketblock[
(with-skia ([surface (make-surface 240 110 #:background 'white)])
  (for ([style '(normal solid outer inner)]
        [x '(35 92 149 206)])
    (with-skia ([mask (make-blur-mask-filter 7 #:style style)]
                [paint (make-paint #:color "#326DE6" #:mask-filter mask)])
      (draw-circle (surface-canvas surface) x 55 20 paint))))
]
@reference-figure["blur-mask-styles-stage8.png"
                  "Four blue circles compare normal, solid, outer, and inner blur-mask styles from left to right."]
}

@(declare-exporting skia skia/effects #:use-sources (skia/effects))

@defproc[(make-table-mask-filter [table bytes?]) mask-filter?]{
Returns a coverage remapping specified by exactly 256 bytes. Entry
@math{i} gives the replacement for input coverage @math{i}, from 0 through
255. The bytes are copied. The table must fit the current byte limit.
Unlike color-filter tables, this constructor does not accept lists or vectors.
}

@defproc[(make-gamma-mask-filter [gamma (and/c real? (>/c 0))]) mask-filter?]{
Returns a coverage remapping using a power curve with the given exponent.
For normalized coverage @math{a}, the ideal curve is @math{a^gamma}; native
quantization applies. Gamma must remain positive after rounding. This changes
coverage, not an image's RGB transfer function or color-space tag.


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([light (make-gamma-mask-filter 0.5)]
              [dark (make-gamma-mask-filter 2.0)]
              [p1 (make-paint #:color "#326DE6" #:mask-filter light)]
              [p2 (make-paint #:color "#326DE6" #:mask-filter dark)])
    (draw-circle canvas 65 50 34 p1)
    (draw-circle canvas 155 50 34 p2))
)
]
@reference-figure["gamma-mask-stage9.png"
                  "Two blue antialiased circles compare gamma 0.5 coverage remapping on the left with gamma 2.0 on the right."]
}

@defproc[(make-clip-mask-filter [low byte?] [high byte?]) mask-filter?]{
Returns a coverage remapping with coverage below the lower threshold mapped
to zero and coverage above the upper threshold mapped to full coverage.
Intermediate coverage is rescaled between the thresholds. The thresholds
must satisfy @math{0 <= low < high <= 255}. This is not a geometric canvas clip.
}

@defproc[(make-shader-mask-filter [shader shader?]) mask-filter?]{
Returns a mask filter using the shader's alpha to modulate shape coverage.
It does not use the shader's RGB as the paint color. The shader is retained;
closing its caller-owned wrapper does not invalidate the filter. A shader
that depends on a GPU context preserves that dependency.
}

@racketblock[
(with-skia ([surface (make-surface 420 125 #:background 'white)]
            [table (make-table-mask-filter
                    (apply bytes (for/list ([coverage (in-range 256)])
                                   (if (< coverage 128) 0 255))))]
            [clipped (make-clip-mask-filter 80 180)]
            [alpha-ramp (make-linear-gradient-shader
                         325 0 390 0 (list (rgba 255 255 255 0) 'white))]
            [shader-mask (make-shader-mask-filter alpha-ramp)]
            [plain (make-paint #:color "#326DE6")]
            [table-paint (make-paint #:color "#326DE6" #:mask-filter table)]
            [clip-paint (make-paint #:color "#326DE6" #:mask-filter clipped)]
            [shader-paint (make-paint #:color "#326DE6" #:mask-filter shader-mask)]
            [font (make-font #:size 11)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (for ([text '("original" "table threshold" "clip 80..180" "shader alpha")]
        [x '(20 114 216 326)])
    (draw-simple-text canvas text x 18 font label))
  (for ([paint (list plain table-paint clip-paint shader-paint)]
        [x '(55.5 155.5 255.5 355.5)])
    (draw-circle canvas x 72.5 27.25 paint)))
]

@reference-figure["mask-filter-coverage.png"
                  "Four fractional-edge blue circles at native device scale: original coverage, a table threshold, clip remapping from 80 through 180, and an alpha-gradient shader mask. The edge and alpha changes are visible against white."]

All four drawings start from the same antialiased circle. These filters remap or modulate
coverage; they do not apply an RGB gamma curve or retag an image's color space.
