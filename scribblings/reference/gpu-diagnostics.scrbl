#lang scribble/manual

@(require (for-label racket/base racket/contract skia/gpu skia/gpu-diagnostics))

@title[#:tag "skia-gpu-diagnostics"]{GPU Diagnostics}

These diagnostics report properties of a selected @tech{GPU context}.
They are diagnostics, not hardware attestations, performance measurements, or
implicit synchronization barriers.

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
describe construction provenance. They do not prove that a particular Skia
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
Runs a fixed synchronous 8 by 8 GPU rendering diagnostic. The context must be
ready and owned by the calling thread. The function enters the context as
needed, creates private target and paint resources, draws four fixed color
regions, flushes, submits with CPU completion, reads RGBA pixels, and verifies
the expected pattern before returning.

The result records the dimensions, transfer format, backend identity,
and immutable RGBA bytes. Temporary GPU resources are retired on exit. This is
a functional diagnostic with an explicit readback; it is not a general drawing
API, benchmark, presentation test, or proof of hardware acceleration.
}
