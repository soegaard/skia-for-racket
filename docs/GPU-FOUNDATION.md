# GPU contexts and diagnostic rendering

This module is the GPU foundation for the standalone `skia` collection. It uses
Ganesh in the pinned SkiaSharp 3.119.1 library. Requiring `skia` retains the CPU
API and does not import GPU support. Requiring `skia/gpu` defines the optional
API without opening a GUI, loading OpenGL/Metal, or resolving GPU symbols.

The initial public operation is a fixed OpenGL rendering diagnostic. General
GPU surfaces, borrowed drawing canvases, images, uploads, and presentation are
not exposed yet. In particular, existing CPU `surface?`, `image?`, pixmaps and
raster buffers have **not** been reclassified as GPU resources. No GPU pointer
is put into a CPU-owned wrapper with a CPU finalizer.

## Borrow an existing Racket OpenGL host

```racket
(require skia/gpu skia/gpu-racket-gl)

;; gl is a live gl-context<%> from an existing GL-enabled canvas.
(define provider (make-racket-gl-provider gl))
(define context (make-gpu-context provider))
(dynamic-wind
  void
  (lambda ()
    (displayln (gpu-context-info context))
    (define result (gpu-smoke-test context))
    ;; Copied, tightly packed CPU bytes; no GPU object escapes.
    (displayln (hash-ref result 'rgba)))
  (lambda () (gpu-context-close! context)))
```

Run `tools/gpu-doctor.rkt` for a complete host-creation example and the combined
runner in [GPU-TESTING.md](GPU-TESTING.md) for regression and review artifacts.
The diagnostic window does not test presentation, swapping, resizing or HiDPI
frame lifetime. It creates a small Skia-owned offscreen target instead of
assuming a window framebuffer number, size, format or stencil attachment.

`make-racket-gl-provider` borrows its `gl-context<%>`. It owns no window and no
event loop. Keep the host alive through final GPU-context destruction. The
adapter uses Racket's `call-as-current`, checks `get-current-gl-context`, and
independently checks the real CGL/GLX/WGL current-context identity. On macOS this
avoids incorrectly comparing an NSOpenGLContext pointer to a CGLContextObj.
Linux uses GLX: this is not native Wayland or display-server-free EGL support.

## Context operations

| Operation | Contract |
|---|---|
| `(make-gpu-context provider)` | Creates one Ganesh domain for an OpenGL provider on the current Racket thread. Requires working native symbols, a current host and a validated interface. Metal requests raise an explicit unavailability exception. |
| `(gpu-context? value)` | Type predicate, including after closure. |
| `(gpu-context-backend context)` | Selected backend symbol, currently `opengl`. |
| `(gpu-context-generation context)` | Unique process/place-local monotonically assigned generation; not a portable cache key. |
| `(gpu-context-state context)` | Lifecycle symbol: `initializing`, `ready`, `abandoned`, `closing`, or `closed`. Normal successful construction returns `ready`. |
| `(gpu-context-info context)` | Detached immutable diagnostic hash on the owner thread. Includes provider, generation, state, cached native limits/driver identity, live-child and release-queue counts. Cached cache usage is explicitly initial usage, not a live reading. |
| `(call-with-gpu-context context thunk)` | Activates the host and calls a zero-argument procedure synchronously. Preserves multiple values. Reentrant use of the same domain is allowed; nested foreign domains and futures are rejected. |
| `(gpu-smoke-test context)` | Activates the context, makes the private GPU target, draws and reads back the fixed pattern, and returns detached data. No public GPU surface or canvas is returned. |
| `(gpu-drain-releases! context)` | Drains queued child destruction while the context is active, or after successful abandonment without native activation. Returns the number of jobs in the detached batch. |
| `(gpu-context-close! context)` | Owner-thread, idempotent normal teardown, outside an execution scope. Drains queued children, rejects live children/indeterminate releases, then destroys Ganesh while the host is current. |
| `(gpu-context-abandon! context)` | Owner-thread lost-context operation outside all GPU scopes. Calls Ganesh's abandon operation, not release-and-abandon, and does not activate a lost GL host. Invalidates all domain use. It does not free still-live child wrappers or imply normal cleanup. |
| `(gpu-context-request-shutdown! context)` | Sets a shutdown request only; safe to request from another Racket thread. New execution/resource creation is rejected. No GPU call or host activation occurs. |
| `(gpu-drain-pending-contexts! #:abandon? [#f])` | Outside GPU scopes, processes requested domains belonging to the calling thread. Returns diagnostic hashes; failures include `shutdown_error` rather than disappearing. Optional abandonment explicitly takes the lost-context path. |

Context objects are separate from CPU `skia-resource?` values: use
`gpu-context-close!`, not `skia-close!`. Backend/generation/state queries do not
perform native work; `gpu-context-info` and operational APIs check ownership.
Native handles, function resolvers, raw driver constructors, and child lifetime
cells are private. There is deliberately no `auto` backend or CPU fallback.

`exn:fail:gpu:unavailable?` recognizes an initialization capability failure;
`exn:fail:gpu:unavailable-step` identifies the failing step. Invalid arguments,
wrong-thread access, expired scopes, rendering errors and cleanup errors are
not silently converted to a successful fallback.

