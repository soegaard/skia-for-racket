# Offscreen GPU surfaces

The OpenGL and Metal backends use the pinned SkiaSharp 3.119.1 / Skia m119
Ganesh C ABI.
Require `skia` for drawing and `skia/gpu` for explicit GPU resource operations.
Requiring either module does not initialize a GUI, open a display or load a
GPU driver. The Racket GL adapter is optional and borrows a host context.
Owned Metal contexts require no GL or GUI host; see [GPU-METAL.md](GPU-METAL.md).

The implementation builds on the context/provider ownership model described in
[GPU-FOUNDATION.md](GPU-FOUNDATION.md). A GPU context is an execution domain;
it is not a replacement set of drawing commands.

## Example

Here `gpu` is an already-created context, for example from
`(make-gpu-context (make-racket-gl-provider gl-context))`. Its host must remain
alive until `gpu-context-close!` completes. Do not create a second Ganesh context
for a host that already has a live domain. Alternatively, use
`(make-gpu-context #:backend 'metal)`; the rest of the drawing and explicit
transfer operations below are unchanged.

```racket
(require skia skia/gpu skia/gpu-racket-gl)

(define image
  (call-with-gpu-context
   gpu
   (lambda ()
     (with-skia ([surface (make-gpu-surface gpu 640 360 #:background 'white)]
                 [paint (make-paint #:color 'blue)])
       (draw-circle (surface-canvas surface) 320 180 100 paint)
       ;; Explicit completion and transfer. Returns an independent CPU image.
       (gpu-surface->raster-image surface)))))

(with-skia ([detached image])
  (save-image detached "circle.png" 'png #:exists 'replace))
;; Close gpu before destroying the application's native GL host.
```

For a complete OpenGL host-creation example run `tools/gpu-offscreen-doctor.rkt`.
Its `--backend metal` mode instead uses owned Metal contexts without a window.
For a visible OpenGL diagnostic run `tools/gpu-window-doctor.rkt --interactive`;
that diagnostic still uses a Racket GL window and is not a Metal presenter.

## Construction and metadata

```racket
(make-gpu-surface gpu width height
                  #:background [background 'transparent]
                  #:color-space [color-space #f]
                  #:sample-count [sample-count 0]
                  #:opaque? [opaque? #f]
                  #:budgeted? [budgeted? #t])
(gpu-surface? value)
(gpu-surface-info surface)
(surface-backend surface)
(canvas-execution-backend canvas)
```

Construction requires the matching active `call-with-gpu-context` scope. The
result is both `gpu-surface?` and `surface?`, and an ordinary `skia-resource?`.
It supports `with-skia`, `call-with-skia-resource`, `skia-close!`, `skia-closed?`,
`surface-width`, `surface-height`, `surface-canvas`, and `surface-color-space`.
A GPU context itself still uses `gpu-context-close!`, not `skia-close!`.

Width and height are pixels, not logical widget coordinates. Dimensions are
positive exact integers, at most the existing 32768 CPU-facing
limit and this context's reported maximum render-target size. The RGBA-sized
allocation/readback budget is checked against `current-skia-byte-limit`.
This is not a bound on total driver, Skia cache, MSAA or VRAM memory.

Storage is RGBA8888, premultiplied alpha by default. `#:opaque? #t` requests an
opaque target and requires an opaque background; it does not preserve meaningful
alpha after arbitrary drawing. Background pixels are initialized explicitly.
`#:color-space` is an optional live color space, retained independently of its
original wrapper. Without it the target is untagged. The canvas remains top-left,
y-down. No floating-point/HDR target or automatic Metal selection is exposed.

`#:sample-count` is an exact integer from 0 through 64 and must not exceed the
native RGBA capability. Skia can round a request to a supported sample count.
For a Skia-owned offscreen target this C ABI has no actual-sample-count getter;
`gpu-surface-info` therefore reports `actual_sample_count` as `#f`, not as a
fabricated zero or the requested value. A request above the capability fails;
it never selects CPU rendering. `#:budgeted?` controls Skia cache accounting,
not a hard physical allocation cap.

