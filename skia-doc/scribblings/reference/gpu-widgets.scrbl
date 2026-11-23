#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (except-in racket/gui/base make-font)
                     skia skia/gpu skia/gpu-gui skia/canvas skia/gpu-canvas
                     skia/render-canvas))

@title[#:tag "skia-gpu-widgets"]{GPU Widgets for Direct Skia Drawing}

@defmodule[skia/gpu-gui #:no-declare]
@(declare-exporting skia/gpu-gui #:use-sources (skia/gpu-gui))

Use @racket[gpu-canvas%] when you want to draw directly with Skia functions
such as @racket[draw-circle] and @racket[draw-path]. Its render callback
receives a @tech{GPU frame}; call @racket[gpu-frame-canvas] to obtain the Skia
canvas to draw on. The frame and its @tech{borrowed canvas} are valid only during
that callback. The @racket[gpu-window%] class provides a convenience window
containing one such canvas widget.

Both @racket[gpu-canvas%] and @racket[skia-canvas-on-gpu%] use Skia. The latter is
the GPU counterpart of @racket[skia-canvas%] in the Racket drawing-context
interface. It adapts @racket[gpu-canvas%]'s frames into drawing contexts for
the paint callback. If your code uses Racket drawing-context methods instead
of direct Skia functions, see @secref["skia-gui-canvases"] for the CPU and GPU
choices.

The @racketmodname[skia/gpu-gui] library initializes Racket's GUI layer and
uses the @tech{GPU presenter} API to display frames. Construction and
widget-specific operations belong to the creating eventspace's handler
thread. Use @racket[queue-callback] to schedule such work from another thread.

The frame canvas initially uses physical pixels. See
@secref["skia-gpu-frame-geometry"] for drawing in logical window coordinates
on high-density displays.

@section[#:tag "skia-gui-backend-options"]{Backend Selection and Options}

Backend selection is fixed for a widget's lifetime. All GUI constructors use
the same automatic GPU choice: Metal on macOS, Direct3D on Windows x86-64,
and desktop OpenGL on Unix. On other platforms there is no automatic GPU
backend. The unified factory and window select raster there only when both
renderer and backend are @racket['auto]; a GPU-only request raises an exception.

These are platform selection rules, not driver probes or failure fallbacks.
Explicit Direct3D presentation requires Windows x86-64; explicit Metal
requires macOS. Failed GPU initialization does not select another backend or
replay the drawing callback on a CPU renderer. WARP is never an implicit
fallback.

The @racket[adapter], @racket[adapter-index], and @racket[sync-interval]
options apply only to Direct3D. Supplying a value other than @racket[#f] for
one of them with another backend raises an exception. For Direct3D,
@racket[#f] selects @racket['hardware], index @racket[0], and synchronization
interval @racket[1], respectively. Explicit @racket['warp] selection requires
index @racket[0].

All GUI constructors check the same numeric restrictions before creating
a window or child widget:

@itemlist[
 @item{Adapter indices range from @racket[0] through @racket[4294967294],
       as in @racket[make-gpu-context]. These are
       numeric limits; selecting an adapter also requires that it exist.}
 @item{The Direct3D presenter accepts synchronization interval @racket[0]
       for immediate presentation or @racket[1] for presentation synchronized
       with a vertical refresh. These are requests, not frame-rate guarantees.
       Other explicit synchronization intervals raise an exception.}]

The synchronization option does not control OpenGL or Metal presentation;
values other than @racket[#f] are rejected for those backends, and these
constructors expose no corresponding synchronization setting for them.

@section{GPU Canvases}

@defclass[gpu-canvas% canvas% ()]{
Implements a callback-oriented GPU canvas with a lazily initialized presenter.
Hiding or minimizing the widget suspends acquisition but does not close its
presenter.

@defconstructor[([parent (is-a?/c area-container<%>)]
                 [style (listof symbol?) '()]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f (integer-in 0 4294967294)) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [render (-> gpu-frame? any) void]
                 [on-error procedure? raise]
                 [background color? 'white]
                 [automatic? boolean? #t]
                 [min-width exact-nonnegative-integer? 1]
                 [min-height exact-nonnegative-integer? 1])]{
Creates a GPU canvas.

The @racket[render] callback receives one @tech{GPU frame} and runs on the
widget's eventspace handler thread. Use @racket[gpu-frame-canvas] to obtain
the Skia canvas for drawing. The callback may return any number of values;
they are ignored. The default callback, @racket[void], does not draw.

The frame's canvas and @tech{GPU context} are borrowed and may be used only during
the callback. Do not close these borrowed resources independently.
The @racket[on-error] callback receives one raised value. Neither callback
may require keyword arguments.

Backend defaults and Direct3D-only options are described in
@secref["skia-gui-backend-options"]. Supported @racket[style] flags are
@racket['border], @racket['control-border], @racket['no-focus], and
@racket['deleted]. Backend-specific flags are managed internally.
@racket['no-autoclear] is not accepted: GPU frames do not preserve the
previous frame's pixels.
}

@defmethod[(get-gpu-presenter) gpu-presenter?]{
Returns the presenter, initializing it if necessary. Explicit access can retry
an earlier initialization failure.
}

@defmethod[(get-gpu-backend) (or/c 'opengl 'metal 'direct3d)]{
Returns the fixed presentation backend.
}

@defmethod[(request-gpu-render) void?]{
Requests a redraw. Repeated requests are coalesced by the presenter scheduler.
}

@defmethod[(render-gpu-now) (or/c 'present-requested 'skipped 'cancelled)]{
Performs an immediate presenter render. The method is rejected inside another
active GPU or presentation scope.
}

@defmethod[(close) void?]{
Stops automatic scheduling and requests safe presenter closure. A failed close
can be retried after application-owned GPU children retire. Stopping the
widget does not by itself prove that native cleanup has finished; see
@secref["skia-gui-cleanup"].
}

@defmethod[(closed?) boolean?]{
Returns whether rendering-resource cleanup has completed successfully.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the cleanup state without initializing the presenter. It includes
the result of deferred cleanup; see @secref["skia-gui-cleanup"].
}

@defmethod[(check-gpu-geometry) void?]{
Checks size, backing scale, visibility, and iconization and requests a redraw
when the observed geometry changes. With @racket[automatic?] true, GUI events
and a weak geometry monitor invoke this check; the monitor is not an animation
clock or frame-rate guarantee.
}
}

@section{GPU Windows}

@defclass[gpu-window% frame% ()]{
Provides a convenience frame containing one @racket[gpu-canvas%].

@defconstructor[([label string? "Skia GPU"]
                 [canvas-style (listof symbol?) '()]
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f (integer-in 0 4294967294)) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [render (-> gpu-frame? any) void]
                 [on-error procedure? raise]
                 [background color? 'white]
                 [automatic? boolean? #t])]{
Creates a GPU window using the same backend and scheduling rules as
@racket[gpu-canvas%]. The @racket[canvas-style] argument supplies the child
canvas's style flags, not the containing frame's style.

The @racket[render] callback is passed to the child @racket[gpu-canvas%]. It
receives one @tech{GPU frame}, not the window object, and its return values
are ignored. The callback runs on the window's eventspace handler thread.
The keyword-argument restrictions and borrowed-frame lifetime rules are the
same as for @racket[gpu-canvas%].
}

@defmethod[(get-gpu-canvas) (is-a?/c gpu-canvas%)]{
Returns the child GPU canvas.
}

@defmethod[(get-gpu-presenter) gpu-presenter?]{
Returns the child's presenter, initializing it if necessary.
}

@defmethod[(request-gpu-render) void?]{
Requests a redraw of the child canvas.
}

@defmethod[(close) void?]{
Closes the child presenter and hides the frame. Window-manager close uses the
same path. Closing one window does not close another window's context.
}

@defmethod[(closed?) boolean?]{
Returns the child canvas's @method[gpu-canvas% closed?] result.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the child canvas's cleanup state.
}
}

@section[#:tag "skia-gpu-animation"]{Requesting Animation Frames}

Use a @racket[timer%] to advance animation state and request a redraw. Create
the timer on the widget's eventspace handler thread, so its callback can
update that state and request rendering on the same thread. Use
@racket[queue-callback] when scheduling setup from another thread.

For example, suppose @racket[canvas-widget] is a @racket[gpu-canvas%] whose
render callback draws according to @racket[phase]. The following timer
advances that phase and requests a redraw about every 16 milliseconds:

@racketblock0[
(define phase 0)
(define animation-timer
  (new timer%
       [notify-callback
        (lambda ()
          (set! phase (modulo (add1 phase) 360))
          (send canvas-widget request-gpu-render))]))
(send animation-timer start 16)
]

Timer notifications and redraw requests do not guarantee a frame rate.
Repeated requests may be coalesced, and a hidden window may not acquire a
frame. Keep drawing in the render callback rather than calling
@method[gpu-canvas% render-gpu-now] from the timer. The widget's automatic
geometry monitor only detects changes such as size, backing scale, and visibility; it does not
advance an animation.

Stop the timer when the animation ends or the widget is closed. For example,
the application's shutdown handler can perform these operations on the
eventspace handler thread:

@racketblock0[
(send animation-timer stop)
(send canvas-widget close)
]

For a drawing-context canvas, use its @tt{refresh} method instead of
@tt{request-gpu-render}; the same scheduling principle applies.
