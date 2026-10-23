#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract racket/gui/base
                     (prefix-in draw: racket/draw)
                     skia/canvas skia/gpu skia/gpu-gui skia/gpu-canvas
                     skia/render-canvas))

@title[#:tag "skia-gui-canvases"]{GUI Canvases with Racket Drawing Contexts}

Use these classes when your drawing code uses methods from Racket's
@racket[draw:dc<%>] interface, such as @method[draw:dc<%> draw-ellipse]. The
paint callback receives the GUI canvas widget and a Skia-backed drawing
context implementing the documented drawing subset of that interface.

Choose @racket[skia-canvas%] for CPU rendering with a drawing context that
persists between repaints. Choose @racket[skia-canvas-on-gpu%] for GPU rendering;
it creates a fresh @tech[#:key "GPU drawing context"]{drawing context} for
each @tech{GPU frame}, valid only during the paint callback. Both widgets
belong to their eventspace handler thread, and their pixel and drawing-context
lifetimes differ as described below.

The @racket[skia-canvas-on-gpu%] class is the GPU counterpart of
@racket[skia-canvas%] in this drawing-context interface. It subclasses
@racket[gpu-canvas%], using the same GPU presentation machinery but supplying
a Racket drawing context instead of a GPU frame to the application callback.
Both GPU classes use Skia. To draw directly with Skia's drawing functions instead, see
@secref["skia-gpu-widgets"].

Both drawing-context interfaces use logical window coordinates and apply the
window's logical-to-pixel scaling automatically. Do not apply the raw-frame
scaling example from @secref["skia-gpu-frame-geometry"] to these drawing
contexts.

The initial smoothing defaults differ: @racket[skia-canvas%] uses
@racket['unsmoothed], while @racket[skia-canvas-on-gpu%] and
@racket[make-skia-render-canvas] use @racket['smoothed]. Pass an explicit
@racket[smoothing] value when choosing the same setting across interfaces.
The unified factory passes that setting to either renderer. For automatic
GPU backend choices and Direct3D-only options, see
@secref["skia-gui-backend-options"].

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

@defclass[skia-canvas-on-gpu% gpu-canvas% ()]{
Adapts each presenter frame to a frame-scoped Skia drawing context. Unlike
@racket[skia-canvas%], the drawing context exists only during one frame callback;
retaining it does not extend its lifetime.

@defconstructor[([parent (is-a?/c area-container<%>)]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f (integer-in 0 4294967294)) #f]
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

The backend and Direct3D-only options follow
@secref["skia-gui-backend-options"]. This constructor does not accept the
@racket[style] argument supported by @racket[skia-canvas%].
}

@defmethod[#:mode override (get-dc) object?]{
Returns the active frame's drawing context while a paint callback is running.
Calling this method when no paint callback is running raises an exception.
}

@defmethod[#:mode override (refresh) void?]{
Requests a GPU frame through the inherited presenter scheduler.
}

@defmethod[#:mode override
           (refresh-now [proc (or/c #f procedure?) #f]
                        [#:flush? flush? boolean? #t])
           void?]{
Performs synchronous GPU drawing. Passing @racket[#f] for @racket[flush?]
raises an unsupported-operation exception because there is no persistent
unpresented frame.
}

@defmethod[(present) void?]{
Raises an unsupported-operation exception instead of redisplaying cached GPU
pixels. Request a frame with @method[skia-canvas-on-gpu% refresh] instead.
}

@defmethod[(close-skia) void?]{
Closes the GPU canvas using @racket[gpu-presenter-close!], with the same
owning-thread, deferred-cleanup, and cleanup-retry rules.
}

@defmethod[(close) void?]{
Closes the same resources as @method[skia-canvas-on-gpu% close-skia].
}

@defmethod[(skia-closed?) boolean?]{
Returns whether closure of the widget has been requested. The flag becomes
true before presenter cleanup completes and can remain true after a cleanup
exception. It is not evidence that all native resources have been released;
see @secref["skia-gui-cleanup"].
}

@defmethod[(get-skia-info) (and/c hash? immutable?)]{
Returns frame and lifetime diagnostics. The result states explicitly
that implicit CPU readback and visible-pixel verification have not occurred.
}
}

@defproc[(skia-canvas-on-gpu? [v any/c]) boolean?]{
Returns whether @racket[v] is an instance of @racket[skia-canvas-on-gpu%].
}

@section{GPU Drawing-Context Window}

@(declare-exporting skia/gpu-canvas #:use-sources (skia/gpu-canvas))

@defclass[skia-window-on-gpu% frame% ()]{
Provides a convenience frame around one @racket[skia-canvas-on-gpu%].

@defconstructor[([label string? "Skia GPU DC"]
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f (integer-in 0 4294967294)) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [paint-callback procedure? void]
                 [on-error procedure? raise]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
                 [automatic? boolean? #t])]{
Creates a GPU drawing-context window using the same backend, smoothing, and
callback rules as @racket[skia-canvas-on-gpu%].
}

@defmethod[(get-skia-canvas) (is-a?/c skia-canvas-on-gpu%)]{
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

@section[#:tag "skia-gui-cleanup"]{Closing GUI Rendering Resources}

Close a widget's rendering resources on its eventspace handler thread using
the method for that interface:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Interface} @bold{Close method} @bold{State query})
  (list @racket[gpu-canvas%] @method[gpu-canvas% close-gpu]
        @elem{@racket[gpu-presenter-state] on its presenter})
  (list @racket[skia-canvas%] @method[skia-canvas% close-skia]
        @method[skia-canvas% closed?])
  (list @racket[skia-canvas-on-gpu%] @method[skia-canvas-on-gpu% close-skia]
        @method[skia-canvas-on-gpu% skia-closed?])
  (list @racket[skia-render-canvas<%>] @method[skia-render-canvas<%> close-skia]
        @method[skia-render-canvas<%> closed?]))]

The drawing-context canvases also provide @tt{close} as an alias for
@tt{close-skia}. Convenience windows use @method[gpu-window% close-gpu],
@method[skia-window-on-gpu% close-skia], or
@method[skia-render-window% close-render], respectively, to close their child
canvas and hide the window. Hiding a window alone does not close its rendering
resources. Stop application-owned animation timers when closing the widget.

For a GPU widget, stopping further rendering and finishing native cleanup are
separate steps. A close during a raw GPU frame can defer cleanup until the
frame ends; open application-owned GPU resources can make cleanup fail.
Close those resources according to their context's rules, then retry the
widget's close method. The GPU drawing-context widget's closed flag, also
used by the unified GPU canvas, can already be true in this situation.
Use @racket[gpu-presenter-state] to inspect presenter closure; the unified
interface's @method[skia-render-canvas<%> get-render-info] additionally reports
the outcome of its close attempt in @racket['close_status].

The raster and unified interfaces reject closure during their paint
callbacks. The raw GPU and GPU drawing-context interfaces instead use the
presenter's deferred-cleanup rules. These differences do not permit closing
a borrowed frame canvas or the presenter's context independently. For the
resource-level cleanup functions, see @secref["skia-resource-cleanup"].
