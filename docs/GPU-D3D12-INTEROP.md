# Direct3D external-resource interop — 0.51

## Scope

This stage lets an external D3D12 producer and Skia exchange an ordinary 2D
texture on the **same actual device**. It adds independent GPU-image copies
and scoped drawing into externally allocated render targets. The existing
OpenGL interop API is unchanged. Metal descriptors use the same generic
operations starting in 0.52; see [Metal interop](GPU-METAL-INTEROP.md).

The default native library remains SkiaSharp 3.119.1 / m119. The implementation
uses Racket FFI directly; applications do not build or load the validation DLL.
The independently compiled Windows SDK fixture is a test dependency only.

The supported resource is Windows x64, RGBA8 (`R8G8B8A8_UNORM`), DEFAULT heap,
2D, one array element, one mip, one sample and quality zero. Only ordinary
allocation-category heap flags and `ALLOW_RENDER_TARGET` resource flags are
accepted. Render-target borrowing requires that flag and premultiplied alpha.
Image copies also accept non-renderable textures and explicitly declared
straight alpha. Unsupported layouts, formats, heap types and flags fail before
graphics handoff. No shared handles, cross-process/cross-adapter resources,
video/YUV, protected resources, UAV, simultaneous access, HDR or MSAA are added.

## Safe operations and unsafe construction

```racket
(require skia/gpu skia/gpu-interop)

(gpu-external-texture? value)
(gpu-external-texture-info handoff)
(gpu-external-texture-close! handoff)

;; In an active call-with-gpu-context for this exact context:
(gpu-import-image context handoff) ; a new, ordinary GPU image
(call-with-gpu-external-surface context handoff
  (lambda (canvas)
    ;; The argument is ONLY a borrowed canvas, not a surface or native pointer.
    ;; Use ordinary Skia drawing functions here.
    ...))
```

Native-pointer construction is deliberately separate:

```racket
(require skia/unsafe/gpu-d3d12)

;; resource and fence are live COM interface pointers supplied by the producer.
;; The factory queries dimensions/format from the resource, not caller labels.
(define handoff
  (make-d3d12-external-texture
    context resource
    #:producer-fence fence #:producer-value completion-value
    #:incoming-state 'pixel-shader-resource
    #:outgoing-state 'copy-source
    #:timeout-ms 5000
    #:premultiplied? #t
    #:color-space #f))
```

The factory must run in an active context scope. It queries `ID3D12Resource`,
`ID3D12Fence`, device identity and native resource/heap properties; retains its
own COM references; and pins the context through a domain-managed resource.

**Unsafe means unsafe.** Arbitrary addresses, already-freed pointers, wrong
interface layouts and simultaneous access from external code can crash the
process or violate the GPU protocol. QueryInterface cannot validate arbitrary
memory. A live interface pointer must remain valid through construction.
Once construction succeeds, the handoff owns additional COM references.
Those references preserve storage lifetime, not permission to access it
concurrently. The caller must arrange exclusive use until handoff completion.

`call-with-gpu-d3d12-device context proc` lends the device pointer within an
active context. It does not lend the Ganesh queue. A native producer can create
its own queue/resources on this device. The callback must not reenter Skia GPU
execution, save the borrowed pointer without AddRef, or resume through a saved
continuation. External ownership of an added COM reference remains the caller's
responsibility. No device pointer appears in the safe diagnostic API.

## Fences, states and ownership

Every handoff requires a producer fence and a positive uint64 completion value
(excluding the all-ones device-loss sentinel). The fence and resource must
identify the exact context device through canonical COM IUnknown identity;
sharing an adapter name or LUID is not sufficient.

State names are `common`, `render-target`, `pixel-shader-resource`,
`shader-read` (pixel plus non-pixel), `copy-dest` and `copy-source`.
**Incoming/outgoing states are caller declarations, not states queried from
D3D12.** The pinned Skia C API exports no general D3D state getter. A well-typed
but false incoming declaration cannot be detected reliably here. Native
metadata reports that limitation instead of certifying the declaration.

Before submission the implementation observes producer completion with a
bounded CPU fence poll and also inserts an explicit queue-side dependency.
Polling first avoids leaving an indefinitely unsignaled wait on the shared
Ganesh queue. Each wait checks device-removal status. The timeout (1..60000 ms)
is per fence wait, not a total function deadline: application callbacks and
native driver calls themselves do not acquire a hard wall-clock limit.
The CI subprocess runner provides an additional whole-command timeout.

The successful operation returns only after the relevant queue work completes
and the external resource has its declared outgoing state. The caller may
then resume external use or release its reference. There is no asynchronous
return-fence API in this stage. A descriptor represents **one handoff**, not a
persistent texture registration. For another use, construct a fresh descriptor
with the current state and the new producer completion point.

The single-use state machine is `ready -> active -> consumed`. Validation that
fails before handoff leaves it ready; a begun operation cannot be retried through
the same token after failure. Explicit close is idempotent and marks it retired;
closing while active is rejected. Descriptor operations belong to the creating
Racket execution owner and exact context.

Closing an unused descriptor queues owner-side retirement; it still waits for
the promised producer completion before dropping references. Finalizers only
enqueue releases. Use the existing context release-drain/close protocol; an
unused, live handoff prevents context destruction beneath its native references.

## Image copy path

