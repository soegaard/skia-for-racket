# Metal external-resource interop — 0.52

## Purpose and supported boundary

An independently owned Metal producer can supply a texture to the existing
`skia/gpu-interop` operations. `gpu-import-image` returns an independent,
Skia-owned GPU image. `call-with-gpu-external-surface` draws into the caller's
texture but exposes only a scoped Skia canvas. No borrowed image or closeable
external surface is returned to application code.

The native entry point is explicitly unsafe, in `skia/unsafe/gpu-metal`.
The supported subset is deliberately small: macOS 10.15 or later, 64-bit
Racket CS (aarch64 or x86_64), the exact MTLDevice owned by the supplied Metal
context, and ordinary RGBA8Unorm 2D textures. This is the MTLCommandQueue /
MTLCommandBuffer API, not Metal 4 command-queue interoperation.

A texture must have one level, one array element, depth one and one sample,
with explicit ShaderRead usage and tracked hazards. Storage can be private or
shared. Scoped drawing additionally requires RenderTarget usage and
premultiplied alpha. The following are rejected: managed/memoryless storage,
heap allocation, texture views/parents, buffer/IOSurface backing, shareable or
remote storage, nonidentity swizzles, ShaderWrite/unknown usage flags, other
formats, mipmaps, arrays and multisampling. Dimensions are checked against
both the subset's bounds and the actual context's texture/render-target limits.

The factory reads these immutable properties from the actual native objects;
callers do not supply a fabricated dimensions/format descriptor. Exact device
object identity is required, not merely equal device names. Native handles
must already be valid: protocol checking cannot make an arbitrary address or
freed Objective-C object safe.

## API

```racket
(require skia/gpu skia/gpu-interop skia/unsafe/gpu-metal)

(make-metal-external-texture
 context texture-pointer
 #:producer-command-buffer producer-command-buffer-pointer
 #:timeout-ms 5000
 #:premultiplied? #t
 #:color-space #f)

(call-with-gpu-metal-device context proc)
```

The constructor, device callback and interop operations require a live
`call-with-gpu-context` scope for the exact Metal context on its owner thread.
The new module is lazy: requiring it or compiling it does not open Metal,
Objective-C, Skia, a GUI or a window. Optional interop symbols are resolved only
when this path is used; CPU and non-Metal users acquire no new native requirement.

The factory retains the texture and producer command buffer and pins its GPU
context. The producer must already have been committed; a completed buffer is
also accepted. It must use retained resource references and belong to the
same device. `#:timeout-ms` is an exact integer in 1 through 60000, applied
separately to each completion wait. `#:premultiplied?` and color space are
caller declarations; the implementation cannot infer the meaning of pixel data.
Straight-alpha textures are supported as copy inputs, not writable targets.

`call-with-gpu-metal-device` passes only the borrowed device to its one-argument
callback. It never exposes the private Ganesh command queue. An advanced
integration can use the device to create its own queue, textures and producer
command buffers. The caller must retain any native objects kept beyond that
callback and obey normal native lifetimes. Skia GPU reentry from the callback
is rejected. The callback is not wrapped in a long-lived autorelease pool.

The safe token operations retain their 0.51 signatures:

```racket
(gpu-external-texture? value)
(gpu-external-texture-info token)
(gpu-external-texture-close! token)
(gpu-import-image context token)
(call-with-gpu-external-surface context token draw)
```

Tokens are single-use. After one operation, create a fresh token for a later
handoff. A mode validation failure before starting the handoff does not consume
the token; for example, a read-only source rejected for drawing can still be
copied. Explicitly closing an unused token queues owner-side retirement.
Closing a token inside its active callback is rejected. Ordinary successful
operations retire their native token references before returning.

## Example: adapt an external producer

This helper accepts **real, already retained native objects** created by the
application. It does not invent native pointers or create a second Metal device.

```racket
(define (copy-external-metal-image context texture producer)
  (call-with-gpu-context context
    (lambda ()
      (define token
        (make-metal-external-texture context texture
          #:producer-command-buffer producer))
      (dynamic-wind void
        (lambda () (gpu-import-image context token))
        (lambda () (gpu-external-texture-close! token))))))
```

The returned GPU image belongs to `context` and is closed with `skia-close!`,
like other GPU images. It may be used in that context's shaders, paints and
retained pictures. Once the handoff has successfully returned, the producer
can retire or reuse its external texture independently of this image.

For drawing, replace the body operation with
`(call-with-gpu-external-surface context token draw)`. The `draw` procedure
receives a **canvas**, not a surface. Multiple return values are preserved.
Its canvas expires at the end of the handoff even if an outer GPU scope remains
active. Unbalanced save/layer stacks are restored and rejected. An application
exception still runs completion and cleanup; a native cleanup failure takes
precedence because storage safety is then indeterminate.

## Synchronization and ownership

The caller promises that the supplied producer buffer covers every prior use
of the texture, including dependencies on other queues. The wrapper verifies
its device and completion state, not the contents of its command stream. The
report therefore includes `producer_coverage_verified = false`. No other CPU
or GPU writer, including a producer completion handler, may race the handoff.

