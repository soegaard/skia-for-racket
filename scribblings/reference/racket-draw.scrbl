#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/bitmap skia/dc skia/pict skia/racket-draw))

@title[#:tag "skia-racket-draw"]{Racket Draw Interoperability}

@defmodule[skia/racket-draw #:no-declare]
@(declare-exporting skia/racket-draw #:use-sources (skia/racket-draw))

The @racketmodname[skia/racket-draw] module copies bitmaps, colors, and paths
between Racket Draw and Skia. Conversions are explicit and eager. The module is
not re-exported by @racketmodname[skia]; require it where bitmap, color, or path
interoperability is needed. Requiring the module does not by itself load the
Skia or HarfBuzz native libraries, create a GPU context, or initialize a GUI.

The bridge converts standalone values rather than drawing contexts. Use
@racketmodname[skia/pict] when a consumer needs a Racket pict, and use
@racketmodname[skia/dc] when a consumer needs an implementation of Racket's
@racket[draw:dc<%>] interface. The functions in this chapter do not create a
live view, share native handles, or provide zero-copy storage.

Successful conversions are detached from their sources. @racket[bitmap->image]
and @racket[dc-path->skia-path] return owned Skia resources, which should be
managed with @racket[with-skia], @racket[call-with-skia-resource], or
@racket[skia-close!]. Conversions in the other direction return ordinary
Racket Draw objects, and @racket[color%->rgba] returns an immutable Skia value;
those results are not Skia resources. Mutation or closure after a conversion
does not change the converted result. The bridge does not make concurrent
mutation of a Racket Draw source safe while a conversion is in progress.

@section{Bitmaps}

@defproc[(bitmap->image
          [bitmap (is-a?/c draw:bitmap%)]
          [#:resolution resolution (or/c 'physical 'logical) 'physical]
          [#:mask mask (or/c 'loaded #f (is-a?/c draw:bitmap%)) 'loaded])
         image?]{
Returns an owned, CPU-resident, untagged Skia image containing a snapshot of
the public pixels of @racket[bitmap]. The source bitmap is not retained.

The @racket[resolution] argument determines the copied pixel dimensions. With
@racket['physical], the default, each dimension is the ceiling of the bitmap's
logical dimension multiplied by its backing scale, and the bridge requests
unscaled pixel readback. With @racket['logical], the output dimensions are the
bitmap's logical width and height and the bridge requests Racket Draw's
logical-size readback. The returned image records only the resulting pixel
dimensions. It retains no backing scale, DPI, encoded format, palette,
loaded-mask identity, color profile, or floating-point/HDR representation.

The @racket[mask] argument controls additional alpha coverage. The default
@racket['loaded] uses @method[draw:bitmap% get-loaded-mask] when one is present.
A false value ignores the loaded mask, and a supplied @racket[draw:bitmap%]
replaces it. A resolved mask must be usable and must have the same logical
dimensions as the source bitmap. Its own loaded mask is not applied
recursively. In physical mode, the bridge chooses the nearest mask pixel for each
source-pixel center, accounting for differing backing scales.

Pixel readback uses premultiplied ARGB samples. The bridge reorders them to
premultiplied RGBA and multiplies every premultiplied component by the resolved
mask coverage. Invalid premultiplied source samples, where an RGB component
exceeds alpha, raise an exception. Fully transparent output has zero RGB.
Monochrome black and white samples remain literal black and white; this is a
pixel copy, not the foreground/background stencil behavior of a bitmap draw.

No PNG encoding, color-space conversion, or profile inference occurs. The
result is created with no Skia color-space tag. The selected source and mask
dimensions must satisfy the ordinary Skia image limits. Before allocating the
bridge buffers, the function also requires a conservative charge of 12 bytes
per output pixel plus 4 bytes per mask pixel, when a mask is used, to fit
@racket[current-skia-byte-limit]. That charge is an admission check for bridge
storage, not a bound on all memory used internally by Racket Draw or Skia.
Readback or native image-construction failure raises without returning a
partial image.
}

The @racket[image->bitmap] and @racket[surface->bitmap] functions are
re-exported unchanged from @racketmodname[skia/bitmap]. They copy CPU Skia
pixels into independent Racket Draw bitmaps and retain the contracts documented
in @secref["skia-image-operations"]. They are reverse-direction pixel copies,
not metadata-preserving inverses of @racket[bitmap->image].

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define source (draw:make-bitmap 20 10 #t))
(with-skia ([image (bitmap->image source #:mask #f)])
  (list (image-width image) (image-height image)))
]

For a bitmap with backing scale 1, the result is @racket['(20 10)].

@section{Colors}

The color conversions copy channel values only. They do not use the Racket
color database, premultiply RGB, or perform color-space conversion.

@defproc[(color%->rgba [color (is-a?/c draw:color%)]) rgba?]{
Returns an immutable @racket[rgba] value with the red, green, and blue bytes
reported by @racket[color]. The Draw alpha value must be finite and in the
inclusive range from 0 through 1. The returned alpha byte is
@racket[(inexact->exact (round (* 255 alpha)))].

An exception is raised if the object reports a non-byte RGB component or an
invalid alpha value. No Draw object or native Skia resource is retained.
}

@defproc[(rgba->color% [color rgba?]) (is-a?/c draw:color%)]{
Returns a fresh Racket Draw @racket[draw:color%] with the same RGB bytes and
alpha @racket[(/ (rgba-alpha color) 255.0)]. The result is independent of the
input value and is not a Skia resource.
}

@section{Paths}

Path conversion copies geometry. It does not copy a drawing-context transform,
clip, pen, brush, text state, or pixel-alignment policy. Racket Draw stores the
fill interpretation separately from @racket[draw:dc-path%], so the bridge makes
that distinction explicit in both directions.

@defproc[(dc-path->skia-path
          [path (is-a?/c draw:dc-path%)]
          [#:fill-style fill-style (or/c 'odd-even 'winding) 'odd-even])
         skia-path?]{
Returns an independently owned Skia path built from the public geometry of
@racket[path]. The bridge copies moves, lines, cubic Bézier segments, closed
subpaths, and a possible final open subpath. Later mutation of the Draw path
does not change the result.

The @racket[fill-style] argument supplies the interpretation that a Draw
drawing operation would otherwise receive separately. @racket['odd-even] maps
to Skia's @racket['even-odd] fill rule, and @racket['winding] maps to
@racket['winding]. The default is @racket['odd-even]; callers that intend to
draw the source with winding fill should pass @racket['winding] explicitly.

Coordinates must be finite values in the Skia drawing-scalar range. Invalid
public path data or an allocation/native construction failure raises rather
than returning a partial path.
}

@defproc[(skia-path->dc-path
          [path skia-path?]
          [#:conic-subdivisions power (or/c #f (integer-in 0 5)) #f])
         (values (is-a?/c draw:dc-path%) (or/c 'odd-even 'winding))]{
Returns two detached values: a fresh Racket Draw @racket[draw:dc-path%] and the
Draw fill style required to preserve the Skia path's fill rule. The source path
must be live and accessed on its owning Racket thread. The returned Draw path has no
Skia resource lifetime.

Moves, lines, cubic Bézier segments, and close operations map directly.
Quadratic Bézier segments are degree-elevated to cubics without geometric
approximation, although ordinary numeric roundoff can change coordinates. A
conic with weight 1 is handled as a quadratic. Other rational conics have no
direct @racket[draw:dc-path%] representation and therefore raise by default.

The @racket[power] argument requests an explicit vector approximation for
non-unit conics. Its value ranges from zero through five. A conic is subdivided
into at most @racket[(expt 2 power)] quadratic segments, and each resulting
quadratic is then degree-elevated to a cubic. The subdivision power is a bound
on expansion, not a geometric-error tolerance and not a raster fallback.

Racket Draw permits any number of closed subpaths followed by at most one final
open subpath. A Skia path containing an open contour followed by another
contour cannot be represented without closing or reordering geometry, so the
function raises instead. Empty paths are accepted.

Both path directions apply a conservative 64-byte charge per copied or
predicted output command against @racket[current-skia-byte-limit]. For Skia
conics, the prediction includes the requested subdivision expansion. A failure
during validation or conversion raises without publishing a partially converted
path.
}

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(define draw-path (new draw:dc-path%))
(send draw-path rectangle 2 2 20 14)

(with-skia ([path (dc-path->skia-path draw-path #:fill-style 'winding)])
  (define-values (copy fill-style)
    (skia-path->dc-path path))
  (list (is-a? copy draw:dc-path%) fill-style))
]

The result is @racket['(#t winding)]. Rational conics require an explicit
approximation policy:

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/racket-draw)

(with-skia ([path (make-path '((move 0 0) (conic 10 20 20 0 0.5)))])
  (define-values (copy fill-style)
    (skia-path->dc-path path #:conic-subdivisions 4))
  (list (is-a? copy draw:dc-path%) fill-style))
]

The second example returns @racket['(#t winding)] after converting the conic to
a bounded sequence of cubic Bézier segments.