`gpu-surface-info` requires a live target in its domain and verifies the native
recording context. It returns immutable metadata including width, height,
backend, generation, color/alpha format, origin, target kind, requested sample
count, reported sample capability and `context_matches`. It exposes no pointers.
`surface-backend` reports immutable backing identity even after close;
`canvas-execution-backend` checks canvas liveness and activation. Execution
backing is distinct from document representation: a detached image embedded in
SVG/PDF is raster content regardless of where its pixels were computed.

## Canvas scopes and destruction

`surface-canvas` returns the existing `canvas?` drawing interface, but a GPU
canvas is borrowed from both its surface and the particular activation in which
it was obtained. It expires on return, exception or continuation escape. Entering
the same context again cannot revive it. A nested activation's canvas expires
with the inner scope; the still-live outer canvas can continue in the outer scope.
Obtain a fresh canvas when reusing a surface in a new activation.

All drawing verifies the creator Racket thread, native context identity, domain
state and generation. Foreign-context, future and cross-thread use rejects.
The GPU surface keeps its public context reachable. Closing a target queues its
native destruction without acquiring a context; activation entry/exit or explicit
owner-side draining performs the release while valid. Closing a target inside a
protected canvas state/layer scope rejects, so cleanup cannot restore a freed
canvas. Other writes are not transactional and are not rolled back on exceptions.

Finalizers only enqueue. They never acquire GUI locks, activate GL, wait for GPU
work or run application code. Normal context close rejects live GPU children;
abandonment is the separate lost-context operation. Explicit shutdown should
finish on the owner before its host window/eventspace is destroyed. A dead owner
can leave a quarantined domain; eventual GC is not a substitute for shutdown.

## Flush, submission and completion

```racket
(gpu-flush! gpu)
(gpu-submit! gpu #:wait? [wait? #f])
(gpu-flush-and-submit! gpu #:wait? [wait? #f])
(gpu-wait! gpu)
```

These operations require the matching active domain. Flush converts pending
Skia commands to backend work. Submit submits that work; it does not flush
pending Skia commands first. The combined operation does both. `#:wait? #t`
requests CPU-visible completion. `gpu-wait!` flushes and synchronously submits,
covering newly recorded as well as previously submitted work. A failed native
submission raises. None of these operations presents a window frame.

Normal window frames use the combined operation without a CPU wait. Readback
uses the synchronous boundary. There is no general fence/completion callback API.

Ordinary drawing protects individual foreign operations using the existing
lifetime boundary, not a whole-frame atomic callback. Explicit flush/submit and
readback callouts are marked blocking for Racket CS and use native pointers plus
raw-allocated descriptors/pixel staging, not movable byte strings. This permits
GC coordination; it is not a GUI event loop, a worker-thread implementation, or
a promise that a slow driver will never block the calling thread. No arbitrary
Racket callback is passed to a native render worker.

## Explicit CPU readback

```racket
(gpu-surface->rgba-bytes surface
                         #:premultiplied? [premultiplied? #f]
                         #:color-space [destination-space #f])
(gpu-surface->raster-image surface)
(gpu-surface-read-raster-buffer! surface buffer)
```

All three require a live active surface and a balanced native save/layer stack.
Finish any `with-canvas-state`/layer scope before reading. Readback flushes and
waits for completion; it is not an asynchronous transfer. Source dimensions and
`current-skia-byte-limit` are checked before allocating output staging.

`gpu-surface->rgba-bytes` returns a detached, tightly packed mutable byte string,
row-major from the top left, R/G/B/A byte order. Default alpha is straight;
`#:premultiplied? #t` retains premultiplied samples. The default output color
space is the source's declared space. Supplying a destination color space asks
Skia to convert samples rather than merely change metadata. Low-alpha 8-bit
unpremultiplication is lossy, as for CPU readback.

