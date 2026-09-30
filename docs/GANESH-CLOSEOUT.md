# Ganesh closeout and Racket drawing compatibility — 0.52

## Decision

After 0.52 passes host and CI acceptance, stabilize the current Ganesh layer
instead of adding another GPU engine or backend. Continue correctness, safety,
packaging and portability fixes. Vulkan, Graphite, native SkiaSharp 4.x
migration, HDR, cross-process/cross-adapter resources and wider format support
are **deferred**, not silently enabled by this closeout.

The next development priority is a genuine Skia implementation of Racket's
`dc<%>` interface and then a GUI canvas that exposes it to existing programs.
This is a roadmap change, not an assertion that the DC or GUI classes already
exist in 0.52.

## What the GPU layer covers

| Area | OpenGL | Metal | Direct3D 12 |
|---|---|---|---|
| Offscreen surfaces and ordinary drawing | Existing | Existing | Existing |
| GPU images, retained graphs, explicit transfers | Existing | Existing | Existing |
| Cache controls and shared stress tooling | Existing | Existing | Existing |
| Bounded document raster executor | Existing | Existing | Added in 0.50 |
| Window presentation | Existing host framebuffer | Existing CAMetalLayer | DXGI in 0.49 |
| External texture copy / scoped drawing | Existing specialized GL API | Added in 0.52 | Added in 0.51 |

The shared token operations in `skia/gpu-interop` now work with Metal and
Direct3D factories. OpenGL retains its established `skia/gpu-gl-interop` API;
this release does not rename it or pretend native GL, Metal and D3D resource
contracts are identical. Metadata in `gpu-backend-capabilities` describes
wrapper functionality only. It is not evidence that a device exists or that a
particular machine has passed rendering validation.

Owned interop copies return independent GPU images. Borrowed targets expose
only scoped canvases. Native pointer ingress remains in explicitly unsafe
modules. Owner-thread, context-affinity, single-handoff, completion and
quarantine rules remain part of the contract, not performance options to
remove in the compatibility layer.

## Evidence boundaries retained

The production native pin remains SkiaSharp 3.119.1 and the established
HarfBuzzSharp pin remains 8.3.1.2. CPU imports still do not initialize GPUs or
GUIs. The GUI `auto` choice is unchanged; explicit backend/adapter requests
never silently become WARP, another backend or CPU drawing.

Existing required Linux EGL/llvmpipe and Windows D3D12/WARP jobs establish
software correctness for their tested paths. SDK layout/constant checks do
not establish device execution. The 0.52 macOS CI addition deliberately
compiles and checks the Apple SDK fixture only. Actual Metal interop requires
`tools/validate-metal-interop.py` on a prepared Mac, in addition to the existing
CPU/OpenGL/Metal regression validator. A native gate has no optional-skip mode.

The 0.51 input commit is `d6af412ba0fdf1b6ebbfb0bb5c9514cc4d6f5d5a`.
Its inspected run `36772282823` passed the completed project-test lanes,
including Direct3D interop, while the EGL pbuffer lane was still installing
system dependencies. This is a recorded evidence limitation, not a successful
pbuffer execution or a new skip rule. This delivery does not change that CI
lane or turn its aggregate green by removing a dependency.

0.52 is accepted only after its own source integration, Mac runtime tests and
required CI results have been reviewed. No assertion of hardware performance,
visible-screen certification, arbitrary external format support or universal
zero-copy behavior follows from accepting this stage.

## Revised implementation roadmap

| Stage | Goal | Key boundary |
|---|---|---|
| 0.53 | `skia-dc%` foundation | Direct public `dc<%>` implementation over a persistent CPU Skia surface; state, transforms, clipping and ordinary primitives |
| 0.54 | Text, bitmap and region compatibility | Match Racket-facing semantics; isolate any necessary private region adapter and test supported Racket versions |
| 0.55 | Real-consumer compatibility | Differential recorded drawing plus `pict`, plotting and other DC clients; semantic correctness with justified pixel tolerances |
| 0.56 | Explicit `skia-canvas%` | Persistent raster GUI widget; exposure, resize, backing scale, invalidation and presentation |
| 0.57 | GPU-backed canvas/DC facade | Use the existing GPU presenters; frame-backed DCs expire with their frame and cannot masquerade as persistent raster DCs |

`skia-dc%` implements drawing behavior. `skia-canvas%` owns and presents a GUI
backbuffer. The existing lower-level `gpu-canvas%` remains the scoped GPU-frame
widget; it is not itself a compatibility replacement for Racket `canvas%`.
The initial DC should not inherit Cairo-specific drawing machinery or require
a GPU merely to support existing programs that consume a `dc<%>`.

Do not promise full drop-in replacement solely because a class implements the
interface. Persistent GUI expectations, fonts/metrics, pens/brushes, bitmap
masks, clipping, alignment, alpha layers and method-specific semantics must be
validated. In particular, raster DC persistence and GPU-frame expiration are
different construction modes with different lifetime contracts.

The supported Ganesh architecture supplies the execution machinery for the
later GPU facade. That future work should adapt the interface, not weaken
resource ownership or add silent readbacks to make arbitrary persistent use
of a borrowed frame appear valid.
