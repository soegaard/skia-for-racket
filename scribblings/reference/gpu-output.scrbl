#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu skia/gpu-output))

@title[#:tag "skia-gpu-output"]{GPU Raster Output Execution}

@defmodule[skia/gpu-output #:no-declare]
@(declare-exporting skia/gpu-output #:use-sources (skia/gpu-output))

These functions provide an explicit GPU @tech{raster executor} for bounded @tech{raster fallbacks} in
PDF and SVG output. The executor changes where the temporary raster is drawn; it
does not change the output policy or turn a vector-compatible group into a
raster group by itself.

A GPU executor renders the temporary target in one exact @tech{GPU context}, performs
an explicit synchronous @tech{GPU readback}, and gives the output layer a CPU-owned @tech{image}.
The resulting document therefore does not depend on GPU resources after export.
This is not a zero-copy path and makes no performance or hardware-acceleration guarantee.

@defproc[(make-gpu-raster-executor [context gpu-context?])
         output-raster-executor?]{
Creates a GPU @tech{raster executor} that borrows @racket[context]. The context
must be ready, have no pending shutdown request, and be used from its owner
thread. The executor records the context generation and rejects later use after
a generation change.

The executor does not close @racket[context]. Each raster operation activates
that exact context, creates a temporary GPU surface, replays the captured
picture, and converts the result to a CPU-owned raster image before returning it
to the output layer. A recorded picture that depends on resources from a different
GPU context is rejected instead of being transferred implicitly.

Pass the executor to @racket[draw-output-group] using its
@racket[#:raster-executor] argument. The executor is used only when the group's
output policy selects rasterization; a group that remains vector does not invoke
GPU raster execution. See @secref["skia-output-groups"].
}

@defproc[(call-with-gpu-raster-executor
          [make-context (-> gpu-context?)]
          [proc (-> output-raster-executor? any)]
          [#:on-unavailable on-unavailable (or/c 'error 'cpu) 'error])
         any]{
Calls @racket[proc] with a scoped @tech{raster executor} and returns its values.
The function must accept one positional argument and no required keywords. The
@racket[make-context] function is invoked lazily when the scope first needs
GPU raster execution, and a created context is closed when the dynamic extent
ends. The executor must not escape the call.

With @racket[#:on-unavailable 'error], backend unavailability is propagated.
With @racket[#:on-unavailable 'cpu], CPU rendering is used only if
@racket[make-context] reports GPU unavailability. Other context-creation errors,
callback errors, and failures during GPU rendering, readback, or cleanup propagate
without retrying on the CPU.
}
