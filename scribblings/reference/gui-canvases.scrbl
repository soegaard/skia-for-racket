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

All GUI drawing-context constructors initially use @racket['smoothed]. Pass
@racket['unsmoothed] or @racket['aligned] explicitly when needed. The unified
factory passes the setting to either renderer. For automatic
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
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
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

@defmethod[(close) void?]{
Closes the owned rendering and presentation resources. The method is rejected
during an active paint or presentation operation and is otherwise idempotent.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the cleanup state described in @secref["skia-gui-cleanup"].
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
                 [style (listof symbol?) '()]
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
@secref["skia-gui-backend-options"]. The @racket[style] argument accepts
@racket['border], @racket['control-border], @racket['no-focus], and
@racket['deleted], as in @racket[gpu-canvas%]. It does not accept the raster
canvas's @racket['no-autoclear] flag.
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

@defmethod[(close) void?]{
Closes the GPU canvas using @racket[gpu-presenter-close!], with the same
owning-thread, deferred-cleanup, and cleanup-retry rules.
}

@defmethod[(closed?) boolean?]{
Returns whether rendering-resource cleanup has completed successfully.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the cleanup state, including deferred cleanup outcomes, as described
in @secref["skia-gui-cleanup"].
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
                 [canvas-style (listof symbol?) '()]
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
The @racket[canvas-style] argument supplies its child canvas's style flags.
}

@defmethod[(get-skia-canvas) (is-a?/c skia-canvas-on-gpu%)]{
Returns the child canvas.
}

@defmethod[(get-gpu-presenter) gpu-presenter?]{
Returns the child's presenter.
}

@defmethod[(close) void?]{
Closes the GPU canvas before hiding the window. Window-manager close uses the
same path.
}

@defmethod[(closed?) boolean?]{
Returns the child canvas's @method[skia-canvas-on-gpu% closed?] result.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the child canvas's cleanup state.
}
}

@section[#:tag "skia-gui-cleanup"]{Closing GUI Rendering Resources}

All canvas and convenience-window interfaces provide @tt{close},
@tt{closed?}, and @tt{get-close-state}. Call them on the widget's eventspace
handler thread. A window's @tt{close} also hides the window, and its state
queries report the child canvas's state. Hiding a window alone does not close
its rendering resources. Stop application-owned animation timers when closing
the widget.

The cleanup states are:

@itemlist[
 @item{@racket['open]: closure has not begun. This is not a GPU-health check.}
 @item{@racket['closing]: further rendering has stopped, but cleanup is
       still in progress or deferred until an active frame ends.}
 @item{@racket['close-failed]: a cleanup attempt raised an exception.
       Rendering remains stopped; address the cause and retry @tt{close}.}
 @item{@racket['closed]: cleanup completed successfully. Further
       @tt{close} calls are harmless.}]

The @tt{closed?} method returns true only for @racket['closed]. The state
query does not activate a GPU context, initialize a presenter, or retry cleanup.

For a GPU widget, stopping further rendering and finishing native cleanup are
separate steps. A close during a raw GPU frame can defer cleanup until the
frame ends; open application-owned GPU resources can make cleanup fail.
Close those resources according to their context's rules, then retry the
widget's @tt{close} method. The @tt{get-close-state} result reflects both
immediate and deferred cleanup outcomes; @tt{closed?} remains false until
cleanup succeeds. The unified interface's
@method[skia-render-canvas<%> get-render-info] reports the same cleanup state
in @racket['close_status].

The raster and unified interfaces reject closure during their paint
callbacks. The raw GPU and GPU drawing-context interfaces instead use the
presenter's deferred-cleanup rules. These differences do not permit closing
a borrowed frame canvas or the presenter's context independently. For the
resource-level cleanup functions, see @secref["skia-resource-cleanup"].
