#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu skia/gpu-interop))

@title[#:tag "skia-gpu-external-resources"]{External GPU Resources}

@defmodule[skia/gpu-interop #:no-declare]
@(declare-exporting skia/gpu-interop #:use-sources (skia/gpu-interop))

Use a texture handoff when combining Skia with another Metal or Direct3D
renderer that owns the texture. With a backend-specific handoff token,
@racket[gpu-import-image] copies its content into a Skia-owned @tech{GPU image}, while
@racket[call-with-gpu-external-surface] lets Skia draw temporarily into the
external texture. These routes avoid a CPU pixel transfer; they do not permit
both renderers to access the texture concurrently.

An @deftech{external GPU texture handoff} is an opaque, owner-thread token that
coordinates one transfer between a caller-owned native texture and one exact
@tech{GPU context}. The safe API never exposes a native pointer. Backend-specific
constructors that accept native pointers are documented separately in
@secref["skia-gpu-native-handoffs"].

Constructing and using an external texture handoff requires a @tech{GPU activation}
for its exact associated context. Metadata
inspection and explicit token retirement require the creating thread, but not an
active drawing scope.

For one transfer, follow this sequence:

@itemlist[#:style 'ordered
 @item{Prepare the native texture and the producer synchronization required
       by its backend, then create a handoff token in the associated context's
       activation. The token begins in the ready state.}
 @item{Use the token once with @racket[gpu-import-image] or
       @racket[call-with-gpu-external-surface]. The token is active during
       that operation and consumed when the operation ends.}
 @item{Call @racket[gpu-external-texture-close!] when the token is no longer
       needed, including when abandoning an unused token. This retires the
       token and starts cleanup of its native references; it does not close
       the context or an image returned by @racket[gpu-import-image].}]

A validation failure before the handoff begins can leave the token ready.
Once an operation has begun, construct a new token for another handoff rather
than retrying the old one, even if that operation raised an exception.
Successful completion permits reuse of the external storage according to
the backend's synchronization rules. After a completion or cleanup failure,
follow the backend's shutdown rules instead of assuming that storage is
safe to reuse.

An external texture token does not satisfy @racket[skia-resource?] and is not
managed by @racket[with-skia] or @racket[skia-close!]. Use
@racket[gpu-external-texture-close!] to retire a token that is no longer needed.
Retire tokens and close application-owned GPU images and surfaces before
closing their context. Native releases can remain queued until an owner-thread
drain, as described in @secref["skia-gpu-context-shutdown"].

@section{Token State and Retirement}

@defproc[(gpu-external-texture? [v any/c]) boolean?]{
Returns whether @racket[v] is an external-texture handoff wrapper. The predicate
also recognizes consumed and retired wrappers. It does not prove that the
underlying native resource is currently usable.
}

@defproc[(gpu-external-texture-info [texture gpu-external-texture?])
          (and/c hash? immutable?)]{
Returns diagnostic information on the token's creating thread. The
report includes its backend, context generation, handoff state, backend-specific
observations, and @racket['raw_handles_exposed] set to false. The report does
not grant access to, extend, or synchronize the native resource.
}

@defproc[(gpu-external-texture-close! [texture gpu-external-texture?]) void?]{
Retires the token and starts backend cleanup of its native references on the
creating Racket thread, outside a future. If the token is active in a handoff,
the function raises an exception without retiring it. Closing an already
retired token is harmless. The state is marked retired before its
backend retirement action runs, so an indeterminate native retirement is not
silently retried.

Closing a token does not close its GPU context. Queued native releases still
follow that context's owner-side drain and shutdown protocol.
}

@section{Importing External Textures}

@defproc[(gpu-import-image [context gpu-context?]
                           [texture gpu-external-texture?]) gpu-image?]{
Copies the external texture into an independent Skia-owned GPU image in the
token's exact associated @racket[context], consuming the ready token. The
returned image has its own pixel storage and follows the normal GPU-image
lifetime rules.
Backend handoff synchronization and validation occur before control returns.
There is no CPU pixel readback.

The token must belong to @racket[context] and be in the ready state. If it
belongs to another context or is active, consumed, or retired, the function
raises an exception before starting the copy. The operation must run on the
token's creating Racket thread, outside a future. Calling it from another
thread, from a future, or during another external-resource operation also
raises an exception.
}

@section{Borrowing External Drawing Targets}

@defproc[(call-with-gpu-external-surface
          [context gpu-context?] [texture gpu-external-texture?]
          [proc (-> canvas? any)]) any]{
Calls @racket[proc] with a borrowed Skia canvas for drawing into the external
texture, consuming the ready token. The callback's multiple values are
returned. The canvas expires at callback exit. It cannot be used as
an independently owned surface, snapshot source, or native-resource handle.

The token, context, thread, and nesting restrictions of @racket[gpu-import-image]
also apply here; violating them raises an exception before @racket[proc] runs.
The backend verifies that the token is suitable for rendering before entering
the active state. The callback must obey the ordinary canvas-state rules; native
completion and resource retirement still run on exceptional or nonlocal exit.
Drawing performed before an exception is not rolled back. Successful completion
returns ownership of the external storage to the caller according to the
backend's synchronization contract.
}
