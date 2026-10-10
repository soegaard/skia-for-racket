# Resource lifetimes

This document defines the public lifetime policy for Skia resources.

Skia uses native resources for values such as surfaces, images, paints, paths,
shaders, fonts, and text blobs. Racket can reclaim ordinary owned CPU resources
automatically, but some programs need control over when native storage is
released.

## Ordinary owned CPU resources

An ordinary owned CPU resource has its own native lifetime.

Examples include CPU surfaces, images, paints, paths, shaders, fonts, and text
blobs. These resources have fallback cleanup. After such a resource becomes
unreachable, Racket can reclaim its native resource through the registered
cleanup mechanism.

For example:

```racket
(define image
  (image-from-file "photo.png"))

(draw-image canvas image 20 20)
```

The program does not need to close `image` merely to make its native resource
reclaimable.

Fallback cleanup does not provide a predictable release time. A native resource
can remain allocated after its last use until Racket performs garbage collection
and runs the registered cleanup. Programs must not depend on finalizer timing
for observable behavior.

## Deterministic release

Use `with-skia`, `call-with-skia-resource`, or `skia-close!` when a resource
should be released at a known point.

For example:

```racket
(with-skia ([image
             (image-from-file "large-photo.png")])
  (process-image image))
```

The `with-skia` form closes the resources listed in its bindings when the body
finishes. It also closes them when the body exits because of an exception.

Deterministic release is useful when native storage is large, when temporary
resources are created repeatedly, when native-memory pressure matters, or when
one resource must be released before another operation begins.

Explicit release removes the resource from ordinary fallback cleanup. It does
not schedule a second release for later garbage collection.

## Detached values

Some Skia functions return ordinary Racket values that contain copied
information.

Examples include colors, dimensions, image descriptions, matrix coefficients,
metadata records, and copied byte strings. Detached values do not own native
resources merely because they describe native data. They do not need
`with-skia` or `skia-close!`.

A detached description also does not prove that an associated native resource
is still live.

## Borrowed and scoped values

Some Skia values do not have an independent lifetime.

A canvas returned by `surface-canvas`, for example, borrows the lifetime of its
surface:

```racket
(define canvas
  (surface-canvas surface))
```

The canvas is valid only while its owner is valid. A still-reachable Racket
value can therefore represent an expired canvas.

Other examples include callback-scoped canvases, pixmap views, raster-buffer
borrows, and document-page canvases. Garbage collection does not extend a
borrowed lifetime. These values must follow the lifetime rules of the operation
that produced them.

## Stateful resources

Some resources represent an operation whose successful completion matters
independently of memory reclamation.

Examples include document writers, streams, and codec sessions. Fallback
cleanup can reclaim abandoned native storage, but it does not turn unfinished
work into a successful result. A document that must be finished or published
still requires its documented completion operation.

Fallback cleanup is cleanup of abandoned work, not successful completion.

## GPU resources

GPU resources have additional context, generation, thread, synchronization,
and teardown rules.

Automatic cleanup remains a safety net for native storage, but it does not
replace required GPU scopes, context activation, submission, waiting, or
explicit transfer operations. Programs must follow the lifetime rules of the
GPU API that created the resource.

## Retained dependencies

Some native Skia objects retain resources that they need.

A paint can, for example, retain a shader after the caller closes the original
shader wrapper. Other factories copy or snapshot their inputs instead.

Retention is operation-specific. Do not assume either that every input must
remain open or that every input can safely be closed immediately. The contract
for the operation defines the relationship.

## Practical rule

| Situation | Preferred style |
|---|---|
| Small ordinary owned CPU resource | Use an ordinary Racket binding |
| Large or repeatedly created CPU resource | Prefer deterministic release |
| Borrowed or callback-scoped value | Follow the owner's documented scope |
| Stateful operation | Use its documented completion operation |
| GPU resource | Follow its context and synchronization rules |

Use ordinary Racket bindings for ordinary owned CPU resources when the exact
release time does not matter. Use deterministic cleanup when prompt release
matters. Always follow explicit lifetime rules for borrowed, scoped, stateful,
and GPU resources.

## Implementation note

The current CPU ownership implementation uses `ffi/unsafe/alloc`.
`new-owned` registers `release-owned!` as fallback cleanup, and explicit close
uses the matching deallocator path. Racket's FFI finalizer support is backed by
a late will executor and a dedicated finalizer thread.

This implementation detail explains the current behavior, but user code should
depend on the public lifetime policy above rather than on finalizer internals.
See [native ABI and ownership notes](ABI.md) for lower-level details.
