#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-resources"]{Resources and Lifetimes}

Skia uses native resources alongside detached Racket values. Resource kind,
ownership, and scope determine when a value remains valid and how it should be
released.

@local-table-of-contents[#:style 'immediate-only]

@section{Resource Kinds and Validity}

An @deftech{owned resource} has a native lifetime managed by its wrapper. An
@deftech{ordinary CPU resource}, such as a CPU @tech{surface} or @tech{paint},
has fallback cleanup after it becomes unreachable. Ordinary Racket bindings
are sufficient when the exact release time does not matter. Fallback cleanup
has no predictable timing; use explicit release when its timing matters.

A @deftech{borrowed canvas} has no independent native lifetime. Its owner and
any callback or GPU activation that supplied it must remain valid. Keeping the
Racket wrapper reachable does not keep an expired target valid.

A @deftech{detached value} contains ordinary copied information rather than an
owned native handle. An RGBA color is a detached value; a paint is not. Detached
values do not need @racket[skia-close!].

A resource predicate recognizes the kind of value, not whether it is open.
Native use and explicit release of an ordinary CPU resource belong to the Racket
thread that created it. A reference to the wrapper does not permit cross-thread
native access.

@bold{Conceptual diagram.} Lifetime relationships are timelines. A CPU surface
owns its borrowed canvas, which becomes invalid when the surface closes; an
independently owned snapshot can remain open afterward. Similarly, a buffer's
pixmap and subset are callback-scoped views even if their wrappers are retained.
This does not generalize every detached result: layouts retain live shapers, and
GPU leases and frames have their own activation and thread rules.

@reference-figure["concept-resource-lifetimes.png"
                  "A time axis shows a CPU surface and its borrowed canvas valid until owner closure, an independent snapshot continuing afterward, and pixmap/subset views valid only during a buffer callback. Gray segments mark invalid views."]

@defproc[(skia-resource? [v any/c]) boolean?]{
Returns @racket[#t] when @racket[v] is an owned resource accepted by the
ordinary Skia resource protocol, and @racket[#f] otherwise. A closed resource
still satisfies the predicate. Borrowed canvases and detached values do not.
This predicate is not a classifier for every object in the separate GPU APIs.
}

@defproc[(skia-closed? [v (or/c skia-resource? canvas?)]) boolean?]{
Returns whether @racket[v] has been closed or its borrowed target has
expired. For a surface canvas, closure follows the surface. Callback and GPU
canvases additionally follow their documented scope. The query does not reopen
an object, activate a context, or prove that a later operation will succeed.
}

@section{Explicit Release}

Explicit release, successful completion, and publication are different actions.
Closing abandoned storage does not finish a document or publish an output file.
GPU contexts and borrowed frame targets have additional activation, generation,
thread, synchronization, and teardown requirements; the CPU rules do not replace
those requirements.

@defproc[(skia-close! [resource skia-resource?]) void?]{
Releases @racket[resource]'s owned native reference. Releasing an ordinary CPU
resource again on its creating thread is harmless. Explicit release cancels its
fallback cleanup; it does not schedule a second native release.

The operation can raise when an exclusive borrow or protected use forbids
closure. A failed close must not be treated as successful release. A borrowed
canvas cannot be closed with this function; close its owner at the permitted
point instead. Resources that retain their own native references to another
object follow the retention rules of their constructors.
}

@section{Scoped Resource Management}

@defproc[(call-with-skia-resource [resource skia-resource?]
                                [proc (-> skia-resource? any)]) any]{
Calls @racket[proc] with @racket[resource] and closes the resource when the call
finishes, including an exceptional or nonlocal exit. On normal completion it
returns the values produced by @racket[proc], unless cleanup raises.

The scope uses a continuation barrier. A continuation cannot be used to re-enter
an ended resource scope and revive its resource. Any returned native resource
must have an independent lifetime; returning the supplied resource or its
borrowed canvas does not keep that resource open.
}

@defform[(with-skia ([resource-id resource-expr] ...) body ...+)
         #:contracts ([resource-expr skia-resource?])]{
Evaluates the resource expressions and closes their results when the body exits.
Only resources introduced by the binding sequence are closed automatically.
Resources created by internal definitions are not added to that sequence.

The resource expressions are evaluated from left to right. Each result is bound to
its identifier for later resource expressions and the body. The body permits
internal definitions and must end in an expression. Successfully acquired
resources are closed in reverse order, including when a later resource
expression or the body raises. The values of the final expression are returned
when cleanup succeeds.

A resource in the binding sequence is closed when the body finishes:

@racketblock[
(define managed #f)
(with-skia ([surface (make-surface 100 100)])
  (set! managed surface))
(skia-closed? managed) ; #t
]

An empty binding sequence manages no resources. In the following example, the
surface remains open after @racket[with-skia] returns. The final call releases
it explicitly:

@racketblock[
(define unlisted
  (with-skia ()
    (define surface (make-surface 100 100))
    surface))
(skia-closed? unlisted) ; #f
(skia-close! unlisted)
]

An ordinary CPU resource created by an internal definition still has fallback
cleanup. The empty binding sequence does not disable that cleanup or make its
timing predictable.
}

@section{Allocation Limits}

@defparam[current-skia-byte-limit limit exact-positive-integer?]{
Controls the byte limit used by checked image and encoding operations. The
initial value is @racket[(* 256 1024 1024)], or 256 MiB. For
@racket[make-surface], @racket[(* 4 width height)] must not exceed this limit.

The parameter is not a process-wide native-memory cap. It does not account for
all native temporaries, driver allocations, or resources already allocated.
Changing it does not resize an existing surface.
}
