#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia/gpu))

@(define backend-eval (make-base-eval))
@(backend-eval '(require skia/gpu))

@title[#:tag "skia-gpu-providers"]{GPU Backends and Providers}

@defmodule[skia/gpu #:no-declare]
@(declare-exporting skia/gpu)

A @deftech{GPU backend} identifies the graphics interface used by a Skia
@tech{GPU context}. A @deftech{GPU provider} supplies access to a particular native host
context or device. A provider is not a Skia context, a rendering target, or a
promise of hardware acceleration. Context construction and lifetime are
specified in @secref["skia-gpu-contexts"].

Importing the @racketmodname[skia/gpu] library does not load a native graphics
library, create a GPU context, or initialize a GUI. Backend declarations and provider
values can be inspected without creating a rendering target.

@section{Backend Declarations}

@defproc[(gpu-backends) (listof (or/c 'opengl 'metal 'direct3d))]{
Returns @racket['(opengl metal direct3d)], the backend names supported by the
wrapper. This list does not depend on the current platform and does not probe
installed libraries, devices, or drivers.
}

@defproc[(gpu-backend? [v any/c]) boolean?]{
Returns @racket[#t] for @racket['opengl], @racket['metal], or
@racket['direct3d], and @racket[#f] otherwise. Recognition does not establish
that a context can be created.
}

@defproc[(gpu-backend-capabilities [backend (or/c 'opengl 'metal 'direct3d)])
          (and/c hash? immutable?)]{
Returns a declaration of the wrapper's support for @racket[backend].
The hash table contains @racket['backend], @racket['engine], @racket['native_backend],
@racket['owned_context], @racket['platforms], @racket['software_selection], and
@racket['features]. The feature hash table describes offscreen rendering, images,
explicit transfers, cache controls, presentation, document execution, and
external-resource interoperation.

The @racket['scope] is @racket["wrapper-declarations"], and
@racket['runtime_availability] is @racket["not-probed"]. The
@racket['native_probe_performed], @racket['hardware_acceleration_verified],
@racket['visible_pixels_verified], and @racket['performance_measured] fields
are all @racket[#f]. Nested hash tables and strings are immutable. No field in this
result certifies that the selected backend works on the current machine.

@examples[#:eval backend-eval
  (eval:check (gpu-backends) '(opengl metal direct3d))
  (eval:check (gpu-backend? 'vulkan) #f)
  (define declaration (gpu-backend-capabilities 'metal))
  (eval:check (hash-ref declaration 'runtime_availability) "not-probed")
  (eval:check (hash-ref declaration 'native_probe_performed) #f)
]
}

@section{Host Providers}

@defproc[(gpu-provider? [v any/c]) boolean?]{
Returns @racket[#t] for a GPU provider value. The predicate does not call the
provider or check whether its host still exists.
}

@defproc[(make-gpu-provider
          [#:name name symbol?]
          [#:backend backend (or/c 'opengl 'metal 'direct3d)]
          [#:key key (or/c symbol? exact-positive-integer?)]
          [#:call-as-current activate procedure?]
          [#:current? current? procedure?]
          [#:describe describe procedure? (lambda () (hasheq))]
          [#:get-proc-address resolve (or/c procedure? #f) #f]) gpu-provider?]{
Creates a provider value owned by the current Racket thread. Construction checks
callback arities but does not invoke them, activate the host, or load Skia.
The provider stores references to its callback procedures. It does not acquire
or destroy the host context; the caller must keep that host alive until its Skia
context is closed, or use the
explicit lost-host abandonment protocol before destroying it.

The @racket[name] is a diagnostic label. The pair of @racket[backend] and
@racket[key] identifies the native host: reuse the same key for the same host,
and use distinct keys for distinct hosts. The wrapper rejects simultaneous GPU
contexts whose providers claim the same backend and key. Different keys must not
be used to disguise concurrent access to the same native host. A native pointer
is not an accepted key.

The callbacks have the following obligations:

@itemlist[
 @item{The @racket[activate] function accepts one zero-argument callback. It must
       activate the intended host, invoke that callback exactly once, synchronously
       on the provider's creating thread, and keep the host alive and current for the whole call.
       It must not save the callback for later or reenter it through a continuation.
       The callback's multiple values are preserved; the provider's own return
       values do not replace them. Intercepting a callback failure does not turn
       it into success. Host activation failures must be reported as failures.}
 @item{The @racket[current?] function accepts no arguments. It must return a
       true value only when the intended host is current and safe for this thread.
       The wrapper checks this before using the host; it does not create or repair
       a native current-context binding on the provider's behalf.}
 @item{The @racket[describe] function accepts no arguments. It supplies a hash table
       with symbol keys and diagnostic values: strings, booleans, finite
       real numbers, lists of such values, or nested symbol-keyed hash tables. Symbols
       as values, vectors, native pointers, and functions are not accepted.
       The OpenGL constructor copies this information into its context report.}
 @item{The optional @racket[resolve] function accepts a native function name as
       a string and returns a foreign pointer or @racket[#f]. It must resolve
       functions for this host and its graphics standard. It is used synchronously
       while the host is current. Interface assembly reports callback failures
       after returning from the native call rather than allowing them to cross
       native frames.}]

All callbacks must be procedures with no required keyword arguments. The
constructor's positional-arity check does not establish their behavior.

Only external OpenGL providers are accepted by @racket[make-gpu-context].
Provider values for Metal or Direct3D can be constructed, but passing them to
that function raises an unavailability exception; use its owned-device routes.
The EGL adapters use the names @racket['egl-owned] and @racket['egl-current].
Those names also select a default interface route that avoids the native GL
interface factory.
}

@defproc[(gpu-provider-name [provider gpu-provider?]) symbol?]{
Returns the provider's diagnostic name without invoking its callbacks. This
value query does not require its creating thread.
}

@defproc[(gpu-provider-backend [provider gpu-provider?])
          (or/c 'opengl 'metal 'direct3d)]{
Returns the declared backend without checking host availability. This value
query does not require the provider's creating thread.
}

@section{Unavailability Exceptions}

@defproc[(exn:fail:gpu:unavailable? [v any/c]) boolean?]{
Returns @racket[#t] for a GPU-unavailability exception, which is also an
@racket[exn:fail?]. Such an exception reports a supported construction route
that could not obtain a required platform facility, interface, or native context.
It is not a general classification of every GPU error: argument, ownership,
provider-contract, resource, and drawing failures can raise other exceptions.
Catching only this predicate does not turn arbitrary errors into CPU fallback.
}

@defproc[(exn:fail:gpu:unavailable-step [exception exn:fail:gpu:unavailable?]) symbol?]{
Returns the step identifying the unavailable facility. The symbol is diagnostic;
there is no exhaustive public enumeration. The exception message provides the
associated explanation. This library exports no constructor for the exception.
}

@close-eval[backend-eval]
