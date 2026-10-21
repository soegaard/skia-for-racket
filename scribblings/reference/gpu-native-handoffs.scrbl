#lang scribble/manual

@(require (for-label racket/base racket/contract (except-in ffi/unsafe ->)
                     skia skia/gpu skia/gpu-interop
                     skia/unsafe/gpu-metal skia/unsafe/gpu-d3d12))

@title[#:tag "skia-gpu-native-handoffs"]{Metal and Direct3D Native Handoffs}

The libraries documented here are explicitly unsafe. Their pointer arguments
must already designate live native objects of the stated interface or
Objective-C protocol on the exact device owned by the supplied @tech{GPU context}. A successful
FFI predicate or native interface query cannot make an arbitrary, forged, or
freed address safe. Violating these preconditions can crash the process.

The constructors create @tech{external GPU texture handoff} tokens for the
safe, single-use operations in @secref["skia-gpu-external-resources"]. They
retain the native references needed after construction, but those references do not permit
concurrent external and Skia access.

@section{Metal}

These operations require 64-bit macOS and an active Metal GPU context.

@defmodule[skia/unsafe/gpu-metal #:no-declare]
@(declare-exporting skia/unsafe/gpu-metal #:use-sources (skia/unsafe/gpu-metal))

@defproc[(call-with-gpu-metal-device [context gpu-context?]
                                     [proc (-> cpointer? any)]) any]{
Calls @racket[proc] with the borrowed @tt{MTLDevice} used by an active Metal
@racket[context] and returns the callback's values. The private Ganesh command
queue is not exposed. The callback must not reenter Skia GPU execution.

The pointer is borrowed only for the callback. Code that keeps a native object
beyond that scope must acquire and later release its own native reference. This
operation does not create a second device, queue, or context.
}

@defproc[(make-metal-external-texture
          [context gpu-context?] [texture cpointer?]
          [#:producer-command-buffer producer cpointer?]
          [#:timeout-ms timeout (integer-in 1 60000) 5000]
          [#:premultiplied? premultiplied? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f])
         gpu-external-texture?]{
Creates a single-use handoff for a live @tt{MTLTexture}. The producer command
buffer is required, must already be committed or complete, use retained
references, and belong to the same Metal device. Construction retains the
texture and producer buffer and pins the context.

The reviewed storage is ordinary RGBA8Unorm 2D storage with one mip level,
array element, depth, and sample. It requires tracked hazards and ShaderRead
usage; drawing additionally requires RenderTarget usage and @tech{premultiplied
alpha}. Unsupported views, heaps, buffers, IOSurface/remote/shareable storage,
managed or memoryless modes, nonidentity swizzles, ShaderWrite, other formats,
arrays, mipmaps, and multisampling are rejected.

The timeout is an exact value from 1 through 60000 milliseconds and applies separately
to bounded command-buffer completion waits. It is not a wall-clock deadline for arbitrary
native calls or the application callback. The caller promises that the producer command
buffer covers every prior use of the texture; the wrapper verifies device identity and completion,
not the producer's command contents. An indeterminate completion or cleanup
failure quarantines retained references and requests context shutdown rather
than freeing potentially in-flight storage.
}

@section{Direct3D 12}

These operations require 64-bit Windows on x86-64 and an active Direct3D 12 GPU
context.

@defmodule[skia/unsafe/gpu-d3d12 #:no-declare]
@(declare-exporting skia/unsafe/gpu-d3d12 #:use-sources (skia/unsafe/gpu-d3d12))

@defproc[(call-with-gpu-d3d12-device [context gpu-context?]
                                     [proc (-> cpointer? any)]) any]{
Calls @racket[proc] with the borrowed @tt{ID3D12Device} used by an active
Direct3D context and returns the callback's values. The Ganesh command queue is
not exposed. External code can use the device to create its own queue and
resources, but must not reenter Skia GPU execution during the callback.

The borrowed pointer is not an added COM reference. Code retaining a native
object beyond the callback is responsible for acquiring and releasing its own
reference.
}

@defproc[(make-d3d12-external-texture
          [context gpu-context?] [resource cpointer?]
          [#:producer-fence fence cpointer?]
          [#:producer-value producer-value (integer-in 1 #xfffffffffffffffe)]
          [#:incoming-state incoming
           (or/c 'common 'render-target 'pixel-shader-resource 'shader-read
                 'copy-dest 'copy-source)]
          [#:outgoing-state outgoing
           (or/c 'common 'render-target 'pixel-shader-resource 'shader-read
                 'copy-dest 'copy-source)]
          [#:timeout-ms timeout (integer-in 1 60000) 5000]
          [#:premultiplied? premultiplied? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f])
         gpu-external-texture?]{
Creates a single-use handoff for a live @tt{ID3D12Resource}. The required fence
and positive completion value identify producer completion. The all-ones uint64
value is reserved as the device-loss sentinel and is rejected. Resource and
fence must belong to the exact context device by canonical COM identity.

The reviewed resource is an unshared DEFAULT-heap, single-level, single-sample
RGBA8 2D texture. Only the ordinary allocation-category heap flags and
ALLOW_RENDER_TARGET resource flag are accepted. Scoped drawing requires that
render-target flag and premultiplied alpha.

The incoming and outgoing state names are caller declarations. The pinned API
has no general native state getter, so a plausible but false incoming declaration
cannot be certified by this wrapper. Before Skia work, the implementation uses
a bounded producer-fence poll and queue-side dependency. Successful return waits
for the relevant queue work and restores the declared outgoing state. The timeout
is per fence wait, not a deadline for arbitrary native or callback execution.

The handoff represents one transfer. Timeouts, device loss, or indeterminate
native cleanup retain potentially in-flight references in quarantine and request
context shutdown rather than retrying an uncertain destructor.
}
