# Offscreen Metal rendering

Import `skia` and `skia/gpu`. Metal changes how a GPU context is created, not
how a canvas is drawn. The existing `surface?`, `canvas?`, `image?`, paint,
shader, filter, text, picture, and resource-ownership interfaces are reused.

## Creating a context

```racket
(make-gpu-context [provider #f] #:backend [backend #f])
```

With an OpenGL provider, omission of `#:backend` retains the established
OpenGL behavior. An explicit backend must agree with the provider. OpenGL
still needs an application-supplied host; it is not created implicitly.

`(make-gpu-context #:backend 'metal)` selects the system's default `MTLDevice`,
creates a private command queue and a Ganesh Metal context, and returns an
owned `gpu-context?`. This path requires 64-bit macOS and a Metal-enabled,
compatible SkiaSharp native library. It requires neither an OpenGL context
nor a caller-supplied window host. The binding does not initialize
`racket/gui`, create a window, or use `MTKView` or `CAMetalLayer`. Text may
still use native font facilities.

An unsupported platform, missing framework/symbol, null device, null queue,
or null Ganesh result raises an explicit exception. The constructor does not
fall back to OpenGL or CPU rendering. `auto`, device selection, external
Metal providers, supplied queues, and texture adoption are not supported by
this constructor. Supplying a provider whose backend is `metal` is rejected
rather than guessing at ownership of external native pointers.

The context belongs to its creating Racket thread. The existing activation,
nesting, continuation, shutdown, and child-close rules apply unchanged.

## Drawing and explicit detachment

```racket
#lang racket/base
(require skia skia/gpu)

(define context (make-gpu-context #:backend 'metal))
(define detached
  (dynamic-wind
    void
    (lambda ()
      (call-with-gpu-context context
        (lambda ()
          (with-skia ([surface (make-gpu-surface context 320 180
                                               #:background 'white)]
                      [paint (make-paint #:color 'blue)])
            (draw-circle (surface-canvas surface) 160 90 55 paint)
            (gpu-surface->raster-image surface)))))
    (lambda () (gpu-context-close! context))))

;; No Metal context is alive here. The detached image is CPU-owned.
(with-skia ([image detached])
  (save-image image "metal-circle.png" 'png #:exists 'replace))
```

`examples/gpu-metal.rkt` renders one of the shared comparison scenes without a
GUI. The shared scene registries are also used by the OpenGL and Metal doctors;
there is no second collection of Metal-specific drawing commands.

## Surfaces, images and retained graphs

`make-gpu-surface` uses the selected Ganesh context and keeps its existing
RGBA8888, premultiplied, top-left contract. The requested sample count and
native capability are reported separately. The C API does not expose the
actual sample count of a Skia-owned target; it remains unknown in that report.
An external OpenGL framebuffer's queryable sample count is a different case.

`surface-backend` and `canvas-execution-backend` report `metal` for Metal
execution. `gpu-surface-info` checks both the native Metal backend ID and
surface/context identity. `gpu-image-info` checks texture backing and image
validity in its owning context. Native pointer values are not public handles.

The following operations are shared by OpenGL and Metal:

```racket
(gpu-upload-image context cpu-image)
(gpu-surface-snapshot surface)
(gpu-image-subset gpu-image x y width height)
(gpu-image->rgba-bytes gpu-image)
(gpu-image->raster-image gpu-image)
(gpu-image-read-raster-buffer! gpu-image raster-buffer)
```

See [GPU images](GPU-IMAGES.md) for keyword options, immutable snapshots,
source-buffer lifetime, residency, color spaces, strided transfers, and the
retained graph contract. A GPU image can be reused through shaders, filters,
runtime children, paints and recorded pictures within the same context. A
parent retains its own native references and context affinity after original
wrappers close. Paint attachment removal does not retroactively change an
already recorded picture.

