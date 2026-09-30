# Direct3D 12 offscreen rendering — 0.48

**0.50 extension:** Direct3D now uses the shared document executor and common
scene/image/document/cache/redraw validation. The 0.48-specific exclusions
below describe that original release. Native pin, explicit hardware/WARP
selection and context/resource ownership are unchanged. See
[GPU-BACKENDS.md](GPU-BACKENDS.md) for current wrapper capabilities and gates.

## Scope and acceptance

This stage adds the Ganesh **Direct3D 12** backend on **Windows x64** using the
existing SkiaSharp **3.119.1** library. The public backend name is `direct3d`.
It does not enable SkiaSharp 4.x or Graphite. The starting accepted repository
commit is `00661e2485daaf7d1f015baa4e06e287b121c20c` (0.47, CI run
`36704037723`). The new required Windows WARP job must actually pass before
0.48 has Windows execution evidence; merely defining the job is not acceptance.

Supported in this stage: owned contexts, ordinary GPU-backed surfaces/canvases,
explicit upload/snapshot/subset/readback, retained image graph affinity, cache
controls, owner-side releases, and offscreen rendering. Existing OpenGL and Metal
behavior is preserved. There are no new implicit CPU/GPU transfers.

Not included: DXGI swap chains or window presentation, external D3D resource
borrowing, GPU document raster executors for this backend, adapter enumeration as
a public API, debug-layer certification, device-loss recovery, GPU timestamps,
or performance/physical-display certification. `gpu-canvas%` continues to use
its existing OpenGL/Metal selection. For PDF/SVG output, explicitly detach a CPU
image; do not pass a Direct3D-dependent retained graph to a CPU/document canvas.

## Context selection

```racket
(require skia skia/gpu)

;; Software D3D12: explicit, useful on standard Windows CI machines.
(define software (make-gpu-context #:backend 'direct3d #:adapter 'warp))

;; Hardware: exact DXGI EnumAdapters1 index, not a preference or fallback list.
(define hardware
  (make-gpu-context #:backend 'direct3d #:adapter 'hardware #:adapter-index 0))
```

Create only the contexts needed by the application. With `#:backend 'direct3d`,
`#:adapter` defaults to `hardware`, and `#:adapter-index` defaults to 0. WARP
requires index 0; a nonzero WARP index is rejected. Hardware indices must be
exact nonnegative integers below `#xffffffff`. The selected adapter must match
the requested hardware/software class. A missing adapter, unsupported device,
missing native symbol, or null Ganesh constructor is an error; no other adapter,
backend, or CPU renderer is silently substituted.

`#:adapter` and `#:adapter-index` are Direct3D-only keywords. An external provider
is not accepted for Direct3D in 0.48. Importing `skia`, `skia/gpu`, or the new
private modules does not load DXGI/D3D12, create a device, or import a GUI. Actual
construction checks Windows/x86_64 and layout sizes before loading system DLLs.

The current device creation requests `D3D_FEATURE_LEVEL_11_0` as its **minimum**.
That number does not change the API into Direct3D 11 and is not a claim about the
maximum feature level supported by the adapter. The command queue is a private
DIRECT queue with NORMAL priority, no special flags and node mask 0.

## Drawing and ownership

Use the existing operations inside `call-with-gpu-context`:
`make-gpu-surface`, ordinary `surface-canvas` drawing, `gpu-flush!`, `gpu-submit!`,
`gpu-flush-and-submit!`, `gpu-wait!`, `gpu-upload-image`, `gpu-surface-snapshot`,
`gpu-image-subset`, explicit surface/image readback and `gpu-cache-info`/cache
controls. Surface and image diagnostics report backend `direct3d`; the native
Ganesh backend ID must be 3. CPU surfaces retain their existing CPU behavior.

The domain is bound to its creating Racket thread. A private queue scope is an
ownership token, not an invented OS "current D3D context". Context generation,
canvas-lease expiration, live-child close guards, cross-context image rejection,
and transitive retained-graph affinity are the existing common implementation.
GC and custodian shutdown only queue owner-side work, not COM or Skia calls on
arbitrary finalizer threads.

Construction owns +1 references to adapter, device and queue, and keeps them
until **after** Ganesh destruction. The native C wrapper borrows the descriptor;
Ganesh keeps its own references. Partial construction releases acquired COM
references in queue/device/adapter order. Normal destruction completes pending
work, releases Ganesh, then releases those COM references. Device removal is
checked before activation and teardown; lost/abandoned contexts are retired
without requesting an impossible completion wait. Applications must explicitly
abandon/close after loss; automatic recreation is not provided. Indeterminate
native destruction is not retried by the shared domain.

A readback explicitly waits for completion and returns CPU-owned storage. Closing
a context while live GPU children remain is still an error. Detached CPU images
can be used and encoded after both the surface and the context have closed.

See `examples/gpu-d3d12.rkt` for a complete offscreen example:

```powershell
racket examples/gpu-d3d12.rkt --adapter warp output/d3d12.png
```

