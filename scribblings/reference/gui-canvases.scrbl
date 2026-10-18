#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract racket/gui/base
                     (prefix-in draw: racket/draw)
                     skia/canvas skia/gpu skia/gpu-gui skia/gpu-canvas))

@title[#:tag "skia-gui-canvases"]{GUI Drawing Canvases}

These GUI classes present Skia drawing through Racket @racket[canvas%] widgets.
The raster canvas reuses one CPU drawing context across repaints; the GPU canvas
creates a fresh @tech[#:key "GPU drawing context"]{drawing context} for each
@tech{GPU frame}. Both belong to their
eventspace handler thread, but their pixel and drawing-context lifetimes differ.

@local-table-of-contents[#:style 'immediate-only]

@section{Persistent Raster Canvas}

@defmodule[skia/canvas #:no-declare]
@(declare-exporting skia/canvas #:use-sources (skia/canvas))

@defclass[skia-canvas% canvas% ()]{
Implements a GUI canvas with one persistent CPU-raster Skia drawing context and
a bitmap presentation bridge. Construction, painting, presentation, resize, and
closure belong to the eventspace handler thread.

@defconstructor[([parent (is-a?/c area-container<%>)]
                 [style (listof symbol?) '()]
                 [paint-callback procedure? void]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'unsmoothed]
                 [label (or/c #f string?) #f]
                 [enabled boolean? #t]
                 [vert-margin exact-nonnegative-integer? 0]
                 [horiz-margin exact-nonnegative-integer? 0]
                 [min-width exact-nonnegative-integer? 1]
                 [min-height exact-nonnegative-integer? 1]
                 [stretchable-width boolean? #t]
                 [stretchable-height boolean? #t])]{
Creates a persistent raster canvas. The @racket[paint-callback] function must
accept the canvas and its drawing context and may not require keyword arguments.
Supported style flags are @racket['border], @racket['control-border],
@racket['no-focus], @racket['deleted], and @racket['no-autoclear].
}

The same drawing-context object and drawing settings are kept across repaints and
resizing. Resizing the pixel buffer replaces its contents.
The @racket['no-autoclear] style suppresses automatic clearing of the pixel buffer;
it does not preserve pixels when that buffer is replaced. The final GUI copy is a CPU pixel
transfer, not GPU rendering or zero-copy presentation.

@defmethod[#:mode override (get-dc) object?]{
Returns the persistent Skia drawing context after widget initialization.
}

@defmethod[#:mode override (refresh) void?]{
Requests a coalesced repaint.
}

@defmethod[#:mode override
           (refresh-now [proc (or/c #f procedure?) #f]
                        [#:flush? flush? boolean? #t])
           void?]{
Performs a synchronous repaint. When supplied, @racket[proc] receives the
persistent drawing context for this invocation.
}

@defmethod[(present) void?]{
Copies the current raster backing to the GUI without running the paint callback.
}

@defmethod[(check-skia-geometry) void?]{
Checks the widget's current backing geometry and resizes the private raster
storage when needed.
}

@defmethod[(get-skia-info) (and/c hash? immutable?)]{
Returns lifetime, geometry, and paint/presentation diagnostics.
}

@defmethod[(closed?) boolean?]{
Returns whether the Skia rendering resources have been closed.
}

@defmethod[(close-skia) void?]{
Closes the owned rendering and presentation resources. The method is rejected
during an active paint or presentation operation and is otherwise idempotent.
}

@defmethod[(close) void?]{
Closes the same resources as @method[skia-canvas% close-skia].
}
}

@defproc[(skia-canvas? [v any/c]) boolean?]{
Returns whether @racket[v] is an instance of @racket[skia-canvas%].
}

@section{Frame-Scoped GPU Canvas}

@defmodule[skia/gpu-canvas #:no-declare]
@(declare-exporting skia/gpu-canvas #:use-sources (skia/gpu-canvas))

@defclass[skia-gpu-canvas% gpu-canvas% ()]{
Adapts each presenter frame to a frame-scoped Skia drawing context. Unlike
@racket[skia-canvas%], the drawing context exists only during one frame callback;
retaining it does not extend its lifetime.

@defconstructor[([parent (is-a?/c area-container<%>)]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f exact-nonnegative-integer?) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [paint-callback procedure? void]
                 [on-error procedure? raise]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
                 [automatic? boolean? #t]
                 [min-width exact-nonnegative-integer? 1]
                 [min-height exact-nonnegative-integer? 1])]{
Creates a GPU drawing-context canvas. The paint callback receives the canvas and
a fresh frame-scoped drawing context.
}

@defmethod[#:mode override (get-dc) object?]{
Returns the active frame's drawing context only while a paint callback is live.
It raises outside that scope.
}

@defmethod[#:mode override (refresh) void?]{
Requests a GPU frame through the inherited presenter scheduler.
}

@defmethod[#:mode override
           (refresh-now [proc (or/c #f procedure?) #f]
                        [#:flush? flush? boolean? #t])
           void?]{
Performs synchronous GPU drawing. A false @racket[flush?] is unsupported because
there is no persistent unpresented frame.
}

@defmethod[(present) void?]{
Raises an unsupported-operation exception instead of redisplaying cached GPU
pixels. Request a frame with @method[skia-gpu-canvas% refresh] instead.
}

@defmethod[(close-skia) void?]{
Closes the GPU canvas using @racket[gpu-presenter-close!], with the same
owning-thread, deferred-cleanup, and cleanup-retry rules.
}

@defmethod[(close) void?]{
Closes the same resources as @method[skia-gpu-canvas% close-skia].
}

@defmethod[(skia-closed?) boolean?]{
Returns the wrapper's closed state.
}

@defmethod[(get-skia-info) (and/c hash? immutable?)]{
Returns frame and lifetime diagnostics. The result states explicitly
that implicit CPU readback and visible-pixel verification have not occurred.
}
}

@defproc[(skia-gpu-canvas? [v any/c]) boolean?]{
Returns whether @racket[v] is an instance of @racket[skia-gpu-canvas%].
}

@section{GPU Drawing-Context Window}

@(declare-exporting skia/gpu-canvas #:use-sources (skia/gpu-canvas))

@defclass[skia-gpu-window% frame% ()]{
Provides a convenience frame around one @racket[skia-gpu-canvas%].

@defconstructor[([label string? "Skia GPU DC"]
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f exact-nonnegative-integer?) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [paint-callback procedure? void]
                 [on-error procedure? raise]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
                 [automatic? boolean? #t])]{
Creates a GPU drawing-context window.
}

@defmethod[(get-skia-canvas) (is-a?/c skia-gpu-canvas%)]{
Returns the child canvas.
}

@defmethod[(get-gpu-presenter) gpu-presenter?]{
Returns the child's presenter.
}

@defmethod[(close-skia) void?]{
Closes the GPU canvas before hiding the window. Window-manager close uses the
same path.
}
}
