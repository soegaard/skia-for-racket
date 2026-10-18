#lang scribble/manual

@(require (for-label racket/base racket/contract skia/gpu skia/gpu-diagnostics))

@title[#:tag "skia-gpu-diagnostics"]{GPU Diagnostics}

The property queries below report information about a @tech{GPU context} without
measuring performance or synchronizing GPU work. @racket[gpu-smoke-test] instead
draws a fixed pattern, waits for completion, and checks the resulting pixels.
Neither establishes that rendering is hardware accelerated.

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
digits, and underscores. An unknown well-formed extension returns false;
malformed names and non-OpenGL contexts raise.

The query examines the interface used to create this Ganesh context. Extension
membership alone does not certify rendering support, a driver path, or visual
correctness. No flush, submission, wait, or pixel readback is implied.
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
and immutable RGBA bytes. Temporary GPU resources are retired on exit. This is
a functional diagnostic with an explicit readback; it is not a general drawing
API, benchmark, presentation test, or proof of hardware acceleration.
}
