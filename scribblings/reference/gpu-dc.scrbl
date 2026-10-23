#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/gpu skia/gpu-dc))

@title[#:tag "skia-gpu-dc"]{GPU Drawing Contexts}

@defmodule[skia/gpu-dc #:no-declare]
@(declare-exporting skia/gpu-dc #:use-sources (skia/gpu-dc))

Use @racketmodname[skia/gpu-dc] to draw with Racket's @racket[draw:dc<%>] methods
on a presenter frame or an offscreen @tech{GPU surface}. For direct Skia canvas
drawing, no DC adapter is needed. Importing this library does not initialize a
GUI or create a @tech{GPU context}; native GPU drawing code is loaded on first
use.

A @deftech[#:key "GPU drawing context"]{GPU DC} is a callback-scoped implementation
of the supported Racket Draw methods. Each adapter call creates a fresh DC and
closes it when the callback returns, raises an exception, or escapes. Saving
the Racket object does not keep its GPU target alive or make the DC reusable in
a later frame. See @secref["skia-reference-racket-integration"] for the other
DC lifetimes and smoothing defaults.

For a presenter frame, drawing first goes to an intermediate GPU surface and
is then copied onto the frame. This extra GPU-to-GPU copy supports DC features
such as alpha groups. For an existing offscreen surface,
@racket[call-with-gpu-surface-dc] draws into the supplied surface instead.

@section[#:tag "skia-gpu-dc-scaling"]{Logical Size and Pixel Density}

Both GPU adapters keep drawing coordinates in logical units and automatically
scale them to the target's physical pixels. The backing scale is the larger
of the horizontal and vertical pixel-to-logical ratios. The device scales
describe the remaining per-axis factors. Their product with the backing scale
gives each axis's full pixel-to-logical ratio. For example, a DC
with a logical size of 40 by 20 and a physical target of 80 by 60 reports:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Query} @bold{Result} @bold{Meaning})
  (list @method[draw:dc<%> get-size] @elem{40, 20}
        @elem{Width and height in logical drawing units})
  (list @tt{get-pixel-size} @elem{80, 60}
        @elem{Width and height in physical pixels})
  (list @method[draw:dc<%> get-device-scale] @elem{2/3, 1}
        @elem{Remaining horizontal and vertical scaling factors})
  (list @method[draw:dc<%> get-backing-scale] @elem{3}
        @elem{Pixel density sufficient for both axes}))]

For a uniformly scaled 2× target, the backing scale is 2 and both device scales
are 1. Code choosing an intermediate bitmap's density can use
@method[draw:dc<%> get-backing-scale] without undersampling either axis. To map
a logical point to physical pixels, multiply by both the backing scale and the
corresponding device scale. Do not also scale the DC by those factors: drawing
already includes that scaling. The physical allocation size is unchanged.

The DC's @tt{snapshot}, @tt{get-rgba-bytes}, and @tt{get-png-bytes} extensions
copy the surface's pixels to CPU memory and wait for the transfer to finish.
They perform explicit @tech{GPU readback}, unlike ordinary GPU drawing and the
frame's GPU-to-GPU copy. A snapshot returns an independently owned Skia image
that the caller must close.

@section{Predicates and Capabilities}

@defproc[(skia-gpu-dc? [v any/c]) boolean?]{
Returns whether @racket[v] is a callback-scoped GPU DC. A GPU DC is not an instance
of the separately constructed persistent @racket[skia-dc%] class.
}

@defproc[(skia-gpu-dc-capabilities) (and/c hash? immutable?)]{
Returns declarations for GPU DC lifetime, device scaling, GPU alpha
groups, explicit snapshots, and presentation behavior. It performs no native
GPU probe and does not initialize a GUI.
}

@section{Presenter Frames}

@defproc[(call-with-gpu-frame-dc
          [frame gpu-frame?]
          [proc (-> (is-a?/c draw:dc<%>) any)]
          [#:background background (or/c string? (is-a?/c draw:color%)) "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:color-type color-type
           (or/c 'rgba-8888 'bgra-8888 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:color-space color-space (or/c #f 'srgb 'linear-srgb bytes? color-space?) #f]
          [#:sample-count sample-count (integer-in 0 64) 0]
          [#:surface-properties properties surface-properties?
           (make-surface-properties)])
         any]{
Calls @racket[proc] with a fresh GPU drawing context for a live presenter frame
and returns the callback's values.

Drawing uses an intermediate full-color RGBA/BGRA/F16/F32 surface in the same
GPU context. After successful drawing, a GPU snapshot of that surface is copied
GPU-to-GPU onto the presenter frame. This extra copy allows the DC to support
alpha groups even when it cannot draw them directly into the frame. The
intermediate surface can be reused between calls when its dimensions and
configuration match; a new surface is not necessarily allocated for every
frame. No automatic CPU readback is part of a normal frame.

The frame must be live on its owning thread. Its presenter has already
activated the correct GPU context, so the callback
must not add another @racket[call-with-gpu-context] scope around this operation.
Nested GPU-DC scopes are rejected. The presenter owns submission and
presentation.

The DC uses the frame's logical window dimensions and the device scaling
described in @secref["skia-gpu-dc-scaling"]. Do not apply the raw-canvas scaling
example in @secref["skia-gpu-frame-geometry"] to this DC: the scaling is already
in effect. This is also the coordinate behavior of the GUI widgets that use
this operation.

The callback must be a procedure that accepts one positional argument. Its DC becomes
invalid on normal return, exception, or escape. A failed callback does not copy
the intermediate surface to the frame, and unfinished alpha groups are discarded.

The color type, color space, sample request, and
@tech{surface-properties value} configure the intermediate surface. The
@racket[color-space] argument accepts @racket[#f], @racket['srgb],
@racket['linear-srgb], complete ICC bytes, or an open color-space resource,
just as @racket[make-gpu-surface] does. ICC bytes are copied. A supplied resource
remains caller-owned and is copied to a @tech{color-space descriptor} for the
cached configuration; closing it after the call does not invalidate the cache.
See @secref["skia-surface-properties"] for pixel geometry and rendering flags.
}

@section{Borrowed Offscreen Surfaces}

@defproc[(call-with-gpu-surface-dc
          [surface gpu-surface?]
          [proc (-> (is-a?/c draw:dc<%>) any)]
          [#:logical-width logical-width (or/c #f (and/c real? (>/c 0))) #f]
          [#:logical-height logical-height (or/c #f (and/c real? (>/c 0))) #f]
          [#:background background (or/c string? (is-a?/c draw:color%)) "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:clear? clear? boolean? #f])
         any]{
Calls @racket[proc] with a fresh DC borrowing @racket[surface] and returns the
callback's values. The surface must be live in its exact owning
@racket[call-with-gpu-context] activation, and its native canvas save stack must
be balanced. The surface itself is not closed by this operation.

Logical dimensions default to the surface's physical dimensions. Set
@racket[logical-width] and @racket[logical-height] to use a different logical
size; the DC then scales drawing as described in @secref["skia-gpu-dc-scaling"].
A true @racket[clear?] clears the surface before the callback, while false
preserves its existing pixels. Pixel persistence does not imply DC-state
persistence: each call starts with a fresh DC, which expires at callback exit.

The borrowed target must use RGBA8888, BGRA8888, F16, or F32 storage so that
transparent alpha intermediates can be represented. Drawing directly into the
same surface concurrently with the callback is unsupported. A user exception
can leave pixels already drawn on the borrowed surface; this operation does not
roll back those changes.
}
