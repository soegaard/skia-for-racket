#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/dc))

@title[#:tag "skia-racket-dc"]{Racket Drawing Contexts}

@defmodule[skia/dc #:no-declare]
@(declare-exporting skia/dc #:use-sources (skia/dc))

The @racketmodname[skia/dc] library provides a persistent CPU-raster
implementation of Racket's @racket[draw:dc<%>] interface. Drawing uses Skia, and
text uses the library's Skia/HarfBuzz text path. Requiring the library does not
initialize a GUI or GPU context. Constructing a drawing context allocates a
native Skia raster surface.

The implementation is a compatibility layer with explicit limits, not a claim of
universal byte-for-byte or metric equivalence with Cairo/Pango or every
@racket[draw:dc<%>] consumer. Use @racket[skia-dc-compatibility] for the complete
method/arity declaration and remaining exclusions.

For explicit copying between standalone Draw bitmaps, colors, and paths and
Skia values, use @racketmodname[skia/racket-draw]. It is separate from this
DC implementation and never turns ordinary conversions into live DC adapters.

@local-table-of-contents[#:style 'immediate-only]

@section{Persistent Raster Drawing Context}

@defclass[skia-dc% object% (draw:dc<%>)]{
Implements @racket[draw:dc<%>] with a persistent CPU-raster backing owned by the
creating Racket thread.

@defconstructor[([width exact-positive-integer? 640]
                 [height exact-positive-integer? 480]
                 [backing-scale (and/c real? (>/c 0) (<=/c 3.402823e38)) 1.0]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'unsmoothed])] {
Creates a drawing context with the given logical size and backing scale. Physical
pixel dimensions are the ceilings of the logical dimensions multiplied by
@racket[backing-scale] and must satisfy the ordinary Skia dimension and byte
limits. The backing starts transparent; @racket[background] is the color used by
@method[draw:dc<%> clear].

The context belongs to the creating thread. Futures and other threads cannot use
it. Close it deterministically with @method[skia-dc% close].
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
Returns copied physical RGBA bytes from the root backing. A true
@racket[premultiplied?] requests premultiplied samples. An unfinished alpha group
is not merged for this query.
}

@defmethod[(get-png-bytes) bytes?]{
Returns a PNG encoding of the root backing. An unfinished alpha group is not
implicitly merged.
}

@defmethod[(snapshot) image?]{
Returns an independently owned CPU Skia image of the root backing. The image
remains usable after the drawing context closes and must be closed through the
ordinary Skia resource protocol.
}

@defmethod[(get-capabilities) (and/c hash? immutable?)]{
Returns the same detached wrapper declarations as @racket[skia-dc-capabilities].
The result is not evidence that a native renderer, font, GUI, or GPU operation
has run successfully.
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
the same solid-drawing semantics as the compatibility layer's other bitmap
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

@section{Compatibility Declarations}

@defproc[(skia-dc? [v any/c]) boolean?]{
Returns whether @racket[v] is an instance of @racket[skia-dc%].
}

@defproc[(skia-dc-capabilities) (and/c hash? immutable?)]{
Returns detached declarations for the historical raster-DC capability surface,
including supported drawing families and explicit exclusions. It performs no
native capability probe and does not certify universal drop-in compatibility.
}

@defproc[(skia-dc-compatibility [target (or/c 'raster 'gpu 'pdf 'svg) 'raster])
         (and/c hash? immutable?)]{
Returns the machine-readable compatibility declaration for the selected DC
lifetime and output target. The report enumerates the complete installed
@racket[draw:dc<%>] method set and accepted positional arities, distinguishing
checked no-ops, supported-with-limits operations, and document operations that
require an explicit bounded raster group.

The report is a declaration rather than execution evidence. @racket['raster]
describes the persistent @racket[skia-dc%]; @racket['gpu], @racket['pdf], and
@racket['svg] describe the callback-scoped integrations documented in
@secref["skia-gpu-dc"] and @secref["skia-dc-output"].
}

@section{Unsupported-Operation Exceptions}

@defstruct*[(exn:fail:skia-dc:unsupported exn:fail:contract)
            ([method symbol?]
             [feature symbol?]
             [stage string?])
            #:transparent]{
Represents an operation that is outside the explicit Skia DC compatibility
boundary. The @racket[method] field identifies the attempted operation,
@racket[feature] identifies the unsupported behavior, and @racket[stage]
records the compatibility-boundary description used when the exception was
raised. An unsupported exception is not a successful draw or an implicit Cairo
fallback.
}
