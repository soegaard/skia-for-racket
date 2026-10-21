#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-presentation"]{GPU Presenters and Frames}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

Use the presenter interface when you need to request redraws or inspect the
rendering state of a GPU window. The @seclink["skia-gpu-widgets"]{GPU widgets}
manage presenters for their windows. In a render callback, use the supplied
frame to obtain the current drawing canvas and pixel dimensions; it is the
window's current target, not an offscreen surface to keep for later.

A @deftech{presentation adapter} is the private, platform-specific bridge between
a GUI window and its @tech{GPU backend}. For each frame, it obtains the window's current
drawing target and asks the system to display the completed drawing.

A @deftech{GPU presenter} owns the presentation adapter and @tech{GPU context} for one
window target. A presenter belongs to its creating GUI/eventspace handler thread.
A @deftech{GPU frame} is a short-lived value delivered to the presenter's render
callback. Its @tech{canvas} and context are borrowed only while that callback is live.

Presenters do not expose native framebuffers, drawables, textures, or command
buffers. Successful presentation means that submission and presentation were
requested; it does not certify physical display pixels or performance.

@local-table-of-contents[#:style 'immediate-only]

@section{Presenter State}

@defproc[(gpu-presenter? [v any/c]) boolean?]{
Returns whether @racket[v] is a presenter wrapper. The predicate inspects Racket
state only and does not activate a GPU context.
}

@defproc[(gpu-presenter-backend [presenter gpu-presenter?])
         (or/c 'opengl 'metal 'direct3d)]{
Returns the fixed backend selected by @racket[presenter]. The query requires the
presenter's owner thread but performs no rendering.
}

@defproc[(gpu-presenter-context [presenter gpu-presenter?]) gpu-context?]{
Returns the presenter's owned GPU context on its owner thread. The context can
be used for explicit same-context resources, but must not be closed separately;
the presenter closes it after its children have retired.
}

@defproc[(gpu-presenter-state [presenter gpu-presenter?])
         (or/c 'ready 'rendering 'closing 'closed 'failed)]{
Returns the current Racket-side state. Unlike operations that access the adapter,
this accessor does not activate the context or perform native work.
}

@defproc[(gpu-presenter-info [presenter gpu-presenter?]) (and/c hash? immutable?)]{
Returns a diagnostic snapshot on the presenter's owner thread. It includes the
backend, state, target generation, acquired/presented/skipped/cancelled counts, queued
redraw state, the last frame/error, frame-target cache information, and adapter
diagnostics. Presentation counts are request counts, not observed screen frames.
}

@section{Rendering and Scheduling}

@defproc[(gpu-presenter-render! [presenter gpu-presenter?])
         (or/c 'present-requested 'skipped 'cancelled)]{
Performs one immediate presentation attempt on the presenter owner thread.
Nested presentation, including presentation inside another GPU execution scope,
is rejected. A hidden or zero-sized target, unavailable drawable, or reported
occlusion can produce @racket['skipped]. A close or geometry change during the
callback can produce @racket['cancelled].

At most one target is acquired and the render callback runs at most once. Before
presentation, geometry is measured again; a changed target is cancelled rather
than presented with stale dimensions. Callback errors retire the frame and are
re-raised. Acquisition, submission, presentation, or indeterminate native
cleanup failures can mark the presenter failed instead of silently reusing it.
}

@defproc[(gpu-presenter-request-render! [presenter gpu-presenter?]) void?]{
Marks the presenter dirty and queues a redraw when one is not already queued.
Repeated requests coalesce. A request made during active GPU/presentation work
is deferred until that work unwinds instead of recursively switching contexts.
}

@defproc[(gpu-presenter-set-render! [presenter gpu-presenter?]
                                    [render (-> gpu-frame? any)]) void?]{
Replaces the presenter's render callback and requests one redraw. Call this
function on the presenter's owner thread. Replacement is rejected for a
closing, closed, or failed presenter.

The @racket[render] callback receives one @tech{GPU frame} and runs on the
presenter's owner thread. It must not require keyword arguments and may
return any number of values, which are ignored. Use @racket[gpu-frame-canvas]
to obtain the Skia canvas for drawing.

The frame's canvas and GPU context are borrowed and may be used only during
the callback. Do not close these borrowed resources independently.
}

@section{Presenter Cleanup}

@defproc[(gpu-presenter-close! [presenter gpu-presenter?]) void?]{
Requests closure of the presenter. Call this on the presenter's owning thread.
If a frame is active, presentation is cancelled and cleanup is deferred until
the frame ends. Cached frame-target resources are closed before the adapter
closes its context. If application-owned resources in its GPU context are still
open, closure can fail. The presenter remains in @racket['closing] state; close
those resources and retry closing the presenter.

Repeated close after successful closure is harmless. Finalizer and custodian
fallback only request owner-side cleanup; they do not destroy GUI or GPU objects
from a finalizer thread.
}

@defproc[(gpu-drain-pending-presenters!)
         (listof (and/c hash? immutable?))]{
Attempts pending presenter cleanup owned by the current thread and returns their
diagnostic snapshots. The function rejects calls from inside an active
GPU or presentation frame. It does not drain presenters owned by other threads.
}

@section{Frame Lifetime and Geometry}

@defproc[(gpu-frame? [v any/c]) boolean?]{
Returns whether @racket[v] is a presentation-frame wrapper. Keeping a reference
to a frame does not allow access to its canvas or context after the callback ends.
}

@defproc[(gpu-frame-expired? [frame gpu-frame?]) boolean?]{
Reports whether the callback lease has ended. Expiration is permanent; a later
frame or later activation does not revive the old frame.
}

@defproc[(gpu-frame-canvas [frame gpu-frame?]) canvas?]{
Returns the @tech{borrowed canvas} while @racket[frame] is live on its original owner
thread. It raises an exception after callback exit, from another Racket thread,
or from within a future.
}

@defproc[(gpu-frame-context [frame gpu-frame?]) gpu-context?]{
Returns the presenter's context under the same owning-thread and active-frame checks as
@racket[gpu-frame-canvas]. The returned context is borrowed from the presenter;
do not close it independently.
}

@defproc[(gpu-frame-info [frame gpu-frame?]) (and/c hash? immutable?)]{
Returns an immutable hash table containing physical and logical extents, scale factors,
backend, target generation, frame index, and backend-specific target diagnostics.
This query can also be called after the frame expires.
}

@defproc[(gpu-frame-width [frame gpu-frame?]) exact-positive-integer?]{
Returns the acquired target width in physical pixels.
}

@defproc[(gpu-frame-height [frame gpu-frame?]) exact-positive-integer?]{
Returns the acquired target height in physical pixels.
}

@defproc[(gpu-frame-logical-width [frame gpu-frame?])
         (and/c real? positive?)]{
Returns the logical client width used for this acquired frame.
}

@defproc[(gpu-frame-logical-height [frame gpu-frame?])
         (and/c real? positive?)]{
Returns the logical client height used for this acquired frame.
}

@defproc[(gpu-frame-scale-x [frame gpu-frame?]) (and/c real? positive?)]{
Returns physical width divided by logical width for this frame.
}

@defproc[(gpu-frame-scale-y [frame gpu-frame?]) (and/c real? positive?)]{
Returns physical height divided by logical height for this frame.
}

@defproc[(gpu-frame-generation [frame gpu-frame?]) exact-positive-integer?]{
Returns the presenter's target generation. It changes when target geometry or
identity changes, but is not a native handle or portable cache key.
}

@defproc[(gpu-frame-index [frame gpu-frame?]) exact-positive-integer?]{
Returns the monotonically increasing acquisition index for this presenter.
Cancelled acquired frames still consume an index; skipped acquisitions do not.
}
