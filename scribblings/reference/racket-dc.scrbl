#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/dc))

@title[#:tag "skia-racket-dc"]{Racket Drawing Contexts}

@defmodule[skia/dc #:no-declare]
@(declare-exporting skia/dc #:use-sources (skia/dc))

Use @racketmodname[skia/dc] when code written for Racket's @racket[draw:dc<%>]
interface needs a CPU pixel buffer that survives between drawing calls. It
provides a persistent CPU-raster implementation of that interface, using Skia
for drawing and Skia/HarfBuzz for text. No window or GPU context is needed.
Constructing a drawing context allocates a native Skia raster surface; merely
requiring the library does not.

Use @racket[call-with-skia-dc] when all drawing fits in one callback and the DC
should be closed automatically. Construct @racket[skia-dc%] directly when the
context must remain available between separate calls.

For PDF or SVG output, use @racketmodname[skia/dc-output]; for a GPU target, use
@racketmodname[skia/gpu-dc]. Those adapters supply callback-scoped DCs instead
of a persistent context. See @secref["skia-reference-racket-integration"] for
their lifetime and smoothing differences, and @racket[skia-dc-compatibility]
for supported methods and restrictions.

For explicit copying between standalone Draw bitmaps, colors, and paths and
Skia values, use @racketmodname[skia/racket-draw]. It is separate from this
DC implementation: copying a value does not create a drawing context.

@local-table-of-contents[#:style 'immediate-only]

@section{Persistent Raster Drawing Context}

@defclass[skia-dc% object% (draw:dc<%>)]{
Implements @racket[draw:dc<%>] with a persistent CPU pixel buffer owned by the
creating Racket thread.

@defconstructor[([width exact-positive-integer? 640]
                 [height exact-positive-integer? 480]
                 [backing-scale (and/c real? (>/c 0) (<=/c 3.402823e38)) 1.0]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed])] {
Creates a drawing context with the given logical size and backing scale. Physical
pixel dimensions are the ceilings of the logical dimensions multiplied by
@racket[backing-scale] and must satisfy the ordinary Skia dimension and byte
limits. The pixel buffer starts transparent; @racket[background] is the color used by
@method[draw:dc<%> clear].

Smoothing defaults to @racket['smoothed], as it does for the output, GPU, and GUI
DC adapters. Select @racket['unsmoothed] or @racket['aligned] explicitly when needed.

The context belongs to the creating thread. Futures and other threads cannot use
it. The caller must close it with @method[skia-dc% close], including when drawing
raises an exception. @racket[call-with-skia-dc] manages this cleanup for a
callback, as shown in the snapshot example below.
}

The inherited @racket[draw:dc<%>] operations cover drawing state, affine
transforms, clipping regions, ordinary geometry, text, bitmaps, copying,
recorded drawing, and nested alpha groups within the compatibility boundary
reported by @racket[skia-dc-compatibility]. Document lifecycle and flush methods
are checked raster no-ops; they do not create a document or presentation queue.

@defmethod[(close) void?]{
Closes the owned raster backing and releases selected pen, brush, and region
locks. The operation is idempotent on the owner thread. Unfinished alpha groups
are discarded rather than implicitly composited. Other drawing, state,
measurement, and output methods reject a closed context.
}

@defmethod[(get-pixel-size) (values exact-positive-integer? exact-positive-integer?)]{
Returns the physical pixel width and height. These can differ from the logical
values returned by the inherited @method[draw:dc<%> get-size] when the backing
scale is not 1.
}

@defmethod[(get-rgba-bytes [#:premultiplied? premultiplied? boolean? #f]) bytes?]{
Returns copied physical RGBA bytes from the drawing context's main pixel buffer. A true
@racket[premultiplied?] requests premultiplied samples. An unfinished alpha group
is not merged for this query.
}

@defmethod[(get-png-bytes) bytes?]{
Returns a PNG encoding of the drawing context's main pixel buffer. An unfinished
alpha group is not implicitly merged.
}

@defmethod[(snapshot) image?]{
Captures the drawing context's main pixel buffer as a Skia image.

The image is stored in CPU memory and is independently owned. It remains usable
after the drawing context closes and must be closed through the ordinary Skia
resource protocol.

This complete headless example uses ordinary Racket Draw methods and takes an
owned snapshot before the scoped DC closes. No window, event
loop, or GUI canvas is involved.

@racketblock[
(require racket/class
         (prefix-in draw: racket/draw)
         skia skia/dc)

(define white (make-object draw:color% 255 255 255))
(define navy (make-object draw:color% 32 52 78))
(define panel (make-object draw:color% 232 238 249))
(define orange (make-object draw:color% 239 160 43))
(define blue (make-object draw:color% 50 109 230))
(define snapshot
  (call-with-skia-dc
   180 105
   (lambda (dc)
     (send dc clear)
     (send dc set-pen navy 2 'solid)
     (send dc set-brush panel 'solid)
     (send dc draw-rounded-rectangle 8 8 164 88 12)
     (send dc set-brush orange 'solid)
     (send dc draw-ellipse 25 35 48 38)
     (send dc set-pen blue 3 'solid)
     (send dc draw-line 92 75 154 30)
     (send dc set-text-foreground navy)
     (send dc draw-text "headless DC" 24 18)
     (send dc snapshot))
   #:background white))
(with-skia ([image snapshot])
  (list (image-width image) (image-height image)))
]
@reference-figure["skia-dc-headless-snapshot.png"
                  "A headless persistent Skia drawing context produces a pale rounded panel, orange ellipse, blue line, and text; the displayed image is its owned snapshot after the DC closes."]
}

@defmethod[(get-capabilities) (and/c hash? immutable?)]{
Returns the same support and limitation information as
@racket[skia-dc-capabilities].
}

@defmethod[(draw-bitmap-section-smooth
            [bitmap (is-a?/c draw:bitmap%)] [x real?] [y real?]
            [dest-width (and/c real? (>=/c 0))]
            [dest-height (and/c real? (>=/c 0))]
            [src-x real?] [src-y real?]
            [src-width (and/c real? (>=/c 0))]
            [src-height (and/c real? (>=/c 0))]
            [style (or/c 'solid 'opaque 'xor) 'solid]
            [color (is-a?/c draw:color%) (make-object draw:color% 0 0 0)]
            [mask (or/c #f (is-a?/c draw:bitmap%)) #f]) boolean?]{
Draws a bitmap subsection with linear sampling while preserving the caller's
smoothing setting. It follows the same copied-pixel, mask, and source-rectangle
rules as the ordinary bitmap methods. The legacy @racket['xor] bitmap style has
the same solid-drawing behavior as the compatibility layer's other bitmap
methods; it is not a bitwise XOR operation.
}

@defmethod[(get-path-bounding-box [path (is-a?/c draw:dc-path%)]
                                  [kind (or/c 'path 'fill 'stroke)])
           (values real? real? real? real?)]{
Returns geometric bounds for the path, fill, or current-pen stroke. The query
uses the current affine transform and alignment rules but not the current clip
or brush/stipple source.
}
}

@section{Scoped Raster Drawing}

@defproc[(call-with-skia-dc
          [width exact-positive-integer?] [height exact-positive-integer?]
          [proc (-> (is-a?/c draw:dc<%>) any)]
          [#:backing-scale backing-scale (and/c real? (>/c 0) (<=/c 3.402823e38)) 1.0]
          [#:background background (or/c string? (is-a?/c draw:color%)) "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed])
         any]{
Creates a raster drawing context, calls @racket[proc] with it, and returns the
callback's values. Dimensions, backing scale, background, smoothing, and
allocation limits follow the @racket[skia-dc%] constructor.

The callback must accept one positional argument without required keywords.
The DC is closed when the callback returns, raises an exception, or escapes;
it cannot be saved for later drawing or reentered through a continuation.
Snapshots taken during the callback are independently owned images and remain
usable after the DC closes. The caller must close those images separately.
}

@section{Compatibility Declarations}

@defproc[(skia-dc? [v any/c]) boolean?]{
Returns whether @racket[v] is an instance of @racket[skia-dc%].
}

@defproc[(skia-dc-capabilities) (and/c hash? immutable?)]{
Returns the library's declared support for raster drawing operations, including
its limitations. This describes the implementation; it does not test whether
native drawing is available on the current system.
}

@defproc[(skia-dc-compatibility [target (or/c 'raster 'gpu 'pdf 'svg) 'raster])
         (and/c hash? immutable?)]{
Returns a hash table describing support for the selected output target. It lists
the installed @racket[draw:dc<%>] methods and the number of positional arguments
each accepts. It distinguishes methods that validate their arguments but do
nothing, operations with restrictions, and document operations that require an
explicit bounded raster group.

The @racket['raster] report describes the persistent @racket[skia-dc%];
@racket['gpu], @racket['pdf], and
@racket['svg] describe the callback-scoped integrations documented in
@secref["skia-gpu-dc"] and @secref["skia-dc-output"].
}

@section{Unsupported-Operation Exceptions}

@defstruct*[(exn:fail:skia-dc:unsupported exn:fail:unsupported)
            ([method symbol?]
             [feature symbol?]
             [stage string?])
            #:transparent]{
Raised when a Skia drawing context does not support the requested operation or
feature. The @racket[method] field identifies the attempted operation,
@racket[feature] identifies the unsupported behavior, and @racket[stage]
describes where the restriction was encountered. The operation raises this
exception instead of silently drawing nothing or switching to Cairo.
It satisfies @racket[exn:fail:unsupported?], not @racket[exn:fail:contract?].
}
