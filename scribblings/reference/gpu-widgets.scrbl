#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract
                     (except-in racket/gui/base make-font)
                     skia skia/gpu skia/gpu-gui))

@title[#:tag "skia-gpu-widgets"]{GPU GUI Widgets}

@defmodule[skia/gpu-gui #:no-declare]
@(declare-exporting skia/gpu-gui #:use-sources (skia/gpu-gui))

The @racketmodname[skia/gpu-gui] library initializes Racket's GUI layer and
provides widgets backed by the presenter API. Construction and widget-specific
operations belong to the creating eventspace's handler thread. Use
@racket[queue-callback] to schedule such work from another thread.

Backend selection is fixed for a widget's lifetime. @racket['auto] chooses Metal
on macOS and OpenGL elsewhere; it is a selection rule, not a failure fallback.
Explicit Direct3D presentation requires Windows x86-64. Explicit Metal requires
macOS. Failed GPU construction does not replay the callback on a CPU renderer.

The unified factory in @secref["skia-render-canvases"] uses a separate automatic
policy: on Windows x86-64 it selects Direct3D, while these raw GPU widgets select
OpenGL. In both APIs, @racket['auto] is a constructor-local selection rule rather
than a universal package-wide backend choice.

@section{GPU Canvases}

@defclass[gpu-canvas% canvas% ()]{
Implements a callback-oriented GPU canvas with a lazily initialized presenter.
Hiding or minimizing the widget suspends acquisition but does not close its
presenter.

@defconstructor[([parent (is-a?/c area-container<%>)]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f exact-nonnegative-integer?) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [render procedure? void]
                 [on-error procedure? raise]
                 [background color? 'white]
                 [automatic? boolean? #t]
                 [min-width exact-nonnegative-integer? 1]
                 [min-height exact-nonnegative-integer? 1])]{
Creates a GPU canvas. The @racket[render] function must accept one frame and
@racket[on-error] must accept one raised value; neither may require keyword
arguments. Direct3D adapter and synchronization options are rejected for other
backends. WARP uses adapter index zero.
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

@defmethod[(close-gpu) void?]{
Stops automatic scheduling and requests safe presenter closure. A failed close
can be retried after application-owned GPU children retire.
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
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f exact-nonnegative-integer?) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [render procedure? void]
                 [on-error procedure? raise]
                 [background color? 'white]
                 [automatic? boolean? #t])]{
Creates a GPU window using the same backend, callback, and scheduling rules as
@racket[gpu-canvas%].
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

@defmethod[(close-gpu) void?]{
Closes the child presenter and hides the frame. Window-manager close uses the
same path. Closing one window does not close another window's context.
}
}
