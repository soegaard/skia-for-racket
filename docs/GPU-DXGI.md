# DXGI / D3D12 window presentation — 0.49

This stage adds explicit Windows x64 swap-chain presentation to the same
`gpu-window%`, `gpu-canvas%`, `gpu-presenter` and scoped `gpu-frame` interfaces
used by OpenGL and Metal. The accepted starting point is 0.48 commit
`b24dc1c2ea6c5dd6d763ff6a6794e7bf87fe8a4e`, CI run `36715835971`.
The new stage requires its own passing Windows/DXGI run before acceptance.

The production native pin remains **SkiaSharp 3.119.1 / ABI 119.0**. No Skia
C++ bridge, native helper DLL, custom window procedure or .NET runtime is
introduced. The native operations use the Windows DXGI/D3D12/Win32 interfaces
and the existing pinned Skia C exports. The extra C/C++ sources are SDK tests,
not a runtime dependency of the library.

## Selecting the backend

```racket
#lang racket/base
(require racket/class racket/gui/base
         (prefix-in sk: skia)
         skia/gpu skia/gpu-gui)

(define (draw frame)
  (define c (gpu-frame-canvas frame))
  (sk:canvas-clear! c 'white)
  (sk:with-skia ([paint (sk:make-paint #:color "#177C9C")])
    (sk:draw-circle c (/ (gpu-frame-width frame) 2)
                      (/ (gpu-frame-height frame) 2) 60 paint)))

(queue-callback
 (lambda ()
   (define window
     (new gpu-window% [label "DXGI / WARP"] [width 640] [height 480]
          [backend 'direct3d] [adapter 'warp] [sync-interval 1]
          [render draw]))
   (send window show #t)))
```

`gpu-window%` and `gpu-canvas%` accept these additional initialization arguments:

| Argument | Default for Direct3D | Contract |
|---|---|---|
| `backend` | Existing `auto` policy | Explicit `direct3d` requires Windows x64 |
| `adapter` | `hardware` | `hardware` or `warp`; there is no fallback |
| `adapter-index` | `0` | DXGI hardware enumeration index; WARP only accepts 0 |
| `sync-interval` | `1` | Exact integer 0 or 1; 0 does not enable tearing |

The omitted values are represented by `#f` before Direct3D defaults are
applied. Supplying these options for a different backend is an argument error.
`auto` is deliberately **unchanged**: Metal on macOS, OpenGL elsewhere,
including Windows. WARP is never selected automatically after a hardware
failure. `hardware` reports a hardware adapter according to DXGI flags, not
an independent hardware/performance certification.

The frame callback, ordinary canvas operations, resize generation, expiration,
queued redraw coalescing, eventspace ownership, and explicit close interfaces
remain the shared contracts documented in [GPU-PRESENTATION.md](GPU-PRESENTATION.md).
The callback exposes a borrowed canvas only: not a closeable surface, texture,
COM object, command queue or persistent back-buffer handle.

## Swap-chain and ownership contract

Racket GUI owns the HWND returned by the canvas's `get-client-handle`. The
presenter borrows this HWND and creates a windowed `IDXGISwapChain3` using the
**exact direct command queue owned by its Ganesh context**. The presenter owns
the swap chain, two back-buffer references, two command allocators/lists, a
fence and its event. It does not destroy the GUI window or install a WndProc.

The reviewed configuration is two RGBA8 UNORM, single-sample, flip-discard
buffers, opaque window composition, and no tearing/fullscreen flags. Returned
swap-chain configuration and actual client extent are checked. Physical and
logical dimensions are reported separately. An invisible, minimized or
zero-sized client area is skipped before buffer acquisition.

One private `dxgi-presentation-host` domain resource pins the GPU context until
the presenter closes. Consequently a ready idle DXGI context has **one** live
host child; this is not a leaked frame. Idle frames have zero live drawables.
After close, live back buffers, host children, queued releases and failed
releases must all be zero. Application-owned GPU images may still prevent
context closure; retire them and retry presenter close, as for other backends.
The already-closed swap chain is not resurrected by that retry.

## Resource states and frame completion

The pinned m119 C API exposes `gr_direct_context_flush_surface` but not the C++
`BackendSurfaceAccess::kPresent` overload. This adapter does **not** call an
unavailable C++ entry point or guess a C++ object layout.

Instead, each acquisition creates a new Skia backend descriptor and a private
SkSurface wrapper with the buffer initially in PRESENT/COMMON state. A mandatory
clear initializes the flip-discard buffer. Only balanced ordinary drawing is
allowed through the borrowed canvas. There is no public snapshot/readback or
external-resource escape path for this surface. With a single-sample draw-only
render target, its final drawing access is RENDER_TARGET.

A normal frame completes as follows:

1. Validate that the callback restored its canvas save/layer stack and that
   the original geometry is still current.
2. Flush and submit Ganesh work on the owned queue.
3. Retire both the SkSurface wrapper and its backend descriptor.
4. Execute a same-queue command list transitioning RENDER_TARGET to PRESENT.
5. Call `Present`, record the returned status, and signal the buffer's fence.

The back buffer itself remains owned throughout. Its next acquisition uses a
fresh PRESENT-state descriptor, not an old Skia state tracker changed behind
Skia's back. The public draw-only restriction is part of this state protocol;
adding frame snapshots, readbacks or external texture access requires revisiting
it. The validation-only readback uses a separate D3D12 copy sequence, not a
Skia read that could alter the final state unexpectedly.

