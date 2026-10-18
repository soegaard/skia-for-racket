#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/gpu skia/gpu-diagnostics))

@title[#:tag "skia-gpu-synchronization"]{GPU Synchronization and Resource Caches}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

A @deftech{GPU flush} makes pending Skia work available for submission.
A @deftech{GPU submission} requests backend execution. A @deftech{GPU wait}
requests completion for the CPU. These are different boundaries: none presents
a window, exports a native fence, or transfers pixels
by itself. These operations require the owning Racket thread and
an active, usable @tech{GPU context}. Detected native context loss requests shutdown and
raises; it does not retry rendering on the CPU.

@bold{Conceptual diagram.} Pending drawing, flush, submission, and requested
CPU completion are separate boundaries. @tech{GPU readback} and presentation are separate
routes from submitted work: readback produces an independent CPU result, while
presentation is requested through its presentation API. A completed wait alone
neither copies pixels nor presents them; presentation success is a request, not
proof of physical display.

@reference-figure["concept-gpu-boundaries.png"
                  "A responsibility diagram sequences pending draw, flush, submit, and CPU wait, then branches from submitted work to readback into a CPU image and a presentation request. Captions state that submit requires prior flush and wait alone neither reads back nor presents."]

@section{Flush, Submit, and Wait}

@defproc[(gpu-flush! [context gpu-context?]) void?]{
Performs a @tech{GPU flush} for the context. It does not request CPU completion.
Use @racket[gpu-submit!] to submit flushed work, or
@racket[gpu-flush-and-submit!] for both operations.
}

@defproc[(gpu-submit! [context gpu-context?] [#:wait? wait? boolean? #f]) void?]{
Requests @tech{GPU submission} of previously flushed work. A true @racket[wait?]
requests CPU completion of submitted work. This operation does not first flush
all pending Skia commands;
use @racket[gpu-wait!] when those commands must be included. Native submission
failure raises an exception. No pixel readback or presentation is performed.
}

@defproc[(gpu-flush-and-submit! [context gpu-context?]
                              [#:wait? wait? boolean? #f]) void?]{
Flushes the context, then submits its work with the given wait request.
A failure of either stage propagates. This is not a transaction that undoes
already submitted work.
}

@defproc[(gpu-wait! [context gpu-context?]) void?]{
Flushes and submits with @racket[#:wait? #t], including pending Skia commands
in the completion request. It neither presents a frame nor copies pixels.
Successful completion is not an interoperability fence for a different device
or an unrelated queue.
}

@defproc[(gpu-flush-surface! [context gpu-context?] [surface gpu-surface?]) void?]{
Flushes work associated with a surface owned by @racket[context]. The surface
must be live with a balanced save/layer stack at save count 1. A CPU or document
target is rejected rather than uploaded. The flush may include dependent work;
it is not a guarantee that unrelated work will remain unexecuted. It requests
neither submission nor CPU completion.
}

@defproc[(gpu-flush-image! [context gpu-context?] [image gpu-image?]) void?]{
Like @racket[gpu-flush-surface!], for a live image in that same context. It does
not upload a CPU image, download the texture, or request submission or completion.
There is no canvas-stack condition for an image.
}

@section{Budgeted Resource Caches}

These operations address the selected context's budgeted resource cache, not
all GPU memory or the process-wide caches in @secref["skia-graphics"]. Purging
does not close the caller's resource wrappers. A byte request is not proof of
bytes released, and a cache limit is not a hard allocation cap.

@defproc[(gpu-cache-info [context gpu-context?]) (and/c hash? immutable?)]{
Reports the context's budgeted cache usage and limit.

The result is an immutable hash table containing the backend, context generation,
@racket['limit_bytes], @racket['budgeted_resources], and @racket['budgeted_bytes].
The usage count and bytes describe budgeted resources, not total VRAM.
The @racket['purgeable_bytes], @racket['total_gpu_bytes], and
@racket['limit_is_hard_allocation_cap] fields are false. The report is not an
atomic account of all driver memory.
}

@defproc[(gpu-set-cache-limit! [context gpu-context?] [bytes exact-nonnegative-integer?]) void?]{
Sets the context's budgeted cache byte limit. The value must fit native
@tt{size_t}; zero is accepted. This function returns void, not the previous
limit or the number of bytes freed. It does not impose a total GPU-memory cap.
}

@defproc[(gpu-purge-unlocked! [context gpu-context?]
                            [#:scratch-only? scratch-only? boolean? #f]) void?]{
Requests purging of unlocked cache resources, optionally restricted to scratch
resources. Resources that are locked or still referenced by other objects may
remain allocated. This operation does not promise a particular reduction in
memory use or CPU completion.
}

@defproc[(gpu-purge-bytes! [context gpu-context?] [bytes exact-nonnegative-integer?]
                         [#:prefer-scratch? prefer-scratch? boolean? #t]) void?]{
Requests purging the given number of bytes, preferring scratch resources when
requested. The byte count must fit native @tt{size_t}; zero is valid. The request
is not a guarantee that this many bytes can be freed. The result is void.
}

@defproc[(gpu-perform-deferred-cleanup! [context gpu-context?]
                                      [milliseconds (integer-in 0 2147483647)]) void?]{
Requests native cleanup based on how long resources have been unused. The exact
nonnegative age is measured in milliseconds. It is not a delay: the function
does not schedule a future callback or sleep for that duration. It returns no
freed-byte count and does not guarantee CPU completion.
}

@defproc[(gpu-free-resources! [context gpu-context?]) void?]{
Requests release of context resources without abandoning the context. The
context remains usable. The native implementation may flush and submit work,
but this operation does not provide a CPU completion fence. It does not retire
live image/surface wrappers or replace orderly context closure.
}

@section{Bounded Memory Reports}

@(declare-exporting skia/gpu skia/gpu-diagnostics #:use-sources (skia/gpu-diagnostics))

@defproc[(gpu-memory-statistics [context gpu-context?]
          [#:detailed? detailed? boolean? #f] [#:dump-wrapped? dump-wrapped? boolean? #f]
          [#:max-entries max-entries (integer-in 0 65536) 4096]
          [#:string-limit string-limit (integer-in 0 65536) 4096]
          [#:byte-limit byte-limit exact-nonnegative-integer? 1048576]) memory-statistics?]{
Returns a memory report for the active context. Its scope is
@racket['gpu-context-skia-resources], not
@racket['process-global-skia-caches]. Use the existing
@racket[memory-statistics-entries] and related accessors to inspect it.

The limits and collector rules match @racket[skia-memory-statistics]. The
maximum entry overhead, estimated as 128 bytes per entry, plus
@racket[byte-limit] must fit @racket[current-skia-byte-limit]. Strings are bounded
individually and in total. Limit-induced omissions are reported as truncation
and a dropped count, not silently presented as a complete report.

The report is not an atomic snapshot, a total-VRAM measurement, or proof that
wrapped external allocations are fully accounted for. Native names and report
contents can vary. The collector cannot run during a live-stream operation or
from its port-service callback.
}