The external resource is first copied with native `CopyResource` into a private
D3D bridge texture. The external source is restored to the outgoing state and
that transfer completes before Skia accesses the bridge. Skia then draws the
bridge into a newly owned GPU surface and returns its snapshot. The returned
image does not alias external storage and participates in normal retained
shader/paint/picture graphs and context-affinity rules.

This intentionally performs a native GPU copy plus a Skia GPU draw. It avoids
relying on an unexported Skia state query for the external source. No CPU pixel
readback or upload is used by the handoff itself. Later explicit application
readback of the returned image is a separate operation.

## Scoped render-target path

A fresh, non-texturable backend render-target wrapper lends only its ordinary
canvas. The callback preserves existing pixels unless it changes them. Its
transform/clip/save state is protected and unwound; unbalanced saves are an
error. The canvas lease expires when this scope ends, even if an outer context
scope survives. It is not a surface and cannot be used for public snapshot or
native-resource extraction.

Arbitrary drawing can leave a backend resource in a state other than
RENDER_TARGET, so scope exit normalizes it: snapshot the non-texturable target
into independent GPU storage, then draw that snapshot through an image shader
and full-target Src rectangle. This final render pass establishes the pinned
backend's render-target state without changing the intended pixel values.
After completion both Skia wrappers are retired, then a native barrier returns
the external resource to its declared outgoing state and a fence completes it.

**This borrowed-target API is not zero-copy.** Its normalization costs a GPU
snapshot copy and draw. It does not hide a CPU staging panel. That conservative
cost is explicit until a reviewed native state-query/transition API can support
a cheaper implementation.

Callback exceptions, arbitrary raised values and outward escapes still unwind
and return the target safely when completion succeeds. Drawing is not a
transaction: pixels changed before an exception are not rolled back. A failed
native completion/destruction overrides ordinary callback success and retains
references in quarantine; the context is not reused for normal drawing.

Indeterminate native failures retain resources until process exit rather than
retrying a destructor or freeing in-flight memory. Public diagnostics distinguish
this from normal clean retirement. This exceptional retention is not advertised
as successful cleanup.

## Required validation

The existing required D3D12 job first runs its original 0.48 and 0.50 checks,
then `tools/ci-d3d12-interop.py`. The latter installs an isolated source package,
fresh pinned natives and the normal Windows CPU checks, then builds the SDK
fixture and executes the interop gate. Its failure fails the existing required
D3D12 job and aggregate; no skip or continue-on-error mode is introduced.

The new workload is:

- 29 real native cases, including aggregate-return GetDesc ABI agreement,
  alpha conversion, copy independence, retained graphs, scope expiration,
  callback errors, invalid native resource shapes and a wrong-device COM double.
- Three cycles with two independent Ganesh contexts each, 24 handoffs per
  context: 72 image copies and 72 borrowed targets, 144 total.
- Twelve actual PNG captures, encoded after all stress contexts close and
  checked pixel-for-pixel by a separately implemented Python oracle.
- A separate, normally exiting process with an unsignaled native fence. It
  must report the specific timeout and quarantine, no resource commands
  submitted, and a shutdown-requested pinned context. Intentional retention in
  that disposable child is not counted as leak-free normal teardown.

The producer/consumer DLL does not link Skia or call its drawing functions. It
creates its own producer and consumer queues on the supplied device. Copy tests
drop the producer's texture reference and close the producer before reading the
Skia-owned result. Borrow tests read the actual external resource using the
independent consumer queue, after the documented synchronous handoff.

The wrong-device probe is explicitly a Windows SDK COM test double with a
foreign canonical identity; it does not pretend WARP provides a second adapter.
State-name validation and actual barrier execution are tested, but no report
claims that a lying incoming-state declaration was discovered by a state query.

Local Windows reproduction, with natives, Python, Racket, CMake, MSVC C/C++ and
the Windows SDK installed:

```powershell
python tools/validate-gpu-interop.py --adapter warp
python tools/validate-gpu-interop.py --adapter hardware --adapter-index 0
```

The source/inspector tests are cross-platform:

```bash
python3 tools/test-gpu-interop.py
"$RACKET" run-tests.rkt --pure
```

Normal validation retains command logs, SDK and Racket diagnostics, raw pixels,
source fingerprints and an independent inspection. Success is published last.
WARP is software correctness evidence, not hardware acceleration, physical
screen output, performance or universal format/device certification.

## Source and implementation references

The state normalization is specific to the checked m119 ABI. In particular,
non-texturable surface snapshots copy their source, and the D3D operations
render pass puts the single-sample root target in RENDER_TARGET before drawing.
A future native profile must review these assumptions rather than relaxing the
ABI guard.

- [Pinned m119 surface snapshot implementation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/gpu/ganesh/surface/SkSurface_Ganesh.cpp)
- [Pinned D3D render-pass transitions](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/gpu/ganesh/d3d/GrD3DOpsRenderPass.cpp)
- [Pinned C context/texture declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/gr_context.h)
- [Microsoft D3D12 resource-barrier rules](https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-resource-barriers-to-synchronize-resource-states-in-direct3d-12)
- [Microsoft command-queue Wait](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12commandqueue-wait)

The source baseline is `ae29c9ffa3556ec18a068f80d17f673a8cadb093`. Its 0.50
aggregate was pending at implementation start; this stage does not reinterpret
an unfinished dependency-install lane as a pass. Acceptance of 0.51 requires
its own host/CI evidence. Metal interop is next, then the agreed `skia-dc%` and
`skia-canvas%` compatibility work rather than new GPU backends.