The sequence is:

1. Flush and submit preceding Ganesh work without requesting a Skia CPU wait.
2. Poll the retained producer buffer until it reaches Completed. Scheduled is
   not completion; Error is a separate failure.
3. Perform the Skia copy or scoped drawing.
4. Flush/submit Ganesh, commit a retained completion buffer to **that exact
   Ganesh queue**, and poll it to Completed.
5. Retire temporary Skia wrappers, the native texture descriptor, the retained
   external references and the context pin before returning control.

This uses the ordered MTLCommandQueue path. Native Objective-C calls have
short per-call autorelease pools. Polling sleeps and application callbacks
run outside those pools. There are no callbacks from Metal into Racket and
no per-handoff runtime helper dylib.

The timeout bounds polling, not arbitrary native driver calls or user drawing.
In particular, Metal command-buffer allocation can block for queue capacity;
this is not a hard real-time operation or a global callback deadline. The
status check observes GPU command completion, not the completion of arbitrary
application work scheduled by native handlers.

Owned-copy input is wrapped only temporarily, then drawn into a fresh
Skia-owned target. It never escapes as an alias into retained graphs. Scoped
Metal drawing uses the external texture directly and needs no D3D12-style
resource-state normalization pass. Nevertheless, neither operation claims a
universal zero-copy guarantee: an owned copy necessarily copies, and Skia may
allocate intermediate GPU resources. There is no CPU pixel staging in either
production operation. Explicit synchronization is not a hidden pixel readback.

On timeout, native command error or indeterminate destruction, the session and
its potentially in-flight references remain quarantined. The context requests
shutdown and cannot resume normal drawing. Destructors are not retried and
storage is not reclaimed merely to make a leak counter green. Such quarantine
can intentionally retain memory until process exit. Correcting an external
producer does not make the old token reusable.

## Validation and evidence

Run on a prepared Mac with the pinned native libraries, Racket, Apple's
command-line developer tools and CMake 3.20 or newer:

```bash
python3 tools/test-metal-interop.py
python3 tools/validate-metal-interop.py --racket "$RACKET"
```

The second command is a required native gate: missing Metal, SDK tools,
compiled fixture, successful completion or correct pixels is a failure, not
an optional pass. It creates a fresh evidence directory and separate persistent
command logs. An existing `--output` directory is refused.

The independent Objective-C++ fixture links Metal and Foundation, not Skia.
It creates its own producer and consumer queues on the supplied device,
uploads an asymmetric 37 x 29 pattern to a private texture, and reads the
actual external target with the independent consumer. A compiled SDK accessor
is compared with Racket's native queries, including the typed four-byte
MTLTextureSwizzleChannels return on both supported architectures.

The live gate requires 33 native cases, three cycles of two independent Skia
contexts, 24 handoffs per context (144 total: 72 copies and 72 drawing scopes),
and 12 actual PNG captures encoded after all six stress contexts close. It
checks translucent and transparent pixels, source retirement, nonaliasing,
retained pictures, expired canvases, rejected native descriptors, callback
errors and normal teardown. Python independently checks the retained PNGs;
matching two incorrect outputs is not a substitute for its expected pixel oracle.

A separate process uses a committed producer waiting on an unsignaled native
shared event. It must observe the specific bounded timeout and retained
quarantine, then unblock its independent producer and exit normally. No abort,
kill, crash dialog or deliberately failed native process is used by this gate.
The report distinguishes deliberate timeout retention from normal leak-free
teardown. Arbitrary invalid pointers are never fed to native methods in tests.

Both existing macOS CPU CI lanes also run `tools/check-metal-interop-sdk.py`.
That compiles the fixture and executes SDK layout/constant assertions without
creating a device. Temporary native build outputs stay outside the uploaded
evidence; SDK receipts and command logs are retained. **This is not a Metal
runtime pass.** Actual Metal acceptance requires the separate local live gate.
Existing required CPU, EGL, Direct3D, DXGI and native-ABI gates remain required.

Success reports do not certify screen pixels, a hardware-speed ranking,
zero-copy behavior or independently attested hardware acceleration. Native
completion is distinct from proving what commands an external producer encoded.

## Primary implementation references

- [Apple MTLTexture](https://developer.apple.com/documentation/metal/mtltexture):
  native immutable texture properties, views and backing storage.
- [Apple MTLCommandBuffer](https://developer.apple.com/documentation/metal/mtlcommandbuffer):
  lifecycle, committed buffers, queue ordering and status.
- [Apple makeCommandBuffer](https://developer.apple.com/documentation/metal/mtlcommandqueue/makecommandbuffer()):
  retained resource references and allocation backpressure.
- [Pinned m119 C backend constructors](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/gr_context.cpp).
- [Pinned m119 surface API](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_surface.h).

The production dependency remains SkiaSharp 3.119.1. This delivery adds no
Graphite, Vulkan, Metal 4, device migration or automatic backend fallback.