## Provider protocol

```racket
(make-gpu-provider
 #:name name                    ; symbol
 #:backend backend              ; 'opengl or 'metal
 #:key identity                 ; stable symbol or positive integer
 #:call-as-current activate     ; (zero-argument-thunk -> any)
 #:current? current?            ; (-> any), truthy only for the correct host
 #:describe describe)           ; optional (-> diagnostic-hash)
```

`gpu-provider?`, `gpu-provider-name` and `gpu-provider-backend` are public
queries. Construction does not invoke callbacks. The provider is owned by its
creator Racket thread. `activate` must synchronously call its argument exactly
once on that thread while the correct native context is current. The wrapper
returns the callback's values and does not let the provider hide a callback
failure by catching it and returning normally. The provider is responsible
for host serialization and restoring its own context activation on return.
Saved callbacks cannot be reused, and continuation reentry is barred separately
from any toolkit lock. User callbacks are not wrapped in a frame-wide atomic
section.

The key identifies a real host context, not an arbitrary per-wrapper token.
Provider wrappers for the same live host must use the same key. Two live Ganesh
domains for that identity are rejected. A host destroyed/recreated in place
must get a new provider; the built-in adapter checks the actual native identity
on each use. External adapters are trusted host integrations: the wrapper
cannot independently prove a user-supplied `current?` callback is truthful.

`describe` returns JSON-compatible data: symbol-keyed hashes, strings, lists,
finite numbers and booleans. The OpenGL driver copies it into immutable data.
Do not return native pointers. Provider callbacks must not capture the public
GPU context or resource wrappers through a cycle; the FFI finalizer machinery
has restrictions on self-reachable values. Explicit close remains mandatory
for deterministic shutdown.

At each outermost GL execution entry, Skia's cached GL state is invalidated.
This does **not** restore the host application's GL state on return. Hosts that
interleave other GL drawing must reestablish their own required state. Do not
mix ordinary Racket DC drawing with this GL target.

## Lifetime and shutdown

A GPU domain owns the native Ganesh context, its generation and a native-release
queue. Private child wrappers retain the domain, not the public context wrapper.
Their allocator finalizers invalidate the child and append a release job only.
Explicit child closure also enqueues; destruction runs at activation boundaries
or explicit drains, with children before the context. Unknown failed releases
are quarantined rather than retried, preventing an indeterminate double free.

The context's GC/custodian callback similarly **requests** shutdown. It never
acquires a GUI/GL lock, makes a context current, waits for a GPU, or calls the
application. A rooted domain registry preserves native dependencies until the
owner performs safe teardown. Shutdown requests do not imply synchronous GPU
cleanup at the end of `custodian-shutdown-all`.

Applications must close on the execution-owner thread **before** destroying
the host, shutting down that thread's custodian or ending its event loop. An
owner that has already died cannot be resurrected safely: the implementation
intentionally retains/quarantines that domain until process/place termination
instead of issuing off-thread backend destruction. This is a documented safety
tradeoff, not a claim of automatic leak-free shutdown under arbitrary thread
termination. Inspect returned shutdown errors and drain explicitly while the
owner and provider are still usable.

Normal close rejects live children. Abandonment is different: Ganesh severs
backend use, after which its CPU-side references may be dropped without making
the lost GL context current. Neither operation rolls back prior rendering.
Provider callbacks must remain valid for normal closure. Explicit resource
operations reject another thread; arbitrary native release callbacks are not
part of this public API.

## What the smoke diagnostic proves

The probe allocates an 8x8 RGBA8888-premultiplied Skia render target with no
requested multisampling, verifies its recording/direct context and OpenGL
backend, clears it to transparency, and draws four opaque integer rectangles.
The unequal left/right widths and transparent vertical column expose origin,
channel and alpha mistakes. Every pixel is compared exactly after flush,
submit with CPU synchronization, and explicit RGBA-unpremultiplied readback.
The image is then CPU-detached and encoded through the existing PNG API.

Actual sample count for a Skia-owned target is not exposed by the selected C
API, so the diagnostic reports it as unknown rather than relabeling the request
as an observation. Driver identity, API/profile and maximum sizes are recorded.
Software renderer names such as llvmpipe and SwiftShader are labeled explicitly.
`hardware-reported` is a driver-string classification, not independent hardware
attestation or a performance measurement.

The probe's synchronous completion is intentional for validation. It is not a
proposal to read back or wait after every future presentation frame. Full
flush/submit/wait and public surface/image APIs remain later milestones.

## Metal construction audit

An explicitly invoked macOS probe creates an MTLDevice, a command queue and a
Ganesh Metal context, checks the selected backend, and destroys them repeatedly.
It does not create Metal surfaces or claim Metal rendering/presentation parity.

The pinned legacy header describes transferable device/queue references, but
the implementation actually calls `fDevice.retain(device)` and
`fQueue.retain(queue)`. Those helpers invoke CFRetain. Consequently the probe
retains responsibility for its own Create/new references and releases them on
both success and null failure. It does not donate speculative extra retains.
See [GPU-ABI.md](GPU-ABI.md) for the exact source chain. Construction/teardown
cycles are not a native heap leak measurement; macOS runtime validation remains
required before accepting the Metal path.