## ABI checks

The m119 C entry point `gr_direct_context_make_direct3d` takes
`gr_d3d_backendcontext_t` **by value**, not a pointer. Its Windows x64 layout is
four pointers followed by a one-byte protection flag and padding: 40 bytes,
with the flag at offset 32. The Racket binding uses `_gr-d3d-backend-context`,
not `_gr-d3d-backend-context-pointer`. It uses the existing 0.47 checked shared
native-library handle and is part of the optional GPU registry, not the CPU
mandatory symbol set.

`tools/d3d12-abi` verifies the actual Windows SDK's DXGI adapter descriptor,
queue descriptor, GUIDs and COM vtable slots. A separate C fixture receives the
by-value descriptor and checks sentinel pointer values and both protection-flag
values without dereferencing those pointers. `tools/check-d3d12-call.rkt` calls
that fixture with the selected Racket. This separates marshalling failures from
real device construction. A non-Windows CMake run checks only the host-C layout
mirror; it is explicitly not a Windows SDK or Racket call-ABI pass.

## Required CI

The workflow adds `Required D3D12 WARP / Windows x64 / Racket 9.3` on
`windows-2022`, with the existing pinned checkout, Python, Racket and artifact
actions. It uses a fresh isolated source-package installation via `ci.py`:
no ambient user installation, compiled/native cache, checkout link, or GUI host.
It retains the complete existing CPU tests and native ABI preflight before the
D3D12 extension hook. The hook runs before final source re-verification and
artifact collection. A hook failure propagates; it cannot be changed into a skip
or an ordinary CPU-only pass.

The required D3D12 sequence performs the SDK and Racket call-ABI checks, then
runs **33 surface + 42 image + 20 cache tests** with real Direct3D contexts.
Three additional lifecycle/stress cycles each create two contexts, draw 180
frames from an independently retained GPU-image graph, periodically snapshot,
subset, read back and purge, and close both contexts before encoding a detached
image. Totals: six contexts, 540 frames and nine CPU/GPU/detached PNG artifacts.

An independent Python inspector validates the raw JSON, exact suite counts,
DXGI software flag and selection, adapter identity, backend/context generations,
zero live/pending/failed resources at final checkpoints, explicit submission and
readback boundaries, and every PNG's CRCs, dimensions, decompression and pixels.
It compares pixels against an asymmetric source pattern, not merely CPU/GPU
agreement. The stress scene is intentionally small and deterministic; this is
not a memory-capacity benchmark or a throughput measurement. Ordinary frames
request no explicit CPU wait, but this is not a guarantee that drivers never
block internally.

`CI required` now depends on source, CPU, EGL **and D3D12**. The original CPU/EGL
matrix, m153 rejection investigation and desktop GPU validators are retained.
The WARP job always selects WARP in code; ambient `GPU_MODE` does not weaken it.
No evidence of acceleration or physical display pixels is derived from WARP.
Explicit hardware runs are labelled `hardware-reported`, not certified speedups.

## Reproduce

From an already installed checkout, with the pinned native libraries installed:

```powershell
$env:RACKET = 'C:\Program Files\Racket\Racket.exe'
$env:PYTHONDONTWRITEBYTECODE = '1'
python tools/test-d3d12.py
python tools/validate-d3d12.py --adapter warp
```

The validator requires Python 3.11+, CMake, Visual Studio 2022 C/C++ tools and the
Windows SDK, plus Windows x64 Racket. Adjust `RACKET` to the installed interpreter.
`ci-d3d12.py` provides the full isolated-install/CPU/WARP path used by CI and expects
the released 9.3 interpreter. The local validator checks Windows x64 but does not
require that exact release, allowing the maintainer's development Racket.

For an explicitly selected physical adapter:

```powershell
python tools/validate-d3d12.py --adapter hardware --adapter-index 0
```

The local validator creates a fresh `output/gpu-d3d12-0.48-*` directory, retains
command logs and failures, and verifies (never rewrites) the source manifest at
the end. CI retains `ci-report.json`, `commands.json`, logs, native provenance and
flat JSON/PNG evidence from the installed copy. CMake build products and native
DLLs are not uploaded. SDK/Racket-call success is reported only after those
commands actually pass. A negative or crashed command fails validation.

On macOS/Linux, run the new pure tests and existing platform validators; do not
run the Windows-only validator as an optional skip. CI supplies the Windows gate.

## Pinned implementation sources

- m119 C descriptor and backend IDs: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_types.h
- C by-value context factory: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/gr_context.cpp
- Descriptor mapping: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_types_priv.h
- Ganesh COM holder fields: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/gpu/d3d/GrD3DBackendContext.h
- SkiaSharp's pinned Windows build: https://github.com/mono/SkiaSharp/blob/v3.119.1/native/windows/build.cake
- Microsoft WARP selection: https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgifactory4-enumwarpadapter
- Microsoft queue construction: https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12device-createcommandqueue
