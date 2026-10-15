#lang scribble/manual

@(require (for-label racket/base racket/class racket/contract racket/gui/base
                     skia/render-canvas))

@title[#:tag "skia-render-canvases"]{Unified Render Canvases}

@defmodule[skia/render-canvas #:no-declare]
@(declare-exporting skia/render-canvas #:use-sources (skia/render-canvas))

This GUI module provides one callback-oriented protocol over the persistent
raster canvas and frame-scoped GPU canvas. Renderer choice is fixed before the
widget is constructed; a runtime GPU failure does not replace the object with a
raster canvas or replay the application callback.

@defproc[(make-skia-render-canvas
          [parent (is-a?/c area-container<%>)]
          [#:renderer renderer (or/c 'auto 'raster 'gpu) 'auto]
          [#:backend backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
          [#:adapter adapter (or/c 'hardware 'warp #f) #f]
          [#:adapter-index adapter-index (or/c exact-nonnegative-integer? #f) #f]
          [#:sync-interval sync-interval (or/c (integer-in 0 4) #f) #f]
          [#:paint-callback paint-callback procedure? void]
          [#:on-error on-error procedure? raise]
          [#:background background any/c "white"]
          [#:smoothing smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed]
          [#:min-width min-width exact-nonnegative-integer? 1]
          [#:min-height min-height exact-nonnegative-integer? 1])
         (and/c (is-a?/c canvas%) skia-render-canvas?)]{
Creates a canvas implementing @racket[skia-render-canvas<%>] on the current
eventspace handler thread. The paint callback accepts the canvas and drawing
context, and its result values are ignored. @racket[on-error] accepts one raised
value. Neither callback may require keyword arguments.

@racket['raster] always selects the CPU implementation. With a GPU renderer and
an automatic backend, the unified policy chooses Metal on macOS, Direct3D on
Windows x86-64, and desktop OpenGL on Unix. @racket['auto] chooses that GPU
preference where declared, otherwise raster. These are declarative platform
rules, not driver probes or fallback rules. Direct3D adapter/sync options are
rejected for other backends; WARP never appears as an implicit fallback.

The selector accepts synchronization intervals from 0 through 4. The current
Direct3D GUI presenter accepts only 0 or 1, so larger selected values are rejected
when that implementation is constructed rather than silently changed.
}

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
Returns immutable lifetime, storage-path, and raster-only capability metadata.
}

@defmethod[(get-render-info) (and/c hash? immutable?)]{
Returns detached selection, callback-count, last-size, close-state, and
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

@defmethod[(close-skia) void?]{
Closes through the selected implementation. Closure is rejected inside a paint
callback, and backend cleanup can remain retryable after a failure.
}

@defmethod[(close) void?]{
Closes the same resources as @method[skia-render-canvas<%> close-skia].
}

@defmethod[(closed?) boolean?]{
Returns the underlying widget's closed state.
}

A saved raster callback DC can remain a live persistent object after callback
return, but @method[skia-render-canvas<%> get-dc] does not expose it outside the
callback; use @method[skia-render-canvas<%> get-raster-dc] explicitly. A saved
GPU callback DC expires permanently at frame exit. Portable callbacks should
initialize the drawing state they need instead of depending on retained raster
state.
}

@defproc[(skia-render-canvas? [v any/c]) boolean?]{
Returns whether @racket[v] implements @racket[skia-render-canvas<%>].
}

@defclass[skia-render-window% frame% ()]{
Provides a convenience frame containing one unified render canvas.

@defconstructor[([label string? "Skia render canvas"]
                 [width exact-nonnegative-integer? 640]
                 [height exact-nonnegative-integer? 480]
                 [renderer (or/c 'auto 'raster 'gpu) 'auto]
                 [backend (or/c 'auto 'opengl 'metal 'direct3d) 'auto]
                 [adapter (or/c #f 'hardware 'warp) #f]
                 [adapter-index (or/c #f exact-nonnegative-integer?) #f]
                 [sync-interval (or/c #f (integer-in 0 4)) #f]
                 [paint-callback procedure? void]
                 [on-error procedure? raise]
                 [background any/c "white"]
                 [smoothing (or/c 'unsmoothed 'smoothed 'aligned) 'smoothed])]{
Creates a 640 by 480 unified render window unless another size is supplied.
}

@defmethod[(get-render-canvas) (is-a?/c canvas%)]{
Returns the factory-created child canvas implementing
@racket[skia-render-canvas<%>].
}

@defmethod[(close-render) void?]{
Closes the child and hides the frame. A rejected close during painting does not
hide the window. Window-manager close uses the same method.
}
}