`GetCurrentBackBufferIndex` selects the actual buffer. Before reusing its
allocator/list/resource, the adapter checks the prior fence value and waits if
necessary. **Normal frames perform no CPU pixel readback, but buffer-reuse
waits can block.** Do not interpret `wait_requested: false` in the shared
flush/submit ledger as proof that the presentation implementation never waits.
`blocking_fence_waits` records actual blocking fence waits separately. This is
correctness-oriented pacing, not an isolated GPU timing or latency benchmark.

`DXGI_STATUS_OCCLUDED` is distinct from S_OK: the shared presenter reports a
skipped frame and does not increment successful presents. Future acquisitions
use `Present(TEST)` until drawing can resume. The existing bounded GUI geometry
poll schedules retries; no tight event-queue retry loop is added. Unknown
positive statuses and failing HRESULTs fail closed.

## Resize, cancellation, and failure

Resize first retires prior queue work, flushes/synchronizes Ganesh and releases
its unused resource references. It then releases the old command lists,
allocators and direct back-buffer references before `ResizeBuffers`. All buffers
and lists are reacquired and the swap-chain generation advances. Frame identity
includes the owning context generation and swap-chain generation, not the
rotating buffer index, so normal rotation does not look like a resize.

An exception, close, or geometry change during a yielded drawing callback
cancels presentation. Outstanding save-layers are balanced, drawing is submitted,
wrappers are retired, the buffer returns to PRESENT, and cancellation work is
retired without `Present`. User callbacks remain outside the native
uninterruptible transactions. Native allocations, ownership transfers and
submission bookkeeping delay asynchronous Racket breaks until their references
and state are registered.

Fence waits are bounded to 5,000 milliseconds. The UINT64_MAX completed-fence
sentinel is treated as device removal, not successful completion. Failed waits,
indeterminate submission or destruction are quarantined: references are retained
rather than released while GPU work might still use them. This stage has no
automatic device-loss recovery. A quarantined presenter cannot claim successful
close or be reused; it fails validation. Do not catch that failure and treat it
as an optional skip.

## Validation and evidence

The separate required job is **Required DXGI presentation / D3D12 WARP** on
`windows-2022`, Python 3.12 and Racket CS 9.3 x64. `CI required` depends on both
`d3d12` (the retained offscreen gate) and `dxgi` (this presentation gate).
The new job uses the complete isolated installed-package CPU/native/ABI path;
its extra checks run before source re-verification and temporary-home cleanup.
No cache, ambient native override or success from an earlier run substitutes for
actual execution. An unusable desktop or wholly occluded run is a failure.

SDK checks cover POD sizes/offsets, 22 COM vtable slots, five interface GUIDs and
resource-state/alignment constants. They use compile-time assertions that remain
active in Release builds. Racket's structure-size report is compared with the
SDK report. Non-Windows C mirrors are explicitly labelled as mirrors and cannot
satisfy the required Windows identity/SDK gate.

The runtime doctor executes all **28 shared presenter native cases**, including
hidden/minimized resume, resize during yield, callback errors, unbalanced saves,
frame expiration, foreign-context rejection, queued redraw and close behavior.
It then runs **three cycles of two coexisting windows**, each with three distinct
sizes/captures and **180 normal stress frames** (1,080 stress frames total).
The final report requires two back-buffer indices to have been used, 18 actual
captures, generation advancement and complete cleanup.

The private capture hook uses RENDER_TARGET → COPY_SOURCE, `CopyTextureRegion`
to a READBACK heap with 256-byte aligned rows, then COPY_SOURCE → PRESENT. It
waits for the copy's queue fence, maps/copies the bytes and strips row padding.
The ordinary application path never installs this hook. Captured bytes are
encoded only after both windows/contexts in their cycle have closed. Python
independently decodes the resulting PNGs, verifies CRCs and bounded decompression,
and compares every pixel with a separately constructed asymmetric reference.
Agreement between two equally wrong images is not sufficient.

The run retains `dxgi.diagnostic.json`, `dxgi.inspection.json`,
`dxgi.review.html`, all 18 PNGs and command logs, including failure records.
Normal-frame transfer ledgers and native host counters are checked together.
The reports distinguish successful presentation **submission**, actual
**back-buffer pixel contents**, **visible screen pixels** (not certified), and
**hardware acceleration/performance** (not certified).

Local reproduction, from an updated checkout with native libraries installed:

```powershell
python tools/validate-dxgi.py --adapter warp
# Explicit real-adapter investigation, not the required CI software gate:
python tools/validate-dxgi.py --adapter hardware --adapter-index 0
```

This requires a usable Windows x64 desktop, Racket, Python, CMake, Visual Studio
C/C++ build tools and the Windows SDK. Normal library use does not require the
compiler. Run `racket examples/gpu-dxgi.rkt --adapter warp` for visual review.

## Boundaries

There is no HDR, transparent window composition, fullscreen/tearing mode,
external D3D texture borrowing, D3D document-fallback executor, Graphite or
Windows ARM64 support in this stage. GPU timing and visible screen capture are
also outside this gate. The existing OpenGL/Metal desktop validators and
software EGL/offscreen WARP gates remain required, not replaced.

## Sources

- Microsoft: [D3D12 swap chains](https://learn.microsoft.com/en-us/windows/win32/direct3d12/swap-chains).
- Microsoft: [ResizeBuffers and direct/indirect references](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-resizebuffers).
- Microsoft: [Resource-state barriers](https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-resource-barriers-to-synchronize-resource-states-in-direct3d-12).
- Microsoft: [DXGI overview, occlusion and resizing](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/d3d10-graphics-programming-guide-dxgi).
- Racket: [window interface and native client handles](https://docs.racket-lang.org/gui/window___.html).
- Pinned m119 [C context/surface-access functions](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/gr_context.cpp).
- Pinned m119 [D3D12 backend state handling](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/gpu/ganesh/d3d/GrD3DGpu.cpp).
