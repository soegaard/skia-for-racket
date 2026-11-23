#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/gpu skia/gpu-interop))

@title[#:tag "skia-resources"]{Resources and Lifetimes}

Skia uses native resources alongside ordinary Racket data. Resource kind,
ownership, and scope determine when a value remains valid and how it should be
released.

@local-table-of-contents[#:style 'immediate-only]

@section{Resource Kinds and Validity}

An @deftech{owned resource} has a Racket wrapper responsible for releasing its
native reference. Owned resources can use CPU or GPU storage; ownership and
where the resource is used are separate distinctions.

An @deftech{ordinary CPU resource}, such as a CPU @tech{surface} or @tech{paint},
is an owned resource with fallback cleanup after it becomes unreachable.
Ordinary Racket bindings are sufficient when the exact release time does not
matter. Fallback cleanup has no predictable timing; use explicit release when
its timing matters. GPU resources have additional requirements described in
their entries.

A @deftech{borrowed canvas} has no independent native lifetime. Its owner and
any callback or @tech{GPU activation} that supplied it must remain valid. Keeping the
Racket wrapper reachable does not keep an expired target valid.

A resource predicate recognizes the kind of value, not whether it is open.
Native use and explicit release of an ordinary CPU resource belong to the Racket
thread that created it. A reference to the wrapper does not permit cross-thread
native access.

The figure below shows how these lifetimes are related. A CPU surface
owns its borrowed canvas, which becomes invalid when the surface closes; an
independently owned snapshot can remain open afterward. Similarly, a buffer's
@tech{pixmap} and subset are callback-scoped views even if the caller keeps references
to their wrappers. @tech{Text layouts} own private font snapshots and must remain open when drawn;
the caller's original @tech{shaper} and font manager can be closed independently.
@tech{GPU leases} and @tech[#:key "GPU frame"]{frames} have their own activation and thread rules.

@reference-figure["concept-resource-lifetimes.png"
                  "A time axis shows a CPU surface and its borrowed canvas valid until owner closure, an independent snapshot continuing afterward, and pixmap/subset views valid only during a buffer callback. Gray segments mark invalid views."]

@defproc[(skia-resource? [v any/c]) boolean?]{
Returns @racket[#t] when @racket[v] is an @tech{owned resource} accepted by the
ordinary Skia resource protocol, and @racket[#f] otherwise. A closed resource
still satisfies the predicate. Borrowed canvases do not.
GPU surfaces and GPU images satisfy this predicate, but GPU contexts,
presenters, and external-texture handoff tokens do not. Their cleanup
operations are listed in @secref["skia-resource-cleanup"].
}

@defproc[(skia-closed? [v (or/c skia-resource? canvas?)]) boolean?]{
Returns whether @racket[v] has been closed or its borrowed target has
expired. For a surface canvas, closure follows the surface. Callback and GPU
canvases additionally follow their documented scope. The query does not activate
a GPU context. An open resource must still satisfy the thread and activation
requirements of the operation that uses it.
}

@section[#:tag "skia-resource-cleanup"]{Explicit Release}

Closing a resource, finishing a document, and saving a file are separate operations.
Closing abandoned storage does not finish a document or save an output file.
@tech{GPU contexts} and borrowed frame targets have additional activation, generation,
thread, synchronization, and teardown requirements; the CPU rules do not replace
those requirements.

Choose the cleanup operation according to the kind of value:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Value} @bold{Cleanup} @bold{Accepted by @racket[with-skia]?})
  (list @elem{An owned @racket[skia-resource?], including GPU surfaces and images}
        @racket[skia-close!] "Yes")
  (list @elem{A @tech{GPU context}} @racket[gpu-context-close!] "No")
  (list @elem{An @tech{external GPU texture handoff}}
        @racket[gpu-external-texture-close!] "No")
  (list @elem{A @tech{GPU presenter}} @racket[gpu-presenter-close!] "No")
  (list @elem{A @tech{borrowed canvas}, including a frame canvas}
        "Do not close independently" "No"))]

For a context needed only during one computation,
@racket[call-with-new-gpu-context] obtains a new context from a creation
callback, activates it for a drawing callback, then closes it. The drawing
callback must still close the GPU-dependent resources it creates, typically
with @racket[with-skia], before returning. A presenter's
context instead belongs to the presenter and must not be closed separately.
Close a GUI widget through its own close method; see
@secref["skia-gui-cleanup"].

Use @racket[call-with-gpu-external-texture] for scoped token retirement.
It does not activate or close the context and does not manage imported images.

These cleanup functions are not interchangeable. Follow each entry's thread,
activation, and failure rules; ending a drawing callback or marking a wrapper
closed does not necessarily mean that all native cleanup has completed.

@defproc[(skia-close! [resource skia-resource?]) void?]{
Releases @racket[resource]'s owned native reference. Releasing an ordinary CPU
resource again on its creating thread is harmless. Closing it from another
Racket thread raises an exception, even if it is already closed. Explicit
release cancels its fallback cleanup.

Some operations require a resource to remain open throughout a callback. For
example, closing a raster buffer during @racket[call-with-raster-buffer-pixmap],
or a target surface during @racket[call-with-overdraw-canvas], raises an
exception. Follow the enclosing operation's rules for when closure is allowed;
a failed close must not be treated as successful release.

A borrowed canvas cannot be closed with this function; close its owner at the
permitted point instead. A resource may keep another native object alive through
its own reference to that object; see the constructor's rules for its input
resources.
}

@section{Scoped Resource Management}

Use @racket[call-with-skia-resource] or @racket[with-skia] when resources should
be closed as soon as a computation finishes, including when it raises an
exception. If cleanup itself raises an exception, that exception propagates in
place of any exception already being raised by the computation.

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
@racket[make-surface], which uses four bytes per pixel,
@racket[(* 4 width height)] must not exceed this limit.

The parameter is not a process-wide native-memory cap. It does not account for
all native temporaries, driver allocations, or resources already allocated.
Changing it does not resize an existing surface.
}