Two independently created Metal contexts are distinct ownership domains,
even when they select the same device. OpenGL and Metal contexts are likewise
incompatible. Neither a GPU image nor a transitive GPU-dependent graph can be
passed directly to the other domain. To move pixels explicitly:

```racket
;; First, in the source context:
(define cpu-image
  (call-with-gpu-context source-context
    (lambda () (gpu-image->raster-image source-gpu-image))))

;; Then, in the destination context (not nested in the source activation):
(define destination-gpu-image
  (with-skia ([cpu cpu-image])
    (call-with-gpu-context destination-context
      (lambda () (gpu-upload-image destination-context cpu)))))
```

Close `destination-gpu-image` before closing its context. Closing queues
native destruction for owner-side draining; it does not permit arbitrary
cross-thread use. CPU/PDF/SVG drawing, ordinary CPU image encoding/conversion/
subsetting, and GPU-dependent SKP serialization retain their explicit-transfer
requirements. This release does not enable GPU-backed document fallbacks.

## Submission and CPU completion

`gpu-flush!`, `gpu-submit!`, `gpu-flush-and-submit!`, and `gpu-wait!` retain the
same meanings on both backends. Normal GPU reuse need not request CPU
completion. Explicit downloads synchronously complete the transfer.

GPU-image readback still draws into a same-context GPU staging surface before
surface readback, because the pinned C image-readback interface lacks a
context argument. This adds a GPU allocation/draw; it is not a zero-copy or
asynchronous download. Raster-buffer downloads keep their exclusive borrow
and row-padding guarantees.

Context destruction and abandonment may synchronize internally in Skia.
The absence of an explicit application wait during resident drawing is not
proof that every native call is nonblocking, and submission time is not a
GPU-completion benchmark.

## Native lifetime and autorelease pools

The native baseline is SkiaSharp 3.119.1 and mono/skia
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. Its C shim calls the legacy
`GrDirectContext::MakeMetal(void*, void*)` overload. The implementation retains
both device and queue. The wrapper releases its own Create/new references on
success and failure; it does not donate an extra retain based on the older
header's transfer wording. The native Ganesh context keeps the long-lived
references. See [the ABI audit](GPU-ABI.md).

A thread-local Objective-C autorelease pool surrounds each immediate
synchronous native operation. Pools are not left open across application
callbacks, `sleep`, GUI scheduling, or an entire `call-with-gpu-context` body.
A small atomic native-call boundary prevents Racket coroutine switching
between pool entry and exit. It does not put the whole rendering callback in
atomic mode. Reentrant native wrappers share their immediate pool.

GPU-dependent deferred release jobs capture this private native-call scope.
GC and custodian callbacks still only queue work/request shutdown. The owner
performs native destruction inside a fresh pool, including after abandonment.
A dead owner is not silently replaced by a finalizer thread; the existing
quarantine/explicit-close model remains in force.

Sources for the pinned native contract:

- `src/c/gr_context.cpp`: C forwarding and GPU-disabled stubs.
- `src/gpu/ganesh/GrDirectContext.cpp`: `MakeMetal` device/queue retains;
  destructor and abandonment synchronization.
- `include/ports/SkCFObject.h`: retained native reference wrapper.

All are at the mono/skia commit above. Build flags and symbols alone do not
establish a working installed Metal renderer.

## Diagnostics and limitations

`gpu-context-info` includes the Metal device name, actual native backend ID,
queue ownership, native version, limits, cache snapshot and lifecycle counts.
Device-name classification is reported as hardware-reported, software or
unclassified; it is not independent hardware attestation.

The legacy `gpu-doctor.rkt --backend metal` remains a construction-only probe.
Use [the Metal validation sequence](GPU-METAL-TESTING.md) for actual rendering,
image reuse, repeated teardown and OpenGL/Metal comparisons. Metal window
presentation, device enumeration, external interop, asynchronous transfers,
performance conclusions and universal CPU/GPU pixel identity are not provided.
