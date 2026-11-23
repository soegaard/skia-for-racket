#lang scribble/manual

@(require (for-label racket/base racket/contract (except-in ffi/unsafe ->)
                     skia skia/gpu skia/gpu-interop
                     skia/unsafe/gpu-metal skia/unsafe/gpu-d3d12))

@title[#:tag "skia-gpu-native-handoffs"]{Metal and Direct3D Native Handoffs}

Use these constructors when another renderer owns a Metal or Direct3D texture
that Skia must copy or draw into. Each constructor creates an
@tech{external GPU texture handoff} for the single-use operations in
@secref["skia-gpu-external-resources"]. The supplied command buffer or fence
identifies completion of the external renderer's earlier work, so Skia can
wait before accessing the texture.

The libraries documented here are explicitly unsafe. Their pointer arguments
must already designate live native objects of the stated interface or
Objective-C protocol on the exact device owned by the supplied @tech{GPU context}. A successful
FFI predicate or native interface query cannot make an arbitrary, forged, or
freed address safe. Violating these preconditions can crash the process.

The constructors acquire their own native references to the texture and its
producer synchronization objects. They also keep the associated GPU context
from closing while the token needs it. These references do not permit
concurrent external and Skia access. Close the token with
@racket[gpu-external-texture-close!] when finished; the application's own
native references remain its responsibility.

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
Creates a single-use handoff for a live @tt{MTLTexture}.

The required producer command buffer must already be committed or complete,
use retained references, and belong to the same Metal device. Completion of
that buffer must cover every prior use of the texture. Skia waits for that
completion before copying or drawing. The wrapper verifies device identity
and completion, but cannot check that the producer's commands cover all
earlier uses.

A producer command buffer is required even if the texture's contents were
initialized by a CPU operation such as @tt{replaceRegion}. There is no
separate constructor form that accepts a claim that the texture is already
ready. An arbitrary empty command buffer is not proof that unrelated GPU
work has finished; the same synchronization requirements still apply.

Construction acquires native references to the texture and producer buffer
and keeps the context from closing until those references can be released.

The supported texture storage is RGBA8Unorm 2D storage with one mip level,
array element, depth, and sample. It requires tracked hazards and ShaderRead
usage; drawing additionally requires RenderTarget usage and @tech{premultiplied
alpha}. Unsupported views, heaps, buffers, IOSurface/remote/shareable storage,
managed or memoryless modes, nonidentity swizzles, ShaderWrite, other formats,
arrays, mipmaps, and multisampling are rejected.

The timeout is an exact value from 1 through 60000 milliseconds and applies
separately to each command-buffer completion wait. It is not a deadline for
arbitrary native calls or the application callback. If completion cannot be
established or cleanup fails, the implementation keeps the native references
in quarantine and requests context shutdown. It does not free storage that
the GPU might still be using.
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
Creates a single-use handoff for a live @tt{ID3D12Resource}.

The required fence and positive completion value identify when the external
renderer has finished its earlier use of the resource. The all-ones uint64
value is reserved as the device-loss sentinel and is rejected. Resource and
fence must belong to the exact context device by canonical COM identity.

The supported resource is an unshared DEFAULT-heap, single-level, single-sample
RGBA8 2D texture. Only the ordinary allocation-category heap flags and
ALLOW_RENDER_TARGET resource flag are accepted. Scoped drawing requires that
render-target flag and premultiplied alpha.

The incoming state declares the resource's state when Skia takes access; the
outgoing state specifies the state to leave it in afterward. The wrapper
checks that the names are supported, but cannot verify that the resource
really is in the declared incoming state. The caller is responsible for that
declaration.

Before Skia work, the implementation waits for the producer fence with a
timeout and also makes Skia's GPU queue depend on that fence. Successful
return waits for the relevant queue work to finish and leaves the resource
in the declared outgoing state. The timeout applies separately to each
fence wait, not to arbitrary native calls or the application callback.

The handoff represents one transfer. After a timeout, device loss, or native
cleanup whose outcome is uncertain, the implementation keeps potentially
in-use native references in quarantine and requests context shutdown. It
does not retry a release whose outcome is unknown.
}
