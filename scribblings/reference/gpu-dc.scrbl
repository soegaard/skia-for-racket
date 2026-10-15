#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (prefix-in draw: racket/draw)
                     skia skia/gpu skia/gpu-dc))

@title[#:tag "skia-gpu-dc"]{GPU Drawing Contexts}

@defmodule[skia/gpu-dc #:no-declare]
@(declare-exporting skia/gpu-dc #:use-sources (skia/gpu-dc))

The @racketmodname[skia/gpu-dc] module supplies the supported Racket
@racket[draw:dc<%>] drawing subset on Ganesh GPU surfaces. Importing the module
does not initialize a GUI or create a GPU context; native GPU drawing code is
loaded on first use.

A GPU DC is callback-scoped. Every call creates a fresh DC, closes it on every
exit, and permanently expires it when the callback returns. Retaining the Racket
object does not extend the underlying GPU target or reactivate the DC in a later
frame.

@section{Predicates and Capabilities}

@defproc[(skia-gpu-dc? [v any/c]) boolean?]{
Returns whether @racket[v] is a frame-scoped GPU DC. A GPU DC is not an instance
of the separately constructed persistent @racket[skia-dc%] class.
}

@defproc[(skia-gpu-dc-capabilities) (and/c hash? immutable?)]{
Returns detached declarations for GPU DC lifetime, device scaling, GPU alpha
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
          [#:color-space color-space color-space-descriptor? #f]
          [#:sample-count sample-count (integer-in 0 64) 0]
          [#:surface-properties properties surface-properties?
           (make-surface-properties)])
         any]{
Calls @racket[proc] with a fresh GPU drawing context for a live presenter frame
and returns the callback's values. The frame must be live on its owning thread;
its presenter has already activated the correct GPU context, so the callback
must not add another @racket[call-with-gpu-context] scope around this operation.
Nested GPU-DC scopes are rejected.

The callback must be callable with one positional argument. Its DC becomes
invalid on normal return, exception, or escape. The staging target is a
same-context full-color RGBA/BGRA/F16/F32 surface. The detached color-space
descriptor, sample request, and surface-property value form part of the staging
configuration and reuse key.

After successful drawing, a GPU snapshot is copied GPU-to-GPU onto the presenter
frame. The presenter owns submission and presentation. No automatic CPU readback
is part of a normal frame. A failed callback does not commit the staging root to
the frame, and unfinished alpha groups are discarded.
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

Logical dimensions default to the surface's physical dimensions. Independent
X/Y device scales are physical extent divided by logical extent; the DC's
reported backing scale remains 1. A true @racket[clear?] clears the root before
the callback, while false preserves existing root pixels. Pixel persistence does
not imply DC-state persistence: the DC always expires at callback exit.

The borrowed target must use RGBA8888, BGRA8888, F16, or F32 storage so that
transparent alpha intermediates can be represented. Drawing directly into the
same surface concurrently with the callback is unsupported. A user exception
can leave pixels already drawn on the borrowed root; this operation is not a
pixel transaction.

The DC's @tt{snapshot}, @tt{get-rgba-bytes}, and @tt{get-png-bytes} extensions
perform explicit synchronous CPU transfers of the root. They are separate from
ordinary GPU drawing and presentation.
}
