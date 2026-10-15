#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (only-in racket/draw bitmap% color% dc-path%)
                     skia skia/bitmap skia/racket-draw))

@title[#:tag "skia-racket-draw"]{Racket Draw Interoperability}

@defmodule[skia/racket-draw #:no-declare]
@(declare-exporting skia/racket-draw #:use-sources (skia/racket-draw))

The opt-in @racketmodname[skia/racket-draw] module makes explicit, eager
copies between ordinary Racket Draw objects and Skia values. It is not
re-exported by @racketmodname[skia], does not add conversions to existing
operations, and has no native, GUI, GPU, or font initialization merely from
requiring the module. The module deliberately has a small boundary: bitmaps,
colors, and vector paths. It does not provide font, surface, GPU, live-view,
or zero-copy conversion.

Each successful conversion has independent ownership. Closing or mutating a
Skia source after a conversion cannot change the returned Draw value; mutating
a Draw source cannot change the returned Skia value. A caller must still avoid
concurrent mutation during a conversion.

@section{Bitmaps}

@defproc[(bitmap->image
          [bitmap (is-a?/c bitmap%)]
          [#:resolution resolution (or/c 'physical 'logical) 'physical]
          [#:mask mask (or/c 'loaded #f (is-a?/c bitmap%)) 'loaded])
         image?]{
Copies the current public pixels of @racket[bitmap] into a fresh, owned CPU
Skia image. The returned image is ordinary RGBA8888 data with no retained
backing-scale, DPI, file-format, palette, loaded-mask identity, color-profile,
or HDR/float metadata.

With @racket['physical], the default, output dimensions are
@racket[(ceiling (* logical-dimension backing-scale))] and the bitmap is read
with public unscaled readback. With @racket['logical], output dimensions are
the bitmap's logical width and height and Draw performs its ordinary logical
readback. The image itself remembers only those output pixel dimensions. In
particular, importing a 20-by-10 bitmap at scale 2 produces a 40-by-20 image,
and exporting it again with @racket[image->bitmap] does not restore scale 2.

By default, @racket['loaded] applies @method[bitmap% get-loaded-mask] as alpha
coverage. Pass @racket[#:mask #f] to ignore it, or provide a replacement
@racket[bitmap%]. A resolved mask must have matching logical dimensions; it
may use a different backing scale. In physical mode its coverage is sampled at
the source pixel centers. A mask's own loaded mask is not recursively applied.

Source pixels and mask coverage are read as premultiplied public ARGB samples,
then copied to premultiplied RGBA. The mask multiplies all four premultiplied
components. Literal black and white samples from a monochrome bitmap remain
black and white: this operation is a neutral image copy, not a DC stencil draw
with a foreground color. Fully transparent output has zero RGB. There is no
PNG round trip, implicit color transform, or profile inference.

The bitmap and mask must be usable @racket[bitmap%] objects. The bridge checks
dimensions, scales, and a conservative temporary-buffer charge against
@racket[current-skia-byte-limit] before pixel buffers or the image are
allocated. Existing @racket[image->bitmap] and @racket[surface->bitmap]
remain the same bindings and retain their established behavior.
}

The unchanged @racket[image->bitmap] and @racket[surface->bitmap] bindings are
re-exported from @racketmodname[skia/bitmap]. They respectively copy a CPU
image or surface into a new Draw bitmap; their existing contracts and behavior
are unchanged.

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define source (draw:make-bitmap 20 10 #t))
(with-skia ([image (bitmap->image source #:mask #f)])
  (list (image-width image) (image-height image)))
]

At backing scale 1, the final value is @racket['(20 10)]. Passing
@racket[#:mask #f] is useful when the caller needs literal source alpha rather
than the bitmap's loaded-mask coverage.

@section{Colors}

@defproc[(color%->rgba [color (is-a?/c color%)]) rgba?]{
Returns a fresh immutable Skia @racket[rgba] with the Draw color's byte red,
green, and blue components and an alpha byte computed as
@racket[(inexact->exact (round (* 255 alpha)))]. Alpha must be finite and in
the inclusive range from zero through one. This is component copying: it does
not premultiply RGB, resolve a color name, or perform a color-space transform.
}

@defproc[(rgba->color% [color rgba?]) (is-a?/c color%)]{
Returns a fresh mutable Draw @racket[color%] with the same RGB bytes and alpha
@racket[(/ alpha 255.0)]. It does not use the color database or cache a shared
object; mutating the result does not affect another conversion.
}

@section{Paths}

@defproc[(dc-path->skia-path
          [path (is-a?/c dc-path%)]
          [#:fill-style fill-style (or/c 'odd-even 'winding) 'odd-even])
         skia-path?]{
Reads the public Draw path datum once and creates a fresh Skia vector path.
Moves, lines, cubics, closed contours, contour order, and the explicitly
supplied fill style are preserved. Draw's @racket['odd-even] spelling maps to
Skia's @racket['even-odd] rule. The path object does not contain a Draw fill
style, so the default is Draw's usual @racket['odd-even] convention.

Coordinates must be finite Skia drawing scalars. This conversion transfers
only path geometry and the chosen fill interpretation—not a DC transform,
pen, brush, clip, text state, or pixel alignment policy.
}

@defproc[(skia-path->dc-path
          [path skia-path?]
          [#:conic-subdivisions power (or/c #f (integer-in 0 5)) #f])
         (values (is-a?/c dc-path%) (or/c 'odd-even 'winding))]{
Creates a fresh Draw path and returns its required Draw fill style as a second
value. The second value is part of the API because a @racket[dc-path%] stores
geometry but not filling interpretation.

The converter reads raw Skia verbs. Lines and cubics map directly;
quadratics are elevated exactly to cubics apart from ordinary floating-point
roundoff. A weight-one conic is a quadratic. Other rational conics raise by
default because Draw has no rational-quadratic verb. Supply
@racket[#:conic-subdivisions] with an integer from zero through five to request
a bounded vector approximation: each conic is subdivided into at most
@racket[(expt 2 power)] quadratics and then elevated to cubics. The power is
not an error tolerance or a raster fallback.

Draw permits any number of closed subpaths followed by at most one final open
subpath. A Skia path with an open contour followed by another contour cannot
be replayed without silently closing or reordering it, so this procedure raises
instead. It also raises for unsupported path data rather than inventing a clip
for inverse filling. Empty paths and observable degenerate geometry are valid.
}

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define draw-path (new draw:dc-path%))
(send draw-path rectangle 2 2 20 14)

(with-skia ([path (dc-path->skia-path draw-path #:fill-style 'winding)])
  (define-values (copy style) (skia-path->dc-path path))
  (list copy style))
]

The result is a new @racket[dc-path%] and @racket['winding]. To export paths
containing ordinary Skia ellipse or arc conics, choose approximation explicitly:

@racketblock[
(define-values (approximate-path fill-style)
  (skia-path->dc-path ellipse-path #:conic-subdivisions 4))
]

All path snapshots and expansion estimates are bounded by
@racket[current-skia-byte-limit].
