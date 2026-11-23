#lang scribble/manual

@(require (for-label racket/base racket/contract skia/gpu skia/gpu-diagnostics))

@title[#:tag "skia-gpu-diagnostics"]{GPU Diagnostics}

Choose a report according to what you need to know:

@itemlist[
 @item{@racket[gpu-backend-capabilities] describes the library's supported
       interfaces without probing the current machine.}
 @item{@racket[gpu-context-info] combines construction choices and initial native
       measurements with current wrapper state and child-resource counts. It
       does not refresh those native measurements.}
 @item{@racket[gpu-surface-format-info] queries the active context's format limits;
       it does not attempt a surface allocation.}
 @item{@racket[gpu-cache-info] and @racket[gpu-memory-statistics] report cache or
       Skia resource usage, not total device memory.}
 @item{The OpenGL queries below describe the context's selected interface and
       advertised extensions.}]

These queries do not draw a test image or measure rendering performance.
@racket[gpu-smoke-test] instead draws a fixed pattern, waits for completion,
and checks the resulting pixels. Neither the queries nor the rendering check
establish that rendering is hardware accelerated.

@section{OpenGL Interface Diagnostics}

@defmodule[skia/gpu-diagnostics #:no-declare]
@(declare-exporting skia/gpu skia/gpu-diagnostics
                    #:use-sources (skia/gpu-diagnostics))

@defproc[(gpu-gl-interface-info [context gpu-context?]) (and/c hash? immutable?)]{
Returns a description of the exact Skia GL interface used by an
active OpenGL @racket[context]. Non-OpenGL contexts are rejected instead of
returning an ambiguous report.

The report records the requested interface mode, selected factory, validation
status, and that extension queries use the context-owned interface. These fields
describe how the interface was created. They do not prove that a particular Skia
operation uses an extension or that the driver is hardware accelerated.
}

@defproc[(gpu-gl-has-extension? [context gpu-context?] [name string?]) boolean?]{
Reports whether the Skia GL interface used by the active OpenGL
@racket[context] advertises @racket[name]. The name must be one ASCII identifier
of 1 through 255 characters, begin with a letter, and contain only letters,
digits, and underscores. If the name violates these requirements or
@racket[context] does not use OpenGL, the function raises an exception.
A well-formed name that the interface does not advertise returns @racket[#f].

An advertised extension does not establish that a particular drawing operation
uses it or produces the expected pixels. The query performs no flush, submission,
wait, or pixel readback.
}

@section{Fixed Rendering Diagnostic}

@(declare-exporting skia/gpu)

@defproc[(gpu-smoke-test [context gpu-context?]) (and/c hash? immutable?)]{
Checks GPU rendering by drawing a fixed 8 by 8 pattern and comparing the pixels
with the expected result.

The context must be ready and owned by the calling thread. The function enters
the context as needed, creates private target and paint resources, and draws
four fixed color regions. It flushes and submits the work, waits for completion,
then reads and verifies the RGBA pixels before returning.

The result records the dimensions, transfer format, backend identity,
and immutable RGBA bytes. Temporary GPU resources are closed on exit. This is
a functional diagnostic with an explicit readback; it is not a general drawing
API, benchmark, presentation test, or proof of hardware acceleration.
}
