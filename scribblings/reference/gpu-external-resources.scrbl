#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu skia/gpu-interop))

@title[#:tag "skia-gpu-external-resources"]{External GPU Resources}

@defmodule[skia/gpu-interop #:no-declare]
@(declare-exporting skia/gpu-interop #:use-sources (skia/gpu-interop))

Use a texture handoff when combining Skia with another Metal or Direct3D
renderer that owns the texture. With a backend-specific handoff token,
@racket[gpu-import-image] copies its content into a Skia-owned GPU image, while
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

A token is single-use. Its normal states progress from ready to active to
consumed. Explicitly closing an unused or consumed token retires it and starts
backend cleanup of its native references. A validation failure before a handoff
begins can leave the token ready; once an operation has begun, construct a new
token for another handoff instead of retrying the old one.

An external texture token does not satisfy @racket[skia-resource?] and is not
managed by @racket[with-skia] or @racket[skia-close!]. Use
@racket[gpu-external-texture-close!] to retire a token that is no longer needed.

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
creating Racket thread, outside a future. Closing an active token raises. Closing
an already retired token is harmless. The state is marked retired before its
backend retirement action runs, so an indeterminate native retirement is not
silently retried.

Closing a token does not close its GPU context. Queued native releases still
follow that context's owner-side drain and shutdown protocol.
}

@section{Importing External Textures}

@defproc[(gpu-import-image [context gpu-context?]
                           [texture gpu-external-texture?]) gpu-image?]{
Consumes a ready token by making an independent Skia-owned GPU image in the
exact associated @racket[context]. The returned image does not alias the
caller's external storage and follows the normal GPU-image lifetime rules.
Backend handoff synchronization and validation occur before control returns.
There is no CPU pixel readback in the production copy path.

A token belonging to another context or in the wrong state is rejected. The
operation must run on the token's creating Racket thread, outside a future.
Nested external-resource operations are not supported.
}

@section{Borrowing External Drawing Targets}

@defproc[(call-with-gpu-external-surface
          [context gpu-context?] [texture gpu-external-texture?]
          [proc (-> canvas? any)]) any]{
Consumes a ready token by temporarily exposing its external texture as a drawing
target. The @racket[proc] callback receives only a borrowed Skia canvas and its multiple
values are returned. The canvas expires at callback exit. It cannot be used as
an independently owned surface, snapshot source, or native-resource handle.

The backend verifies that the token is suitable for rendering before entering
the active state. The callback must obey the ordinary canvas-state rules; native
completion and resource retirement still run on exceptional or nonlocal exit.
Drawing performed before an exception is not rolled back. Successful completion
returns ownership of the external storage to the caller according to the
backend's synchronization contract.
}
