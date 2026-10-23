#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract racket/gui/base
                     (prefix-in draw: racket/draw)
                     skia/canvas skia/render-canvas))

@title[#:tag "skia-render-canvases"]{Unified Render Canvases}

@defmodule[skia/render-canvas #:no-declare]
@(declare-exporting skia/render-canvas #:use-sources (skia/render-canvas))

Use @racketmodname[skia/render-canvas] when the same drawing-context callback
should work with either CPU or GPU rendering. The callback receives the
widget and a drawing context; draw in logical window coordinates, since the
selected implementation applies the logical-to-pixel scaling. Drawing-context
state persists on the raster renderer but starts fresh for each GPU frame.

Renderer choice is fixed before the widget is constructed. A runtime GPU
failure does not replace the object with a raster canvas or replay the
application callback. See @secref["skia-gui-backend-options"] for the
automatic choices and current constructor restrictions.

@local-table-of-contents[#:style 'immediate-only]

@section{Construction and Renderer Selection}

@defproc[(make-skia-render-canvas
          [parent (is-a?/c area-container<%>)]
          [#:style style (listof symbol?) '()]
          [#:renderer renderer (or/c 'auto 'raster 'gpu) 'auto]
          [#:backend backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
          [#:adapter adapter (or/c 'hardware 'warp #f) #f]
          [#:adapter-index adapter-index (or/c #f (integer-in 0 4294967294)) #f]
          [#:sync-interval sync-interval (or/c (integer-in 0 1) #f) #f]
          [#:paint-callback paint-callback procedure? void]
          [#:on-error on-error procedure? raise]
          [#:background background (or/c string? (is-a?/c draw:color%)) "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:min-width min-width exact-nonnegative-integer? 1]
          [#:min-height min-height exact-nonnegative-integer? 1])
         (and/c (is-a?/c canvas%) skia-render-canvas?)]{
Creates a canvas implementing @racket[skia-render-canvas<%>] on the current
eventspace handler thread. The paint callback accepts the canvas and drawing
context, and its result values are ignored. The @racket[on-error] callback accepts one
raised value. Neither callback may require keyword arguments.

The @racket['raster] renderer always selects the CPU implementation and
requires @racket[backend] to be @racket['auto]. The @racket['gpu] renderer
requires a GPU backend; @racket['auto] chooses according to the platform and
backend request. All GUI constructors share the backend rules in
@secref["skia-gui-backend-options"].

Adapter and synchronization options other than @racket[#f] require
Direct3D. Unsupported values are rejected before creating a child widget.

The @racket[smoothing] setting is passed to either implementation. Its
default is @racket['smoothed], as for the other GUI drawing-context interfaces.

The @racket[style] argument accepts @racket['border], @racket['control-border],
@racket['no-focus], and @racket['deleted]. The raster renderer additionally
accepts @racket['no-autoclear]; selecting GPU rendering with that flag raises
an exception rather than promising persistent frame pixels.
}

@section{Common Render Canvas Interface}

@definterface[skia-render-canvas<%> ()]{
Specifies the common callback-oriented protocol implemented by the unified
raster and GPU canvas wrappers.

@defmethod[(get-renderer) (or/c 'raster 'gpu)]{
Returns the selected renderer. The result remains available after closure.
}

@defmethod[(get-backend) (or/c 'raster 'opengl 'metal 'direct3d)]{
Returns the selected backing backend.
}

@defmethod[(get-render-capabilities) (and/c hash? immutable?)]{
Returns an immutable hash table describing the renderer, drawing-context lifetime,
whether drawing state persists between callbacks, and support for cached-pixel
presentation and bitmap transfer.
}

@defmethod[(get-render-info) (and/c hash? immutable?)]{
Returns selection, callback-count, last-size, close-state, and
implementation diagnostics.
}

@defmethod[(get-dc) object?]{
Returns the exact drawing context only while a paint callback is live. The
common protocol rejects this method outside callbacks on both renderers.
}

@defmethod[(get-raster-dc) object?]{
Returns the persistent raster drawing context for a raster canvas and rejects a
GPU canvas without readback or renderer fallback.
}

@defmethod[(set-paint-callback [proc procedure?]) void?]{
Replaces the ordinary two-argument paint callback while idle. The method does
not request a frame by itself.
}

@defmethod[(refresh) void?]{
Requests another frame through the selected implementation's scheduler.
}

@defmethod[(refresh-now [proc (or/c #f procedure?) #f]
                        [#:flush? flush? boolean? #t])
           void?]{
Performs a synchronous frame. The optional one-argument callback applies only
to that invocation. Only a true @racket[flush?] is portable through this
interface.
}

@defmethod[(present) void?]{
Presents cached pixels for the raster renderer. GPU callers must request a new
frame instead.
}

@defmethod[(close) void?]{
Closes through the selected implementation. Closure is rejected inside a paint
callback, and backend cleanup can remain retryable after a failure.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the cleanup state described in @secref["skia-gui-cleanup"].
}

@defmethod[(closed?) boolean?]{
Returns whether rendering-resource cleanup has completed successfully.
It remains false after a failed cleanup attempt; see
@secref["skia-gui-cleanup"].
}

A saved raster callback DC can remain a live persistent object after callback
return, but @method[skia-render-canvas<%> get-dc] does not expose it outside the
callback; use @method[skia-render-canvas<%> get-raster-dc] explicitly. A saved
GPU callback DC expires permanently at frame exit. Portable callbacks should
initialize the drawing state they need instead of depending on raster DC state
left by a previous callback.
}

@defproc[(skia-render-canvas? [v any/c]) boolean?]{
Returns whether @racket[v] implements @racket[skia-render-canvas<%>].
}

@section{Unified Render Windows}

@defclass[skia-render-window% frame% ()]{
Provides a convenience frame containing one unified render canvas.

@defconstructor[([label string? "Skia render canvas"]
                 [canvas-style (listof symbol?) '()]
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [renderer (or/c 'auto 'raster 'gpu) 'auto]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f (integer-in 0 4294967294)) #f]
                 [sync-interval (or/c #f (integer-in 0 1)) #f]
                 [paint-callback procedure? void]
                 [on-error procedure? raise]
                 [background (or/c string? (is-a?/c draw:color%)) "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed])]{
Creates a 640 by 480 unified render window unless another size is supplied.
Renderer selection and option restrictions are the same as for
@racket[make-skia-render-canvas]. The @racket[canvas-style] argument supplies
the child canvas's style flags.
}

@defmethod[(get-render-canvas) (is-a?/c canvas%)]{
Returns the factory-created child canvas implementing
@racket[skia-render-canvas<%>].
}

@defmethod[(close) void?]{
Closes the child and hides the frame. A rejected close during painting does not
hide the window. Window-manager close uses the same method.
}

@defmethod[(closed?) boolean?]{
Returns the child canvas's @method[skia-render-canvas<%> closed?] result.
}

@defmethod[(get-close-state) (or/c 'open 'closing 'close-failed 'closed)]{
Returns the child canvas's cleanup state.
}
}
