#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/effects))

@title[#:tag "skia-path-effects"]{Path Effects and Mask Filters}

@(declare-exporting skia)

A @deftech{path effect} changes the geometry used for drawing without mutating
its input path. A @deftech{mask filter} changes the coverage of a shape rather
than the colors inside an image. Attach them with @racket[make-paint],
@racket[paint-set-path-effect!], or @racket[paint-set-mask-filter!].

The constructors return owned resources. A paint or composed effect retains
its own native references to its inputs; it does not take ownership of the
caller's wrappers. Inputs must be open on the appropriate owning thread when
used. GPU-dependent inputs retain their context restrictions. Native rejection
raises an exception. Numeric arguments must also be @tech{drawing scalar}s.

@section{Path Effects}

@defproc[(path-effect? [v any/c]) boolean?]{
Returns @racket[#t] for a path-effect resource and @racket[#f] otherwise.
The predicate remains true after the resource is closed.
}

@defproc[(make-dash-path-effect [intervals (or/c list? vector?)] [phase real? 0]) path-effect?]{
Returns an effect that alternates drawn and skipped distances along a stroke.
The first interval is drawn, the second is skipped, and the pattern repeats.
Intervals are nonnegative drawing scalars in a list or vector of even length,
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

Closing the caller's dash wrapper does not remove the paint's retained effect.
}

@defproc[(make-corner-path-effect [radius (and/c real? (>/c 0))]) path-effect?]{
Returns an effect that replaces sharp path corners with rounded transitions
of the requested radius. The input path is unchanged. The radius is measured
in local drawing units and must remain positive at native precision; native
rejection raises an exception.
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
}

@defproc[(make-compose-path-effect [outer path-effect?] [inner path-effect?]) path-effect?]{
Returns an effect that applies @racket[inner] first, then @racket[outer].
The result retains both effects; closing either input wrapper does not
invalidate the result. Composition is not generally commutative.
}

@defproc[(make-sum-path-effect [first path-effect?] [second path-effect?]) path-effect?]{
Returns an effect that applies both effects to the original geometry and
combines the resulting paths. Unlike composition, neither effect receives
the other's output. Both input effects are retained.
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