`gpu-surface->raster-image` makes an independent CPU-owned `image?`, preserving
the source color-space tag. It currently uses raw readback staging, a copied
Racket byte string, and Skia's copying raster-image constructor. It is not a
zero-copy GPU snapshot. The image remains valid after surface mutation, closure
and complete GPU teardown and can enter existing CPU shader/picture/document
APIs without retaining a GPU execution dependency.

`gpu-surface-read-raster-buffer!` borrows the existing 0.37 native CPU buffer
exclusively. Its dimensions must exactly match. Native readback writes the
active RGBA bytes directly with the buffer's stride and premultiplied alpha;
row padding is untouched. The destination's declared color space controls native
conversion. An active pixmap/canvas borrow rejects before transfer. A dimension
mismatch leaves storage unchanged; an unexpected native transfer failure need
not roll back writes already made. This is CPU memory, not a GPU-mapped pixmap.

## Deliberately rejected implicit operations

`surface-snapshot`, `surface->rgba-bytes`, `surface-pixel`, `surface->png-bytes`,
`save-png`, and consumers that use these CPU helpers reject GPU targets. Use the
explicit functions above and then the ordinary image encoder/bitmap bridge.
GPU images, explicit uploads, GPU snapshots/subsets, and retained graph affinity
are now described in [GPU-IMAGES.md](GPU-IMAGES.md). CPU encoding helpers remain
explicit transfer boundaries; use a detached raster image for those operations.
External texture handles and shared-context access remain outside this API.

Ordinary CPU images and CPU-recorded pictures can be drawn on a GPU target.
`draw-output-group` and `draw-rasterized` reject GPU destinations instead of
silently producing CPU intermediates. Their existing raster/PDF/SVG policies are
unchanged. GPU-assisted document fallbacks are a separate opt-in future feature.
Native Skia may internally implement some operations differently by backend;
a GPU target is not a promise that every primitive has identical pixels or cost.

## OpenGL diagnostic window, not a public presenter

The private diagnostic captures the actual host FBO before Ganesh uses it. It
queries drawable pixels separately from logical widget size, attachment bit
sizes/encoding, stencil, draw buffer and sample count. Unsupported/HDR layouts,
missing entry points or incomplete framebuffers fail rather than guess.

Each frame draws into a Skia-owned offscreen GPU surface, then uses native
surface drawing onto a borrowed host-framebuffer surface cleared to a known
light-gray background, so transparent margins do not expose stale pixels. The host owns that
FBO. The wrapper is released before its descriptor and before host destruction.
Native bottom-left window origin is translated without changing public canvas
coordinates. Framebuffer binding handoff invalidates Skia's cached state; it does
not restore arbitrary host programs, textures or VAOs. The diagnostic owns the
exclusive GL drawing area and does not mix Racket DC drawing into it.

The default tool exercises three window sizes and records submission, swapping,
canvas expiration and zero live/queued wrapper counts. Private instrumentation
records the actual explicit transfer/submission functions used during each frame.
Its report says `visible_pixels_verified: false`: API calls cannot establish
that the monitor displayed correct pixels. Use interactive review for that.
No per-frame explicit readback or CPU completion wait is performed; driver
submission, swaps, resource deletion or teardown may still block internally.

## Sources and validation limits

The C contract is pinned to mono/skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/c/gr_context.h`, `include/c/sk_surface.h`, `include/c/sk_types.h`,
`src/c/gr_context.cpp`, and `src/c/sk_surface.cpp`. See also
[the existing ABI notes](GPU-ABI.md).
Racket reference contracts: `gl-context<%>`, `canvas%` `get-gl-client-size`,
FFI allocation/finalization and blocking foreign callouts. These contracts do
not establish a live driver result.

This implementation was authored with source/context-patch, synthetic Python
and local host-C checks only. No Racket expansion, RackUnit, native GPU run,
visible window review or full-checkout execution was available in authoring.
The maintainer has since supplied passing 0.39/0.40 Mac validation and a 0.39
interactive-window review. Those are historical baseline results, not a new
Metal run. Follow [GPU-METAL-TESTING.md](GPU-METAL-TESTING.md) for current
backend-specific and direct OpenGL/Metal validation.
