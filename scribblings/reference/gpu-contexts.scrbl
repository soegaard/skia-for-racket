#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-contexts"]{GPU Contexts and Lifetimes}

@(declare-exporting skia/gpu)

Manage a GPU context explicitly when you need offscreen GPU drawing or want
to reuse GPU surfaces and images across several rendering operations. Create
it with @racket[make-gpu-context] and perform GPU work within
@racket[call-with-gpu-context]. For window drawing, the
@seclink["skia-gpu-widgets"]{GPU widgets} can manage the context for you.

A @deftech{GPU context} owns Skia's connection to one native graphics host and
tracks its GPU-dependent resources. A @tech{GPU provider} activates that host.
Context creation is explicit: importing a library, recognizing a backend name,
or constructing options does not create a context.

A context belongs to its creating Racket thread. GPU execution and teardown
must run on that thread, not in a future. Entering a context does not transfer
ownership to a different thread. A context is managed with
@racket[gpu-context-close!], not @racket[skia-close!] or @racket[with-skia].
The ordinary resource protocol still manages its GPU-dependent child resources.

@local-table-of-contents[#:style 'immediate-only]

@section{Construction}

@defproc[(gpu-context? [v any/c]) boolean?]{
Returns @racket[#t] for a GPU context wrapper, including one that has been
abandoned or closed. This predicate does not test native usability.
}

@defproc[(make-gpu-context [provider (or/c gpu-provider? #f) #f]
          [#:backend backend (or/c 'opengl 'metal 'direct3d #f) #f]
          [#:adapter adapter (or/c 'hardware 'warp #f) #f]
          [#:adapter-index index (or/c (integer-in 0 4294967294) #f) #f]
          [#:options options (or/c gpu-context-options? #f) #f]
          [#:gl-interface interface (or/c 'default 'auto 'desktop 'gles 'webgl) 'default])
          gpu-context?]{
Creates a ready context on the current Racket thread and registers shutdown
notification with the current custodian. Construction cannot occur inside any
GPU execution scope or a future. The provider, when supplied, must belong to
the creating thread.

When @racket[backend] is @racket[#f], the provider supplies its backend. Supplying
neither a provider nor a backend raises an exception: there is no automatic
platform selection or CPU fallback. An explicit backend must agree with the
provider's declaration.

@itemlist[
 @item{The @racket['opengl] backend requires an explicit host provider. The host
       must remain available for normal execution and closure. Closing the Skia
       context does not destroy the caller's external host.}
 @item{The @racket['metal] backend creates and owns a device and queue on macOS.
       Omit the provider. External Metal providers are not accepted.}
 @item{The @racket['direct3d] backend creates and owns a Direct3D 12 device and
       queue on Windows. Omit the provider. The default adapter selection is
       @racket['hardware], with index @racket[0]. The explicit @racket['warp]
       selection requests software execution and requires index @racket[0].
       No failed hardware request silently falls back to WARP.}]

Adapter options other than @racket[#f] are rejected outside Direct3D. For example,
@racket[(make-gpu-context #:backend 'metal)] requests the owned Metal route;
@racket[(make-gpu-context provider)] uses the supplied OpenGL host.

The @racket[options] argument selects native defaults or an explicit immutable
request, as described in @secref["skia-gpu-context-options"]. The returned report
identifies that request; it is not an effective-options readback.

The @racket[interface] argument selects OpenGL interface construction. Values
other than @racket['default] are rejected for Metal and Direct3D:

@itemlist[
 @item{The @racket['default] route first tries the native GL interface, except
       for the EGL adapters. When no interface is obtained and a resolver exists,
       it tries desktop GL assembly through that resolver. It does not fall back
       to GLES or WebGL.}
 @item{The @racket['auto] route assembles an interface using the provider's
       resolver and the host's reported graphics standard.}
 @item{The @racket['desktop], @racket['gles], and @racket['webgl] routes require
       a resolver and a matching current host standard. They select an interface
       for an existing host. They do not create a different kind of host.}]

Unavailable facilities can raise @racket[exn:fail:gpu:unavailable?]. Other
failures retain their ordinary exceptions. Construction is not a benchmark or
verification of hardware acceleration. A failure after a native context has
been created can leave a pending shutdown record for owner-thread cleanup;
@racket[gpu-drain-pending-contexts!] reports those records.
}

@section{Execution Scopes}

@defproc[(call-with-gpu-context [context gpu-context?] [thunk (-> any)]) any]{
Activates the context's provider, calls @racket[thunk] without arguments, and
returns its multiple values. The context must be ready, with no shutdown
request, on its owning thread. This function does not close the context.

A @deftech{GPU activation} is one execution scope established by this call.
It keeps the context's native host current while the callback runs.

Nested scopes for the same context are supported without reactivating the
provider. Nesting a different context is rejected. At the outermost entry,
Skia's cached assumptions about native state are reset. Pending resource
releases are drained at entry and exit. This does not restore the host's OpenGL
state after the call, submit all pending drawing, wait for GPU completion, or
present a window.

The host must remain current throughout the scope. A @deftech{GPU lease}
limits a borrowed GPU canvas to the activation that supplied it. A canvas
obtained in an inner scope expires when that scope exits, even if an outer scope for the same
context remains active. Entering the context again does not revive old canvases.

Cleanup retires the activation after normal return, an exception, or an escape.
Reentry through a saved continuation is rejected. State cleanup is not pixel
rollback, and a release failure can leave the context requiring explicit cleanup.

The following helper creates and enters a context when called, then closes it
on exit. The callback must retire all GPU children it creates before returning.
A failed close is not silently replaced with abandonment.

@racketblock[
(require skia/gpu)
(define (call-with-new-gpu-context proc #:backend backend #:provider [provider #f])
  (define context (make-gpu-context provider #:backend backend))
  (dynamic-wind
    void
    (lambda () (call-with-gpu-context context (lambda () (proc context))))
    (lambda () (gpu-context-close! context))))
]

On macOS, when a Metal context can be created, the following expression returns
context information and closes the context before returning:
@racket[(call-with-new-gpu-context gpu-context-info #:backend 'metal)].
Defining the helper alone creates no context.
}

@section{Identity and State}

@defproc[(gpu-context-backend [context gpu-context?]) (or/c 'opengl 'metal 'direct3d)]{
Returns the selected backend. This stored-value query requires no active scope
or owning thread and remains available after closure.
}

@defproc[(gpu-context-generation [context gpu-context?]) exact-positive-integer?]{
Returns the context's generation identifier. Generations distinguish context
instances and remain unchanged after closure. They are not persistent device
identifiers. This stored-value query requires no active scope or owning thread.
}

@defproc[(gpu-context-state [context gpu-context?])
          (or/c 'initializing 'ready 'releasing 'release-failed 'abandoned 'closing 'closed)]{
Returns the current wrapper state without requiring an active scope or owning
thread. A successful constructor returns a @racket['ready] context.
A @racket['ready] result alone is not a usability test: a pending shutdown
request also prevents execution, and a lost native host can fail later checks.

The @racket['initializing], @racket['releasing], and @racket['closing] states
cover construction and teardown. A @racket['release-failed] result means that
healthy-host release-and-abandon had an indeterminate outcome. Such a context
is quarantined: normal release, abandonment, and closure must not retry it.
An abandoned context cannot resume drawing; a closed context has finished
releasing its tracked native ownership.
}

@defproc[(gpu-context-info [context gpu-context?]) (and/c hash? immutable?)]{
Returns context information on the owning Racket thread, outside a
future. No active GPU scope is required, and the query remains available after
abandonment or closure. It does not activate the provider or refresh native
capability and cache measurements.

The hash table combines construction-time diagnostics with current wrapper fields:
@racket['backend] and @racket['provider] are strings; @racket['generation] is
an exact positive integer; @racket['state] is a string; @racket['live_children],
@racket['pending_releases], and @racket['failed_releases] are counts; and
@racket['shutdown_requested] is a boolean. Child counts concern tracked resource
references, not a count of every native allocation.

The @racket['context_factory], @racket['context_options_source], and
@racket['context_options] fields record construction choices. The
@racket['context_options_native_readback] field is @racket[#f]. Native limits,
initial cache measurements, and provider details are snapshots, not promises
that the device remains usable or that current resource usage is unchanged.
}

@section{Release, Abandonment, and Shutdown}

@defproc[(gpu-context-close! [context gpu-context?]) void?]{
Closes a context on its owning thread, outside every GPU execution scope.
Pending releases are drained first. Closure then requires no live GPU children
and no indeterminate native release records. A live-child failure does not
silently close those children; retire them and retry closure.

A ready context's provider is activated for teardown. An abandoned context
can release its remaining ownership without activating a lost host. A successful
close releases the context and any separately owned device and queue, unregisters
its custodian notification, and changes its state to @racket['closed]. Repeated
close is harmless, but still subject to thread and scope restrictions.

A native destructor with an indeterminate outcome is not retried. Its record
remains quarantined instead of risking double destruction. Close does not
promise that unsubmitted drawing is preserved or that results are copied to CPU
memory; arrange any required submission, completion, or transfer before teardown.
}

@defproc[(gpu-context-abandon! [context gpu-context?]) void?]{
Marks a context abandoned on its owning thread, outside all GPU execution
scopes. This is the lost-host route: it does not activate the provider. Use it
when the host is no longer safe to activate, not as a substitute for normal
successful rendering or as a request to clear pixels.

Successful abandonment prevents future drawing and invalidates borrowed canvases.
It does not close child wrappers or release the context itself. Retire the
children with @racket[skia-close!], then use @racket[gpu-context-close!].
Repeated abandonment of an abandoned or closed context is harmless. A context
in @racket['release-failed] is rejected rather than retried through this route.
}

@defproc[(gpu-context-release-and-abandon! [context gpu-context?]) void?]{
Releases native resources and abandons a ready context while its host is still
usable. The operation runs on the owning thread, outside all GPU execution
scopes, and requires no pending shutdown request. Unlike
@racket[gpu-context-abandon!], it activates the provider, checks native state,
drains releases, and invokes the healthy-host release operation.

Success leaves the context abandoned, not closed. Live children are not silently
retired, and the native context and owned host handles remain until final close.
The operation does not promise completion of prior drawing or preserve
unsubmitted content. It is not a CPU fence or a readback.

If the native release operation or its abandonment postcondition fails, the
state becomes @racket['release-failed] and shutdown is requested. The context is
quarantined; neither this function, lost-host abandonment, nor normal closure
retries the indeterminate operation. Failure before that operation begins does
not by itself establish that native resources were released.
}

@defproc[(gpu-context-request-shutdown! [context gpu-context?]) void?]{
Requests shutdown without activating a provider, waiting for the GPU, releasing
native objects, or running application callbacks. This operation may be called
from another Racket thread. It is harmless for an already closed context.

The request flag is separate from @racket[gpu-context-state]. It prevents new
execution and invalidates borrowed canvases, but does not force the state to
@racket['closed] or close live children. The owning thread must retire children
and perform closure or drain pending context shutdowns. GC and custodian
notifications use this request mechanism; they do not perform off-thread native
teardown. A dead owner can therefore leave resources retained for safety.
}

@defproc[(gpu-drain-releases! [context gpu-context?]) exact-nonnegative-integer?]{
Drains queued child-resource releases on the owning thread and returns the
number of release jobs processed by that call. It does not collect garbage or
retire live wrappers. A ready or closing context requires the correct active
GPU scope. An abandoned context requires no current host.

Pending jobs are removed from the queue before processing. A failed release is not
retried: its record is quarantined, the remaining jobs are attempted, and an
exception is raised instead of returning a successful count. There is no
successful drain for a closed or @racket['release-failed] context.
}

@defproc[(gpu-drain-pending-contexts! [#:abandon? abandon? boolean? #f])
          (listof (and/c hash? immutable?))]{
Attempts shutdown for pending contexts owned by the calling Racket thread.
It must run outside GPU execution scopes. The result contains one
context report for each selected context; the order is unspecified. Contexts
owned by other threads are not processed.

With @racket[abandon?] false, normal closure requires an available host. With
@racket[abandon?] true, the lost-host abandonment operation is attempted first.
Neither mode silently retires live children. If one shutdown raises a value satisfying
@racket[exn:fail?], its report contains a @racket['shutdown_error] string and processing
continues. Other raised values are not converted into reports. Inspect the
reports: returning a list does not imply that every selected context closed.
This operation does not drain presenter or GUI-window shutdowns.
}
