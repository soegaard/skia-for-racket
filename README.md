# Racket Skia — 0.75

## Source directory guide

The root Racket modules are public entry points and detached value types.
[main.rkt](main.rkt) assembles the default `skia` import; GUI, GPU, and
interoperability entry points are selected explicitly. Implementations and native
ownership machinery live in [private/](private/README.md). Source comments follow
[house-style.md](house-style.md).

| Directory | Contents |
| --- | --- |
| [private/](private/README.md) | Core implementation, validation, native bindings, resource lifetimes, and backend adapters. |
| [unsafe/](unsafe/README.md) | Explicit native-pointer ingress for Metal and Direct3D interoperability. |
| [examples/](examples/README.md) | Runnable demonstrations and public API usage examples. |
| [scribblings/](scribblings/README.md) | Reference/tutorial sources, example modules, supporting code, and checked visual assets. |
| [tests/](tests/README.md) | Pure regressions, native rendering checks, and opt-in GPU/GUI tests. |
| [tools/](tools/README.md) | Installers, validators, ABI probes, evidence collectors, and documentation tooling. |
| [docs/](docs/README.md) | Maintainer-facing design, contracts, compatibility notes, and validation instructions. |
| [api/](api/README.md) | Reviewed capability, public-signature, Reference-coverage, and release-policy inventories. |
| [native/](native/README.md) | Installation destination for separately obtained native libraries. |
| [plans/](plans/README.md) | Implementation/editorial plans and progress records. |
| [.github/](.github/README.md) | CI, opt-in acceptance, documentation publication, and dependency-update configuration. |

### Root module map

The modules below are grouped by responsibility, not by dependency order.
Re-export facades may delegate their implementation to private modules; a public
filename does not imply that it is included in the default import.

<details>
<summary>Entry points and package support</summary>

| Module | Responsibility |
| --- | --- |
| [main.rkt](main.rkt) | Collects the default drawing, image, geometry, text, document, and stream interfaces. |
| [info.rkt](info.rkt) | Declares package dependencies, registered manuals, test exclusions, and command-line tools. |
| [run-tests.rkt](run-tests.rkt) | Runs the package's selected Racket test modules. |
| [native-capabilities.rkt](native-capabilities.rkt) | Exposes the package's native capability declarations. |

</details>

<details>
<summary>Drawing, geometry, and effects</summary>

| Module | Responsibility |
| --- | --- |
| [canvas-primitives.rkt](canvas-primitives.rkt) | Draws points, arcs, rounded rectangles, and colors and manages canvas clips and layers. |
| [advanced-layers.rkt](advanced-layers.rkt) | Applies checked layer options to native canvas save/restore scopes. |
| [layer-options.rkt](layer-options.rkt) | Defines immutable layer bounds and compositing-flag requests. |
| [specialized-canvases.rkt](specialized-canvases.rkt) | Supplies no-draw, multi-target, and overdraw canvases to bounded callbacks. |
| [matrix.rkt](matrix.rkt) | Constructs and combines detached affine transformations and maps points, vectors, and rectangles. |
| [projective-matrix.rkt](projective-matrix.rkt) | Constructs, combines, inverts, and applies detached 3-by-3 and 4-by-4 matrices. |
| [canvas-matrix.rkt](canvas-matrix.rkt) | Reads and applies 3-by-3 and 4-by-4 canvas transformation matrices. |
| [geometry.rkt](geometry.rkt) | Extends path construction, geometric inspection, paint queries, and region and rounded-rectangle operations. |
| [geometry-primitives.rkt](geometry-primitives.rkt) | Constructs integer regions, vertex meshes, image lattices, atlas transforms, and cubic patches. |
| [portable-drawing.rkt](portable-drawing.rkt) | Draws markers, sliced images, lattices, and atlases through explicit portable paths. |
| [effects.rkt](effects.rkt) | Constructs additional path effects, masks, procedural shaders, and compositing effects. |
| [runtime-effects.rkt](runtime-effects.rkt) | Compiles SkSL effects, reflects uniforms and children, and constructs shader, filter, or blender instances. |
| [pictures.rkt](pictures.rkt) | Queries, serializes, loads, and samples recorded native pictures. |
| [drawables.rkt](drawables.rkt) | Wraps recorded pictures as drawables and exposes drawing, bounds, and change queries. |

</details>

<details>
<summary>Images, color, pixels, and codecs</summary>

| Module | Responsibility |
| --- | --- |
| [color.rkt](color.rkt) | Normalizes named and packed colors into RGBA byte values. |
| [color4f.rkt](color4f.rkt) | Defines detached extended-range float colors with explicit alpha semantics. |
| [color-space.rkt](color-space.rkt) | Constructs transfer functions, RGB spaces, and XYZ-D50 conversion matrices. |
| [color-filters.rkt](color-filters.rkt) | Constructs channel-table, gamma, lighting, luma, and contrast filters. |
| [float-colors.rkt](float-colors.rkt) | Uses extended-range color values in paints, canvas fills, and gradient shaders. |
| [image-info.rkt](image-info.rkt) | Describes image dimensions, pixel formats, alpha interpretation, and color-space metadata. |
| [image-operations.rkt](image-operations.rkt) | Queries image properties and performs materialization, pixel transfers, scaling, and filtering. |
| [raster-buffers.rkt](raster-buffers.rkt) | Owns formatted pixel storage and lends checked pixmap or canvas access to callbacks. |
| [surface-properties.rkt](surface-properties.rkt) | Describes native pixel geometry and supported surface-rendering flags. |
| [codec-queries.rkt](codec-queries.rkt) | Queries decoder-supported scaled dimensions and subset rectangles. |
| [codec-scanlines.rkt](codec-scanlines.rkt) | Creates sequential decoder sessions and reads or skips output rows. |
| [codec-incremental.rkt](codec-incremental.rkt) | Feeds encoded input to a stateful decoder and exposes progress and copied pixel snapshots. |
| [graphics.rkt](graphics.rkt) | Queries and configures native font and resource caches and requests explicit cache purges. |

</details>

<details>
<summary>Text, output, and streams</summary>

| Module | Responsibility |
| --- | --- |
| [fonts.rkt](fonts.rkt) | Configures native font behavior and queries glyph metrics, positions, and outlines. |
| [typefaces.rkt](typefaces.rkt) | Loads typefaces, queries font styles and tables, and copies native font data. |
| [text-blobs.rkt](text-blobs.rkt) | Builds text blobs from ordered glyph runs and places shaped glyphs along paths. |
| [output.rkt](output.rkt) | Describes physical output pages and renders them to images, PDF, or SVG. |
| [output-policy.rkt](output-policy.rkt) | Describes backend capabilities and classifies output-audit events and reports. |
| [output-audit.rkt](output-audit.rkt) | Analyzes output pages and returns reports alongside encoded or saved document output. |
| [output-groups.rkt](output-groups.rkt) | Records a drawing group and chooses its permitted native or raster output representation. |
| [annotations.rkt](annotations.rkt) | Adds PDF/SVG links and named destinations through validated canvas operations. |
| [streams.rkt](streams.rkt) | Wraps native memory and file streams with checked seeking, copying, and byte transfer operations. |
| [stream-inputs.rkt](stream-inputs.rkt) | Constructs codecs, typefaces, pictures, and images from native streams or buffered ports. |
| [file-streams.rkt](file-streams.rkt) | Opens native output streams for files and exposes explicit flushing. |
| [live-streams.rkt](live-streams.rkt) | Reads and writes encoded images, pictures, and documents through Racket ports. |

</details>

<details>
<summary>Racket drawing and GUI bridges</summary>

| Module | Responsibility |
| --- | --- |
| [bitmap.rkt](bitmap.rkt) | Copies Skia surfaces and images into Racket bitmap objects. |
| [racket-draw.rkt](racket-draw.rkt) | Copies bitmaps, colors, and paths between Racket draw values and Skia values. |
| [pict.rkt](pict.rkt) | Converts Skia images, surfaces, and recorded pictures into Racket pict values. |
| [dc.rkt](dc.rkt) | Provides persistent and callback-scoped Skia raster drawing contexts and capability queries. |
| [dc-output.rkt](dc-output.rkt) | Supplies Skia drawing contexts to document callbacks and supports explicit raster groups and annotations. |
| [canvas.rkt](canvas.rkt) | Presents a persistent Skia drawing context through Racket GUI canvas and window behavior. |
| [render-canvas.rkt](render-canvas.rkt) | Selects a raster or GPU canvas implementation behind a common callback-oriented interface. |

</details>

<details>
<summary>Opt-in GPU interfaces</summary>

| Module | Responsibility |
| --- | --- |
| [gpu.rkt](gpu.rkt) | Creates and scopes GPU contexts and exposes rendering, state, and shutdown operations. |
| [gpu-context-options.rkt](gpu-context-options.rkt) | Validates detached options used to construct native GPU contexts. |
| [gpu-diagnostics.rkt](gpu-diagnostics.rkt) | Queries native memory statistics and OpenGL interface capabilities. |
| [gpu-egl.rkt](gpu-egl.rkt) | Creates headless EGL contexts or providers for an already-current EGL context. |
| [gpu-racket-gl.rkt](gpu-racket-gl.rkt) | Adapts a Racket GUI OpenGL context to a GPU provider. |
| [gpu-interop.rkt](gpu-interop.rkt) | Re-exports common GPU interoperability operations and guarded transfer support. |
| [gpu-gl-interop.rkt](gpu-gl-interop.rkt) | Exposes the supported OpenGL resource-sharing operations. |
| [gpu-gui.rkt](gpu-gui.rkt) | Hosts GPU presenters in Racket GUI canvases and windows. |
| [gpu-dc.rkt](gpu-dc.rkt) | Supplies drawing-context adapters during a GPU frame or surface callback. |
| [gpu-canvas.rkt](gpu-canvas.rkt) | Presents frame-scoped Skia drawing contexts in Racket GUI canvases and windows. |
| [gpu-output.rkt](gpu-output.rkt) | Runs explicit document raster-fallback work using a live GPU context. |

</details>


## Integer pixel storage and image information

[0.70 integer pixels](docs/INTEGER-PIXELS.md) adds detached image metadata,
seven integer formats, raw samples, explicit conversions and scoped raster targets.
The existing RGBA APIs retain their original meaning. Native/GPU/document acceptance
is selected explicitly; generalized GPU targets remain a later stage; floating formats are added below.

## Multi-run text and shaped text-on-path

[0.69 text blobs](docs/TEXT-BLOBS.md) adds retained multi-font and transformed runs,
UTF-8 cluster data, geometric intercepts and path placement. Font snapshots remain
independent of source mutation/closure. Run the selected native/GPU/document gates.

## Font options and glyph queries

[0.68b font queries](docs/FONT-QUERIES.md) adds font controls, retained typeface replacement,
immutable measurements, owned batch outlines and simple prefix fitting. Snapshot
configuration is preserved. Native host/CI acceptance must be run separately.

## Typeface resources and metadata

[0.68a typefaces](docs/TYPEFACES.md) adds copied-byte/TTC loading, owned style sets,
detached metadata and font tables, design-unit pair kerning, and copied raw-font
export. The 0.68a resource APIs remain available; 0.68b adds SkFont controls and glyph queries. The new acceptance gate uses procedural fixtures and native PDF /
outlined SVG output. Native host/CI acceptance is required.

## Geometry completion

[0.67 geometry](docs/GEOMETRY-COMPLETION.md) adds arc authoring, shape recognition,
ordered path-operation batches, conic conversion, paint inspection/reset and
geometric stroke expansion, region spans/clipping, and normalized rounded-rectangle
operations. Existing path snapshots and ownership rules are preserved. New
PDF/SVG fixtures require actual vector geometry; the GPU gate verifies reset
clears stale context dependencies. Native host/CI acceptance remains required.

## Additional effects and shader composition

[0.66 effects](docs/EFFECTS.md) adds path stamping, coverage/shader masks,
Perlin shaders, arithmetic/custom-blender composition and explicit picture-filter
target bounds. GPU-dependent masks retain context affinity; document fallback
remains explicit and bounded. The capability inventory is reconciled with the
new factories. Native acceptance is required before adopting this candidate.

## Pinned capability inventory and additive API decisions

0.65 adds a checked [SkiaSharp gap inventory](docs/SKIASHARP-GAPS.md), covering
all nine native binding registries and a finite m119 C/managed-source scope.
Source declarations, native symbol resolution and executed rendering are
separate evidence. [API decisions](docs/API-DESIGN-DECISIONS.md) define the
additive pixel/color/ownership direction; no new rendering APIs are exported.

```bash
python3 tools/test-api-inventory.py
python3 tools/api-inventory.py --check
python3 tools/validate-api-inventory.py
```

See [inventory maintenance and optional upstream/native gates](api/README.md).
Existing rendering and package validators remain mandatory. Missing effects
and shader composition are the next implementation stage, 0.66.

## Checked DC compatibility boundary

Single-family comma/Pango font descriptions now preserve weight, slant and
stretch while keeping the public font% size/override rules. Explicit font faces
honour font-name-directory mappings. Pango parses descriptions only; Skia and
HarfBuzz still draw and shape all text. Richer description fields are rejected.

`(skia-dc-compatibility 'raster)` (also `gpu`, `pdf`, `svg`) declares every
`dc<%>` method/arity, lifetime and remaining exclusion without probing a backend.
See [the compatibility contract](docs/DC-COMPATIBILITY.md). The new native/pure
cases and described-font consumer fixtures run through the existing CI gates.

```bash
python3 tools/validate-dc-closure.py --racket "$RACKET" --require-renderers
"$RACKET" examples/dc-closure.rkt
```


## Shared DC authoring for PDF and SVG

`skia/dc-output` connects the tested `dc<%>` authoring subset to the existing
output-page, PDF/SVG, text-mode and audit facilities. Geometry and ordinary
text remain native where supported; isolated alpha/pattern fallbacks are
reported. `draw-dc-raster-group` is the explicit bounded boundary for pixel
operations such as `copy`. No automatic whole-page screenshot is taken.

See [API, limitations and acceptance](docs/DC-OUTPUT.md). The document gate
checks actual PDF content streams, SVG elements, text and annotations; its
full mode also renders the files independently with Poppler and librsvg.

```bash
python3 -m pip install -r tools/dc-output-requirements.txt
python3 tools/validate-dc-output.py --racket "$RACKET" --require-renderers
"$RACKET" examples/dc-output.rkt
```

## GPU staging reuse

A GPU presenter retains one compatible offscreen staging surface across frames.
Every paint callback still receives a fresh, expiring DC; the existing snapshot
and GPU-to-GPU commit remain. Resize replaces the staging wrapper, failed DC
scopes discard it, and presenter shutdown retires it before context closure.
This reduces wrapper-level surface construction, not a promise of zero driver
allocations, zero-copy presentation or a measured speedup.

See [ownership, diagnostics and acceptance](docs/GPU-FRAME-REUSE.md). Run the
expanded gate, which also requires the prior common-canvas and consumer gates:

```bash
python3 tools/validate-gpu-frame-reuse.py --racket "$RACKET" --require-gui
```

## Unified callback-oriented canvases

`skia/render-canvas` provides `make-skia-render-canvas`: the same paint callback
can use an explicit raster renderer or a platform GPU, without replacing either
existing concrete canvas class. The factory returns an actual `canvas%` object.
`get-dc` is callback-only; `get-raster-dc` is explicit persistent raster access.
Actual raster and GPU DC lifetimes remain distinct and are reported by the API.

```racket
(require racket/gui/base skia/render-canvas)
(queue-callback
 (lambda ()
   (define frame (new skia-render-window%
                      [label "Unified Skia canvas"] [renderer 'auto]
                      [paint-callback
                       (lambda (_canvas dc)
                         (send dc set-pen "navy" 2 'solid)
                         (send dc set-brush "lightblue" 'solid)
                         (send dc draw-ellipse 20 20 160 100))]))
   (send frame show #t)))
```

`auto` selects Metal on macOS, Direct3D on Windows x64 and OpenGL on Unix.
Selection is not a driver probe: GPU initialization failures are reported, not
silently replaced by raster rendering. See the [API contract, renderer choices,
examples and acceptance limits](docs/RENDER-CANVAS.md).

```bash
python3 tools/validate-render-canvas.py --racket "$RACKET" --require-gpu
"$RACKET" examples/render-canvas.rkt --renderer raster
"$RACKET" examples/render-canvas.rkt --renderer gpu
```

## 0.59: GPU drawing contexts

[`skia/gpu-dc` and `skia/gpu-canvas`](docs/GPU-DC.md) add the existing `dc<%>`
drawing subset to the OpenGL, Metal and Direct3D paths. Unlike the persistent
raster DC, a GPU DC is valid only during its callback and is never reactivated.
Rendering, alpha composition, overlap copy and ordinary presentation use GPU
surfaces; CPU snapshots/readback are explicit operations. Device scales come
from the actual X/Y target extents, including HiDPI rounding.

```bash
python3 tools/validate-gpu-dc.py --racket "$RACKET" --require-gui
"$RACKET" examples/skia-canvas-on-gpu.rkt
```

## Persistent raster GUI canvas

Import `skia/canvas` explicitly to create `skia-canvas%`, a Racket `canvas%`
whose persistent `get-dc` result is a CPU Skia `skia-dc%`. Ordinary
`[paint-callback (lambda (canvas dc) ...)]` drawing, exposure repainting,
coalesced `refresh`, synchronous `refresh-now`, and explicit `present` all
use the same drawing context. Existing text, styles, recording replay and
alpha groups remain available through that DC.

Resizing replaces the transparent backing while preserving the DC's identity,
selected objects, transforms and other drawing state. Repaint callbacks redraw
the new extent. Actual GUI bitmap backing scale controls physical dimensions;
zero-sized clients defer work. Presentation transfers premultiplied pixels
straight into a reusable toolkit bitmap and blits it, without PNG encoding.
Skia renders the scene; the GUI toolkit displays the completed bitmap.

Call `close` (or `close`) explicitly on the owning eventspace handler
thread when the canvas is no longer needed. Hiding a frame does not close its
canvas. The raster canvas has no GPU selection or silent rendering fallback.
The next stage is **0.59: a GPU-backed canvas/DC facade with explicit frame
lifetime**. The existing `gpu-canvas%` API and native pins are unchanged.

Run the [GUI example](examples/skia-canvas.rkt) and see
[the canvas contract and validation](docs/SKIA-CANVAS.md). The new required
Linux GUI CI job uses an isolated installed package under Xvfb; existing CPU
and EGL jobs retain their headless contracts. GUI CI establishes tested widget
behavior and pixel transfer, while physical display/Retina review remains a
host check. This implementation starts from
`6c7ad1ff8c6b108abce4fd6e35cc1152ff726bd6`. Its 0.57 baseline
[CI run 37146060599](https://github.com/soegaard/skia-for-racket/actions/runs/37146060599)
completed successfully. The new 0.58 GitHub Actions run and physical-display
review remain acceptance gates.

## Retained 0.57 drawing styles and DC compatibility

`skia/dc` now supports public linear/radial gradients, repeating bitmap stipples,
six hatch brushes, legacy style aliases, finite affine alignment and geometric
path bounds. Existing alpha/replay and pict/plot validation remain required.
Associated-region utilities have an isolated query-only Cairo recording context;
Skia pixels are never given to that context and no Cairo drawing fallback is used.
Native Cairo-handle brushes and arbitrary combined-text breaks remain deferred.

The expanded installed-package DC gate requires 148 pure and 149 native cases,
with 24 alpha-controller and 45 style-math subchecks, and retains 20 PNGs. Older
exact oracles stay exact; new style captures have fixed semantic/replay bounds.
See [styles and limitations](docs/DC-STYLES.md). Racket 8.18 / draw-lib 1.22 and
all GPU pins/jobs/workloads remain unchanged.
The 0.58 canvas uses this drawing subset; 0.59 is the remaining GPU-facade stage.

## Retained 0.56 consumer coverage

This narrowed stage adds actual `pict` and `plot/no-gui` consumers to the
required installed-package DC gate. It tests direct drawing, both upstream
replay forms, state/clip preservation, 2x backing and post-close snapshots.
No new gradient, stipple, hatch, alignment or GUI implementation is added.

The minimum remains **Racket 8.18 / draw-lib 1.22**; `pict-lib` and `plot-lib`
are declared dependencies for the installed validation and examples. The DC
renderer, native pins, GPU demos and all GPU workloads are unchanged.

The gate runs 124 pure + 109 native DC cases and retains sixteen PNGs. The
new consumer images have independent semantic probes; procedure/datum forms
of the same recording agree within two channel units. Direct/reference text
and antialiasing are reviewed, not required to be pixel-identical.

See [consumer scope, examples and evidence](docs/DC-CONSUMERS.md). This is a
host/CI validation candidate based on `f1568cf68e57b0358ac27e4c5eeb1e0e33e6de8a`.
The subsequent stages are recorded in the current
[compatibility roadmap](docs/GANESH-CLOSEOUT.md#revised-implementation-roadmap).

## Recorded drawing and nested raster alpha groups (0.55 history)

`skia/dc` supports direct upstream `record-dc%` procedure replay and
`recorded-datum->procedure`, with the private replay identities isolated in a
small adapter. Selected pen and brush objects now keep their identity and are
locked until replacement/close instead of being silently copied.

Nested `start-alpha` / `end-alpha` groups draw into independent CPU Skia
surfaces and composite once, preserving overlap semantics and saved opacity.
Allocation is bounded, close discards unfinished groups, and explicit snapshots
inspect only the root backing. Successful upstream replay restores destination
state; exceptions are propagated without claiming transactional pixel rollback.
The established geometry, Skia/HarfBuzz text, bitmap/mask/copy and region APIs
remain. No Cairo rendering fallback, GUI initialization or GPU expansion occurs.

The minimum remains **Racket 8.18 and draw-lib 1.22**. The installed-package DC
gate now requires 124 pure and 93 native RackUnit cases. It preserves the two
existing exact oracles and independently checks direct/procedure/datum alpha
captures with a two-channel-unit quantization tolerance. All GPU gates and
native pins remain unchanged. See [the DC contract and limits](docs/SKIA-DC.md).

This is a validation candidate from `f4dedd03d0f8d0fdb79fcb9f5706b218a78183c5`;
it preserves both GPU game demos. Acceptance requires host and CI evidence.
The roadmap was subsequently refined into 0.56 consumers, 0.57 styles,
0.58 raster canvas and 0.59 GPU facade. No `pict`/plot/style claims were added in 0.55.

## Metal interop and Ganesh closeout

`skia/gpu-interop` now accepts Metal tokens created by the explicitly unsafe
`skia/unsafe/gpu-metal` bridge. Same-device RGBA8 textures support independent
Skia-owned GPU copies and scoped external-target drawing. Producer command
buffers and exact-Ganesh-queue completion buffers are retained and polled with
bounded waits; unknown completion quarantines storage instead of freeing it.
There is no CPU pixel staging or new runtime helper library.

The new local Metal gate compiles an independent Apple SDK producer/consumer,
runs 33 native cases, 144 handoffs and 12 post-teardown PNG comparisons, and
checks a separate expected-timeout process. Both existing macOS CI lanes compile
the Apple SDK fixture and check ABI declarations without claiming GPU execution.
All required D3D12, DXGI, CPU, EGL and native-ABI gates remain in place.

This closes the planned Ganesh feature work after validation, not every possible
GPU API extension. The next direction is `skia-dc%`, followed by `skia-canvas%`.
Vulkan, Graphite and a native 4.x migration are deferred. The production native
pin is unchanged. See [Metal interop](docs/GPU-METAL-INTEROP.md)
and [Ganesh closeout / compatibility roadmap](docs/GANESH-CLOSEOUT.md).

## Direct3D external textures

`skia/gpu-interop` adds opaque, single-use external texture handoffs:
`gpu-import-image` returns an independent Skia-owned GPU image, while
`call-with-gpu-external-surface` lends only a scoped drawing canvas.
The Windows x64 factory is explicitly unsafe, in `skia/unsafe/gpu-d3d12`.
It validates the native resource descriptor and canonical COM device identity,
retains resource/fence references, requires a producer fence and declared
incoming/outgoing resource states, and completes each handoff synchronously
with bounded fence waits. State declarations are caller obligations, not queries.

The initial subset is same-device, unshared DEFAULT-heap RGBA8 2D textures,
one mip, one array element and one sample. Copies use a private GPU bridge;
borrowed targets use a GPU snapshot plus shader-filled normalization pass.
There is no CPU pixel staging, but these paths are not advertised as zero-copy.
Indeterminate completion quarantines native references instead of freeing them.

The required D3D12 job keeps its offscreen/parity checks and then runs a separate
isolated installed-package interop gate, using an independent Windows SDK
producer/consumer, 29 native cases, 144 handoffs and 12 retained pixel captures.
A disposable process tests expected timeout quarantine without crashing.
Configuration is not acceptance: the new Windows gate must actually pass.
See [API, ownership and validation](docs/GPU-D3D12-INTEROP.md).

The native pin remains SkiaSharp 3.119.1. Metal interop is the next stage;
Vulkan, Graphite and native migration remain deferred in favor of the planned
`skia-dc%` and `skia-canvas%` compatibility work.

## 0.50: shared GPU backend policy and validation

`skia/gpu` now provides `gpu-backends`, `gpu-backend?`, and
`gpu-backend-capabilities`. These report immutable wrapper declarations, not
runtime availability: no native library, context, or GUI is initialized.
OpenGL, Metal, and Direct3D use one source-only backend/native-ID registry.

Direct3D now participates in the existing bounded PDF/SVG raster executor,
including its explicit readback, capture-once authoring, retained CPU images,
and unchanged vector/text/link policies. Surface identity is derived from
the validated live context, not a specialized constructor's descriptive hash.

`tools/validate-gpu-parity.py` runs the same rich scene, retained-image,
document, cache/stress and redraw implementations on an explicitly selected
backend. Required Windows WARP jobs retain their original 0.48/0.49 gates and
add this common validation, including all 137 offscreen native cases and the
full 540 offscreen / 1,080 presentation stress frames. The presentation timing
report accounts for real DXGI fence waits instead of applying GL's no-wait
assumption. No pixel tolerance, workload, or existing required lane is relaxed.

The native pin is unchanged. External Direct3D/Metal
resource import, Vulkan, Graphite, hardware certification and automatic native
migration are not added. See [backend API and parity validation](docs/GPU-BACKENDS.md).
Configuration is not acceptance: a new 0.50 host/CI run is still required.

## DXGI / Direct3D 12 window presentation

On Windows x64, `skia/gpu-gui` now accepts `[backend 'direct3d]` with
`[adapter 'hardware]` (default) or explicit `[adapter 'warp]`, an optional
hardware `[adapter-index 0]`, and `[sync-interval 1]` (0 or 1). The same
`gpu-window%`, `gpu-canvas%`, presenter and scoped-frame API is used. `auto`
selects Metal on macOS, Direct3D on Windows x64, and OpenGL on Unix, as in the
other GUI constructors. No fallback occurs.

The presenter owns a two-buffer flip-discard swap chain on Ganesh's exact
command queue. Per-buffer fences protect reuse; resize/close retire queued
work and every direct/indirect back-buffer reference. Normal frames do not
read back pixels, but buffer-reuse fence waits can block when work is pending.
Occlusion is a skip, not a successfully presented frame.

A separate required Windows WARP/DXGI lane runs the 28 shared presenter tests,
then six coexisting-pair contexts, 1,080 stress frames, two resizes per window,
and 18 independently checked swap-chain captures encoded after teardown.
This validates buffer contents and presentation submission, not physical
screen pixels or hardware performance. The 0.48 offscreen WARP gate remains.

See [DXGI API, state protocol and validation](docs/GPU-DXGI.md).

## Direct3D 12 offscreen rendering and required WARP validation

`skia/gpu` accepts `#:backend 'direct3d` on Windows x64, with an owned
DXGI adapter, D3D12 device and direct command queue. Explicit `#:adapter 'warp`
selects software rendering; the default `#:adapter 'hardware` never falls back
to WARP. Ordinary surfaces, images, transfers, retained context affinity and
cache controls use the same GPU API as OpenGL and Metal.

The required Windows WARP CI lane installs an isolated source package, runs
CPU checks, verifies actual Windows SDK layouts/GUIDs/vtables and the by-value
Racket call ABI, then runs all 33 surface, 42 image and 20 cache source cases.
Three recreate cycles exercise 540 retained-image frames and verify nine PNGs
against an independent asymmetric pixel reference. Failure is never a skip.

The offscreen lane supplies software D3D12/Ganesh correctness coverage, not hardware acceleration,
physical display pixels, a benchmark, or DXGI swap-chain presentation. The
native pin remains SkiaSharp 3.119.1. The existing CI matrix and desktop GPU
validators remain required and unchanged in scope. Configuration is not a
passing Windows run: consult the latest required CI result and artifacts.

See [D3D12 API, ownership and validation](docs/GPU-D3D12.md).

## Native ABI policy and isolated 4.x investigation

The supported default remains **SkiaSharp 3.119.1**, native ABI **119.0**.
A single lazy loader and explicit ABI profile now serve the CPU and optional
Ganesh registries. The profile checks 64-bit Racket layout sizes before CPU
preflight completes; every required CPU symbol is still resolved before object
allocation. Optional GPU groups remain optional and share the same checked
library handle. No version-check bypass or implicit backend fallback is added.

`skia/native-capabilities` exposes explicit diagnostics without importing a GUI.
The candidate tool investigates pinned **SkiaSharp 4.153.1** in a disposable
process, inventories actual exports and requires the real Racket loader to reject
the unsupported milestone. Same-name pointer signatures can still be incompatible:
`sk_pathmeasure_get_segment` now requires a path builder, not a path.
A successful investigation is not a candidate rendering or migration pass.

See [native ABI API and validation](docs/NATIVE-ABI.md),
[4.x compatibility and migration report](docs/NATIVE-MIGRATION-0.47.md), and
[Graphite feasibility](docs/GRAPHITE-FEASIBILITY.md).
The required Linux CPU lane adds the candidate rejection gate; all existing
CPU, EGL, document, cache and stress gates remain. New 0.47 native results
must be established by host/CI execution. The accepted baseline is
`1cd0599a463c00aa50dcdef1a3f1114ca12cdf10`; earlier sections below are historical.

## CI and portability

[GitHub Actions CI](docs/CI.md) checks an independently installed source package,
not only a development checkout. The required matrix covers Linux x64, Windows
x64, macOS ARM64 and macOS Intel with Racket CS 9.3, plus Linux CS 8.18 (the
currently declared minimum). Two required Linux Mesa/llvmpipe lanes run the
complete EGL headless sequence with surfaceless and pbuffer bindings and no
display server. Software rendering establishes functionality, not acceleration.

Native assets are installed afresh inside each isolated package copy. Source
manifests are verified, never rewritten by CI. Logs, installation/native identity,
JSON/CSV and actual visual outputs are retained even when a later check fails.
The aggregate `CI required` check rejects failed, cancelled or skipped lanes.

Baseline: `92f6119af3846966075ced0034ceb740e916bdee` (0.45), with accepted
macOS OpenGL/Metal validation. The Linux headless gate deferred since 0.43
passed the required 0.46 workflow at commit
`808befa8768e672238e3fcdc5288e497a8b2705f` (Actions run `36620003104`) in both
surfaceless and pbuffer modes on Mesa llvmpipe with no display server. This is
software OpenGL/Ganesh functionality evidence, not hardware-acceleration or
hardware-performance evidence.
Hosted macOS/Windows lanes make no GPU claim. See the explicit
[coverage and evidence matrix](docs/PORTABILITY.md). Earlier release sections
below are historical notes, not the current support matrix.

## Cache control, completion-aware measurements and release stress

`skia/gpu` now exposes explicit per-context budget, purge, age-cleanup and
resource-release controls. The live cache query reports budgeted usage, not
total VRAM. The cache budget is not a hard allocation limit.

New diagnostics distinguish authoring, host SkSL construction, first replay,
warm draw/flush/submit/completion, uploads, readback and window presentation.
They preserve raw samples and driver/target identity, and exercise sustained
retained graphs, GC, cache pressure, resize, queued redraw and context recreation.
They measure host latency, not isolated GPU timestamps or physical display latency;
no speedup is claimed before an actual hardware run.

See [cache API](docs/GPU-CACHE.md), [measurement boundaries](docs/GPU-PERFORMANCE.md)
and [validation and longer runs](docs/GPU-PERFORMANCE-TESTING.md).
The accepted baseline is 0.44 commit `4304856a73dc8087d5962963428f37a84cbc8a21`.
Linux headless validation remains deferred to future CI. Earlier sections below
are historical release notes.

## GPU-assisted bounded document fallbacks

`skia/gpu-output` provides borrowed or lazily owned raster executors for
`draw-output-group`. Select `#:raster-executor` explicitly; CPU execution remains
the default. The existing representation policy first chooses native replay,
bounded rasterization or rejection. A selected raster can then render on an
OpenGL/Metal context, read back explicitly, and embed a CPU-owned image.

GPU availability cannot override vector-only, annotation, native-text, unknown
provenance or device-clip restrictions. Nested groups inherit execution only
through their own enclosing capture. Reports separate representation, actual
execution, context generation and transfer. Only explicit factory-unavailability
policy permits a CPU fallback; authoring is never retried.

See [API and ownership](docs/GPU-OUTPUT.md) and
[document validation](docs/GPU-OUTPUT-TESTING.md). The runner checks actual
PDF/SVG resources and placement, retained vector paths/links and embedded SVG
PNG comparisons, including serialization after both GPU contexts close.

The accepted baseline is `f493314201d69973956c3e5485fda0b709dcad67` (0.43).
Its macOS checks passed; Linux EGL end-to-end acceptance is explicitly deferred
to future GitHub Actions CI, not a blocker for this baseline. New 0.44 native
results remain a separate host validation. No speedup is presumed.

## EGL headless contexts and external GL borrowing

`skia/gpu-egl` creates explicit Linux EGL contexts without a native window or
GLX, using the same OpenGL/Ganesh surface and image API. Surfaceless and device
platforms, with either no binding surface or an explicit pbuffer, have separate
selection and diagnostics. A borrowed-current EGL provider supports existing
host-managed contexts without taking over their EGL object lifetimes.

`skia/gpu-gl-interop` provides a scoped canvas over a restricted host-owned
RGBA8/stencil8 framebuffer and an explicit GPU-side copy of an external RGBA8
texture. It never adopts external names. The copy can safely enter retained
shader/picture graphs after the host source is reused or deleted. Synchronization
and the limited binding-restoration contract are explicit; this is not zero-copy
import or cross-context sharing.

See [EGL ownership](docs/GPU-EGL.md), [interop contracts](docs/GPU-INTEROP.md),
and [desktop/headless validation](docs/GPU-HEADLESS-TESTING.md).
`tools/validate-gpu.sh` retains presentation/parity tests and adds GL interop.
`tools/validate-gpu-headless.sh` runs the Linux EGL gate with display variables
removed and no GUI host. Both publish evidence only after selected success.

Baseline: `e5f93e529fd875661a0b0019d5b9d897ff8c9dc0` (0.42), whose macOS
automated and interactive checks passed. New Racket/native execution remains
a separate host gate. Earlier release-specific notes below are historical.

## Unified OpenGL and Metal windows

`skia/gpu-gui` provides `gpu-canvas%` and `gpu-window%`. Both use the same
`gpu-presenter?` / short-lived `gpu-frame?` API from `skia/gpu`, with ordinary
canvas drawing, actual pixel/logical geometry, target generations, queued
redraws and safe close/resize behavior. `auto` selects Metal on macOS,
Direct3D on Windows x64, and OpenGL on Unix; failures never silently fall back
to CPU rendering.

OpenGL wraps the real host framebuffer and swaps. Metal retains the current
CAMetalDrawable, wraps its BGRA texture, and requests presentation on the exact
same command queue as Ganesh after rendering submission. Successful normal
frames require no explicit CPU readback or completion wait. Cancelled Metal
frames may synchronize for safe drawable cleanup; acquisition can block.

See [presentation API and ownership](docs/GPU-PRESENTATION.md) and
[automated and manual validation](docs/GPU-PRESENTATION-TESTING.md).
Run `examples/gpu-presenters.rkt --backend both` on macOS to inspect the same
callback in both windows. Automated submission/teardown checks do not certify
physical display pixels; their review explicitly requires human inspection.

Baseline: `07db8f0356e2bb508e06a119adf7f19c9396f80e` (0.41). The maintainer's
OpenGL/Metal offscreen, image, lifecycle and parity checks passed on the Apple
M4 Pro. New 0.42 native and visible-window execution remains a host validation
gate. CPU imports, offscreen constructors, document policies, and explicit
cross-context transfers are preserved. Older sections below are historical.

## Offscreen Metal with the shared GPU API (0.41)

`(make-gpu-context #:backend 'metal)` creates an owned default-device/private-
queue Ganesh Metal context on 64-bit macOS, without a GUI or OpenGL host.
Existing GPU surfaces, images, drawing, transfers and retained graph ownership
work with the selected backend. Explicit OpenGL-provider construction remains
unchanged. No backend is silently replaced with CPU rendering.

Metal native calls and deferred owner-side destruction use short autorelease
scopes, never a pool left open across application drawing callbacks or yields.
The validation runner executes the same surface/image suites and ten visual
workflows on both backends, plus Metal lifecycle and cross-backend transfer
checks. Review the combined `parity.review.html` after a successful host run.

See [Metal API and lifetime](docs/GPU-METAL.md) and
[the complete validation sequence](docs/GPU-METAL-TESTING.md).
The implementation baseline is `dca0aa876b1b42f293db2fef235eecee0ed7cd5a` (0.40).
The maintainer's 0.40 macOS OpenGL checks passed; new 0.41 Metal rendering still
requires host validation. Metal window presentation, external interop and
performance claims are not part of this revision.

The older release-specific sections below are historical.

## GPU images and retained graph ownership

`skia/gpu` now provides explicit image uploads, immutable GPU surface snapshots,
GPU subsets, residency/context queries, and synchronous CPU detachment. GPU
images remain ordinary `image?` values. Context affinity follows native retained
shader, filter, paint, runtime-child and picture graphs after original wrappers
are closed. Mutable paint slots and retained getters preserve their own affinity.

CPU/PDF/SVG drawing, CPU encoding/subset helpers and SKP serialization reject
GPU-dependent input rather than hiding a download. Detach explicitly for those
uses. Image readback uses a same-context GPU staging surface because the pinned
C image-readback interface omits a context argument; it is not zero-copy.

See [GPU images](docs/GPU-IMAGES.md) and [validation](docs/GPU-IMAGE-TESTING.md).
The combined runner retains all prior GPU/CPU checks and adds 33 pure + 42 live
image cases, retained-graph visual workflows, and an independent PNG inspector.
The baseline is `0eea009d393500cda7dc4a6848579c09300f53db`; new native execution
still requires host validation. Earlier revision-specific acceptance notes below
are historical. Metal rendering and external texture interop are not added here.

## Offscreen OpenGL with the ordinary drawing API

`skia/gpu` adds `make-gpu-surface`, returning the existing `surface?` interface
with GPU backing. Its borrowed `canvas?` uses the same paths, paints, gradients,
images, filters, SkSL, text, meshes and matrix operations as CPU drawing.
GPU canvases require a live activation and expire when that activation ends;
the surface itself can be reused in a later activation.

Submission and CPU transfers are explicit: `gpu-flush!`, `gpu-submit!`,
`gpu-flush-and-submit!`, `gpu-wait!`, `gpu-surface->rgba-bytes`,
`gpu-surface->raster-image`, and `gpu-surface-read-raster-buffer!`.
The latter writes directly into the existing exclusive strided CPU buffer.
`make-surface` stays CPU-only, and ordinary snapshot/encoding entry points reject
GPU targets rather than creating an untracked GPU image or hidden readback.

See [the surface guide and reference](docs/GPU-OFFSCREEN.md),
[context ownership](docs/GPU-FOUNDATION.md), and
[the complete validation sequence](docs/GPU-OFFSCREEN-TESTING.md).
The diagnostic window wraps its actual host framebuffer, submits, and swaps
without explicit per-frame CPU waits or readbacks. It is not a finalized public
presenter API; visible pixels and resize/HiDPI behavior require manual review.
The offscreen runner compares eight directly rendered CPU/GPU scene pairs.

Baseline: `f2aa79db1a8c24045445623c42930ebc09cc0527` (0.38, including the GC-test
correction). The maintainer's 0.38 macOS/aarch64 run passed CPU tests, GL
render/readback, and Metal construction. This 0.39 authoring delivery has source,
context-patch, Python and host-C checks, **not Racket/native execution**.
Linux/Windows GL and all 0.39 host execution remain validation gates.
Metal still has a construction probe only. No GPU-image API, automatic CPU
fallback, document acceleration, universal pixel identity or performance claim
is introduced. Existing document-output policies remain unchanged.

Earlier feature sections below retain historical revision-specific notes.

## Persistent pictures and picture shaders

`picture->bytes`, `picture-from-bytes`, `picture-from-file`, and `save-picture`
add native SKP persistence to the existing owned `picture?` type. Loading is
explicitly trusted (`#:trusted? #t`): the pinned native decoder can compile
embedded SkSL. This is an application cache format, not a safe document format.
Picture metadata, optional R-tree-backed recording, and tiled picture shaders
are available from `skia/pictures` and `skia`.

Loaded pictures retain an `unknown` audit finding even inside raster groups;
there is no API to certify a stream by attaching an unverified JSON summary.
Live picture shaders use explicit PDF/SVG raster groups. Sampled annotations
are reported as discarded semantics.

See [the picture guide](docs/PERSISTENT-PICTURES.md) and
[the validation sequence](docs/PICTURE-TESTING.md).
Expected current suite: **1042 cases**, including **31 new pure + 40 new native**;
**377 Skia / 27 HarfBuzz** symbols; no new native layouts.
The validator also runs a separate selected-Racket process to decode a cache
and compares its RGBA pixels to the original recording.

## Perspective and general canvas matrices

Immutable row-major `matrix3?` and `matrix4?` values add homogeneous point
mapping, horizon-aware rectangle bounds, composition, inversion, and retained
Z coordinates. `canvas-matrix4` reads all sixteen coefficients;
`with-canvas-matrix` composes or replaces the matrix in a protected state scope.
The existing six-coefficient affine API is unchanged. Native packing converts
the public row-major representation to the pinned column-major SkM44 ABI.

General matrices are conservatively reported as `needs-raster` for both PDF
and SVG. Apply the matrix **inside** `draw-rasterized`; canonical affine matrices
still pass vector-only export. Recorded pictures retain matrix provenance.
There is no automatic fallback, depth buffer, or hidden-surface removal.

See [the matrix guide](docs/PROJECTIVE-MATRICES.md) and
[the validation sequence](docs/PROJECTIVE-TESTING.md).
Expected suite: **971 cases** (59 new pure + 36 new native);
**367 Skia / 27 HarfBuzz** symbols, unchanged. No new native layout or callout.
The baseline is `85f8292a5925cc14bad880675385e7d9c5a75067`, including the SVG
region-seam fix. The maintainer reports passing 0.31 tests. This authoring pass
has source/context-patch, host-C, and Python-inspector checks, **not Racket/native
execution**. Run the selected-interpreter validation before accepting 0.32.

## Previous revision: structured geometry (0.31)

Owned integer regions and copied triangle meshes, pure lattice/atlas/Coons-patch
specifications, and native nine-patch/lattice/atlas/patch drawing now use the
ordinary canvas and resource APIs. The 0.30 rounded-rectangle values are retained.
All new operations participate in output audits and picture provenance.

See [the guide](docs/GEOMETRY-PRIMITIVES.md) and
[the validation sequence](docs/GEOMETRY-TESTING.md).
Expected suite: **876 cases**; **367 Skia / 27 HarfBuzz** symbols. New 64-bit
layouts are 48-byte lattice / 16-byte RSXform; lattice cell kinds are uint8.
The maintainer reports passing 0.30 tests. This 0.31 authoring run has source,
patch, host-C, and synthetic-inspector checks, **not Racket/native execution**.
The GitHub connection still returned 0.29, so the patch targets that visible
source plus the exact tested 0.30 patch; no newer commit hash is claimed.

### Earlier implementation notes

An experimental standalone CPU drawing and PDF/SVG-output binding to Skia through
SkiaSharp's native C ABI. The Racket collection is named `skia`; the unsafe ABI
layer remains private.

**Verification status:** the maintainer reports passing 0.29 tests. This revision
starts from `aa94a31509635090fdd2677ab393e8e005927dbb` (output capability audit).
**0.30 has source/context-patch, host-C and synthetic-inspector checks only in
the authoring environment; Racket/native execution remains required.**
Expected suite: 796 cases (321 pure + 6 lifetime + 469 native); 336 Skia /
27 HarfBuzz symbols. No new native layouts. See [canvas validation](docs/CANVAS-TESTING.md).
Earlier full Unicode conformance results remain historical.

## Canvas primitives and compositing layers

`canvas-primitives.rkt`, also exported by `main.rkt`, adds points/point sets,
arcs, immutable four-corner rounded-rectangle specifications, clip queries,
color fills, and protected scoped layers. A layer paint applies opacity and
filters to the completed group at restore. Native layer bounds can restrict
content in m119; supply conservative bounds or omit them.

The output auditor reports native point sprites and layers as requiring SVG
fallback. The combined PDF/SVG/reference probe keeps the remaining geometry and
labels vector. See the [guide](docs/CANVAS-PRIMITIVES.md).

## Output capabilities and fallback auditing

```racket
(define report (analyze-output-page page 'svg))
(output-audit-report-blocking? report)
(save-output/audit page "diagram.svg" 'svg #:policy 'error #:exists 'replace)
```

Audits execute the drawing callback; they are not static analysis. Preflight
suppresses target drawing while collecting known risks. Audited exports draw
once, report observed features, and optionally reject unsupported/unknown uses
before publication. Explicit raster groups resolve representation risks but
cannot preserve links or capture an outer backdrop. Paint copies, child
resources, and previously recorded pictures retain compact provenance summaries.
See the [guide](docs/OUTPUT-AUDIT.md) for policies, labels, limits, and the
important distinction between no known policy gap and visual certification.

## Runtime effects / SkSL

Compile a program once, then bind checked uniform and child snapshots to create
ordinary shaders, color filters, or paint blenders. Effects and blenders use the
existing owned-resource lifetime rules; reflection is copied into immutable values.

```racket
(with-skia ([effect
             (make-runtime-effect
              "layout(color) uniform half4 color; half4 main(float2 p) { return half4(color.rgb*color.a,color.a); }")]
            [shader (runtime-effect->shader effect #:uniforms (hash 'color '(0.2 0.4 0.8 1)))]
            [paint (make-paint #:shader shader)])
  (draw-circle canvas 100 90 45 paint))
```

The [guide](docs/RUNTIME-EFFECTS.md) explains tight uniform packing, column-major
matrix uniforms, premultiplied output, typed child slots, and structured compiler
errors. Generic SkSL/custom blenders require explicit bounded raster groups in
PDF/SVG; surrounding labels and geometry remain vector. There is no GPU context
or universal automatic fallback in this revision.

## Links and named destinations

```racket
(canvas-annotate-url! canvas 10 20 180 25 "https://docs.racket-lang.org/")
(canvas-link-destination! canvas 10 60 180 25 "later")
;; This definition can be on a later PDF page.
(canvas-define-destination! canvas "later" 10 200)
```

The rectangles use current canvas coordinates, including shared-page units and
margins. They add no pixels. PDF supports forward references across pages;
SVG resolves same-document names to stable predefined views. Duplicate definitions
and unresolved names raise errors before publication. URL annotations can be
recorded in pictures; named annotations are added to live document canvases.
Raster output ignores annotation operations after argument validation.

See [the annotation guide](docs/ANNOTATIONS.md) for clipping/bounding-rectangle
semantics, URI restrictions, stable fragment IDs, and ownership. The single
`examples/document-links.rkt` runner exports PDF, SVGs, raster references and
an **interactive** HTML review page using `object` rather than `img` for SVGs.
The existing ICC sentinel workaround and color-output implementation are unchanged.

## Color-managed output

`make-rgb-color-space` combines an SDR transfer function with an XYZ-D50 gamut.
Named choices include sRGB, linear sRGB, Display P3, Adobe RGB and SDR Rec. 2020.
Detached transfer/matrix values support inspection, custom primaries, and native
transfer inversion.

`image-convert-color-space` changes samples. Encoder `#:color-space` converts
before encoding; `#:icc-profile` overrides metadata without changing samples.
These keywords reach PNG, JPEG and WebP byte/file output, and surface PNG output.
ICC overrides are restricted to RGB matrix/TRC profiles supported by the native
writer, which regenerates a semantically equivalent profile rather than copying
arbitrary ICC tags verbatim.

```racket
(with-skia ([linear (make-linear-srgb-color-space)]
            [srgb (make-srgb-color-space)]
            [im (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                  #:color-space linear)])
  (save-image im "converted.png" 'png #:color-space srgb
              #:icc-profile (color-space->icc-bytes srgb) #:exists 'replace))
```

PDF `#:pdfa? #t` exposes Skia's XMP/UUID/fixed-sRGB-output-intent mode, not a
PDF/A conformance guarantee. Normalize source-image samples to sRGB before
embedding in portable documents: the pinned PDF serializer does not reliably
preserve source-image ICC profiles. See [the guide](docs/COLOR-OUTPUT.md).
`examples/color-output.rkt` supplies one PDF/SVG/raster registry, six tagged
encoded images, source profiles, and a comparison HTML page.

## Advanced filter graphs

Merge, blend, arithmetic, morphology, displacement, convolution, image
transforms, tiling, magnification, explicit image/picture/shader sources, and
six alpha-lighting constructors use the existing image-filter paint API.
Crops are available on the existing filters and as explicit graph nodes.

```racket
(with-skia ([shadow (make-drop-shadow-only-image-filter 8 6 4 4 (rgba 0 0 0 120))]
            [graph (make-merge-image-filter (list shadow #f) #:crop '(0 0 300 160))]
            [paint (make-paint #:color 'blue #:image-filter graph)])
  (draw-rounded-rect canvas 40 35 190 85 14 14 paint))
```

An input `#f` denotes the dynamic source, not transparent pixels. Merge order is
back to front. The [guide](docs/FILTER-GRAPHS.md) explains output cropping versus
input cropping, convolution pixel units and tiling, and ownership. Native PDF
filters can rasterize. General filter graphs on SVG need explicit bounded
`draw-rasterized` groups; there is no blanket automatic fallback.

The validation script uses the same selected Racket for compiling all test
modules and running the complete suite. `examples/filter-graphs.rkt` is one
registry for the PDF, SVGs, independent references, and browser review page.

## Path inspection and affine matrices

```racket
(for ([segment (in-path-segments path #:mode 'raw)])
  (printf "~a ~s\n" (path-segment-verb segment) (path-segment-points segment)))

(with-canvas-state canvas
  (canvas-concat! canvas
    (matrix-compose (matrix-translate 100 60) (matrix-rotate-degrees 30)))
  (draw-path canvas path paint))
```

Path inspection returns immutable segment structures, with raw/normal closure
semantics, conic weights, contour grouping and reconstruction commands. Point
collections are immutable vectors of immutable `#(x y)` vectors. Point and bounds
queries return `#(x y)` and `#(x y width height)` vectors, as do affine and projective
matrix mappings.

Affine matrices support composition, inversion, canvas get/set/concat, transformed
paths, path-measure frames and shader-local transforms. Use `matrix-rotate-radians`
or `matrix-rotate-degrees` to make the angle unit explicit. Matrices are values,
not native resources. See [the guide](docs/PATH-MATRIX.md).

The validation script compiles **all** `tests/*.rkt` with the chosen Racket,
including dynamically loaded suites, before running the tests and probes.

## Shared PDF/SVG pages

```racket
(define page
  (make-output-page 210 148.5
    (lambda (c)
      (with-skia ([p (make-paint #:color 'blue)])
        (draw-circle c 30 30 15 p)))
    #:unit 'mm #:margins 10 #:background 'white))
(save-output page "drawing.pdf" 'pdf #:exists 'replace)
(save-output page "drawing.svg" 'svg #:exists 'replace)
```

A page has explicit units, margins, background, and clipping. The same callback
can target either format; PDF also accepts a list of differently sized pages.
SVG gets physical point-sized root dimensions that match the PDF media box.
Auto text policy retains native PDF text and outlines SVG text, including
paragraphs and prebuilt text blobs. Padded raster groups inherit export density
without shrinking their original content box. The low-level APIs retain their
native-text and SVG-user-unit defaults.

See the [shared-output guide](docs/OUTPUT-GUIDE.md), the [API reference](docs/API.md),
and `examples/vector-output.rkt` for the complete PDF/SVG/raster review registry.
Already-recorded pictures cannot have their text policy changed retroactively;
unsupported native SVG effects still need explicit rasterization.

## SVG documents

```racket
(call-with-svg-file
 "example.svg" 300 180
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (draw-circle canvas 100 90 45 paint)))
 #:title "Example SVG" #:exists 'replace)
```

SVG helpers receive a normal canvas directly. They produce complete UTF-8 SVG
bytes, strings, or safely published files with explicit dimensions/viewBox,
escaped title/description, and stable prefixed resource IDs. They are not PDF
page wrappers. Existing PDF output is unchanged.

The pinned native SVG serializer is not equivalent to every raster/PDF
operation. Native text relies on viewer fonts and glyph-to-Unicode conversion;
use `simple-text-path` or `shaped-run->path` for explicit outlines. Use
`draw-rasterized` for bounded effects/shaders that require pixels, while
surrounding content stays vector. There is no blanket automatic fallback.
See the [SVG guide and coverage table](docs/SVG-OUTPUT.md).

`examples/svg-documents.rkt` writes three SVGs, their separately drawn raster
references, and a browser review page. `tools/inspect-svg-output.py` checks the
actual SVG structure using Python's standard library; it does not render it.

## PDF documents

```racket
(call-with-pdf-file
 "example.pdf"
 (lambda (doc)
   (with-pdf-page (canvas doc 595.28 841.89)
     (with-skia ([paint (make-paint #:color 'blue)])
       (draw-circle canvas 100 120 40 paint))))
 #:title "Example PDF" #:exists 'replace)
```

The same canvas drawing operations now target multi-page PDFs. Output can be
copied to bytes or safely published to a file; metadata and fallback raster DPI
are configurable. PDF page dimensions are points, not pixels. See the
[PDF guide](docs/PDF-OUTPUT.md) and [API reference](docs/API.md#pdf-documents).
`examples/pdf-documents.rkt` writes a three-page PDF and separate raster reference
PNGs. Those PNGs are not PDF renderings; compare them with an actual PDF viewer.

## Animated frames and orientation

```racket
(with-skia ([codec (codec-from-file "animation.gif")])
  (printf "~a selectable frames\n" (codec-frame-count codec))
  (with-skia ([frame (codec->image codec #:frame-index 0)])
    ;; The frame is a detached full-canvas raster, normalized by default.
    (save-image frame "frame-0.png" 'png #:exists 'replace)))
```

`image-frame-from-bytes` and `image-frame-from-file` offer one-shot decoding.
Use `#:normalize-origin? #f` for encoded pixel coordinates. Existing image
constructors retain their previous behavior. Run `examples/advanced-codecs.rkt`
for the animation/orientation contact sheet. Detailed contracts are in
[the API reference](docs/API.md#animated-codecs-and-encoded-orientation).

## Implemented

CPU RGBA surfaces; canvas save/restore, translation, scaling, rotation, skew,
and clipping; fills, strokes, circles, ovals, rounded rectangles, polygons,
quadratic and cubic Bézier paths; paint settings and blend modes; path bounds
and containment; immutable image snapshots and copied RGBA input; image
placement/scaling; native PNG encoding; font-manager enumeration and fallback;
default/family/file-backed typefaces; configurable fonts and metrics; UTF-8
simple-text drawing/measurement; positioned text blobs; HarfBuzz-shaped glyph runs; mixed-script/bidi run layout and font fallback; Unicode 15.1 line breaking; paragraph wrapping/alignment/justification; glyph IDs and text/glyph
outline paths; owned shaders; color, linear, radial, sweep,
and conical gradients; image tiling; shader blending; PNG/JPEG/WebP encoded
image decode and encode; codec metadata probing; image subsets and source-rectangle
drawing; dash/corner/discrete/trim/composed path effects; path measurement,
segments and tangents; boolean path operations; color-matrix/blend/composed
color filters; blur mask filters; blur, drop-shadow, color, and composed image
filters; immutable pictures; picture recording/replay; picture rasterization; expanded path/SVG geometry; explicit/scoped resource cleanup and GC fallback. An optional module
copies pixels into a Racket `bitmap%`.

The unsafe ABI layer is private. Public resource wrappers do not expose raw
pointers. The source distribution contains no native binary or font files.

## Quick start on macOS

From the extracted directory:

```sh
cd racket-skia-0.19.0-20260925

RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
bash tools/install-harfbuzz.sh &&
bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&
mkdir -p output &&
"$RACKET" examples/circle.rkt output/circle.png &&
"$RACKET" examples/gallery.rkt output/gallery.png &&
"$RACKET" examples/text.rkt output/text.png &&
"$RACKET" examples/text-blobs.rkt output/text-blobs.png &&
"$RACKET" examples/shaping.rkt output/shaping.png &&
"$RACKET" examples/layout.rkt output/layout.png &&
"$RACKET" examples/mixed-text.rkt output/mixed-text.png &&
"$RACKET" examples/line-breaking.rkt output/line-breaking.png &&
"$RACKET" examples/justification.rkt output/justification.png &&
"$RACKET" examples/bidi-controls.rkt output/bidi-controls.png &&
"$RACKET" examples/break-providers.rkt output/break-providers.png &&
"$RACKET" examples/script-justification.rkt output/script-justification.png &&
"$RACKET" examples/color-spaces.rkt output/color-spaces.png &&
"$RACKET" examples/gradients.rkt output/gradients.png &&
"$RACKET" examples/codecs.rkt output/codecs.png &&
"$RACKET" examples/path-effects.rkt output/path-effects.png &&
"$RACKET" examples/filters.rkt output/filters.png &&
"$RACKET" examples/pictures.rkt output/pictures.png &&
"$RACKET" examples/svg-paths.rkt output/svg-paths.png &&
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Adjust the two executable paths for another Racket installation. The examples
refuse to overwrite existing output files; choose a new output name on reruns.
The public `save-png` function supports an explicit `#:exists 'replace` option.

The installer downloads **SkiaSharp.NativeAssets.macOS 3.119.1** and extracts
`runtimes/osx/native/libSkiaSharp.dylib`. It does not install .NET, compile Skia,
use `sudo`, or run the downloaded library. The doctor command is the first
actual native load and rendering smoke test.

Racket 8.18+ and draw-lib 1.22+ are required. This version of `dc<%>`
supplies the alpha-method default implementations overridden by `skia-dc%`;
8.17 has the methods but not these defaults. 0.55 implements alpha-group
rendering. Package installation resolves the declared dependencies.

### Linux

With Racket on `PATH`, use the same commands with `racket` and `raco` instead of
the macOS paths. The installer selects x86-64 or ARM64 from the host architecture
and uses the fontconfig-enabled `SkiaSharp.NativeAssets.Linux` 3.119.1 package.
This is required by the library's public default-font-manager and system-font
matching APIs. Install a working fontconfig runtime and system fonts before the
native probe. The installer targets glibc Linux, not Alpine/musl, Windows, or
cross-compilation.

### Testing without a native library

```sh
racket run-tests.rkt --pure
```

This runs the color/validation/ABI-layout tests and the actual ownership layer
with synthetic native tokens. It does not exercise Skia. Without `--pure`, a
missing or incompatible library is an error, not a silently skipped test.

### Use an existing native library

```sh
export RACKET_SKIA_LIBRARY="/absolute/path/to/libSkiaSharp.dylib"
racket tools/doctor.rkt
```

The override is a **filename**, not a directory, and must match the pinned
3.119.1 ABI. It takes precedence over every other location; an invalid override
does not silently load another library. Otherwise the loader tries the local
`native/<platform>/` directory, then the system library search path.

The loader checks native milestone 119 and resolves every required symbol
before allocating objects. This is an early error check, not a proof that an
arbitrary custom milestone-119 build is ABI-compatible. Use the pinned package.
Library loading is lazy and performs no downloads. After a failed load or a
change to the environment variable, start a fresh Racket process.

An already downloaded NuGet archive can be installed offline:

```sh
bash tools/install-native.sh --archive /path/to/native-assets.3.119.1.nupkg
```

The installer validates the archive's package ID and version, retains the
original archive and metadata, and records hashes. Those recorded hashes are
not independent signature verification; HTTPS/NuGet is the download trust
boundary. Stop active renderers before reinstalling a native library.

## Native symbol audit

`tools/audit-symbols.sh` compares every `define-native` declaration in
`private/native.rkt` against the symbols actually exported by the selected
`libSkiaSharp`. Unlike `skia-check!`, which stops when symbol resolution first
fails, the audit reports all missing native names in one pass. Run it after
installing or replacing the native asset and before the doctor when changing
the FFI layer. It honors `RACKET_SKIA_LIBRARY` or accepts an explicit library
filename.

## Install as a Racket package

Installation is optional for the examples, which use relative module paths.
From this directory, after choosing the Racket executables:

```sh
"$RACO" pkg install --auto --name racket-skia "$PWD"
```

The collection can then be imported with:

```racket
(require skia)
```

The package is not published to a Racket catalog by this source distribution.
Package installation does not automatically download native code; run the
installer explicitly. Do not remove a linked source directory while the
package remains installed.

## First drawing

This program works as a file in the extracted root using `"main.rkt"`. Replace
that module path with `skia` after package installation.

```racket
#lang racket/base
(require "main.rkt")

(with-skia ([surface (make-surface 640 480 #:background 'white)]
            [fill (make-paint #:color "#326DE6")]
            [outline (make-paint #:color "#18243B"
                                  #:style 'stroke
                                  #:stroke-width 4)])
  (define canvas (surface-canvas surface))
  (draw-circle canvas 320 240 100 fill)
  (draw-circle canvas 320 240 100 outline)
  (save-png surface "circle.png"))
```

`with-skia` closes resources in reverse binding order, including when an
exception escapes or a later resource constructor fails. Resources can also
be managed explicitly with `skia-close!`; closing twice is harmless. GC
cleanup is a fallback, not a reason to retain thousands of native objects.
Do not return a live resource from a scope that closes that resource.

A canvas is borrowed from a surface, keeps that surface reachable, and is not
closed separately. Explicitly closing the surface invalidates every canvas
alias. A snapshot image owns its own reference and can outlive the original
surface. The wrappers reject use after closure before invoking C.

## Fonts and simple text

Version 0.2 adds owned typefaces and fonts without adding a shaping engine.
The deliberately explicit `draw-simple-text` name means exactly that: Skia
maps the UTF-8 run to glyphs and draws it at a baseline position, but this API
does not perform script shaping, bidirectional layout, line breaking, or font
fallback across a run.

```racket
(with-skia ([surface (make-surface 800 220 #:background 'white)]
            [face (make-typeface)]
            [font (make-font face #:size 48)]
            [paint (make-paint #:color "#18243B")])
  (define canvas (surface-canvas surface))
  (draw-simple-text canvas "Skia from Racket" 40 100 font paint)
  (define metrics (font-get-metrics font))
  (define advance (measure-simple-text font "Skia from Racket"))
  (printf "advance: ~a; ascent: ~a; descent: ~a\n"
          advance
          (font-metrics-ascent metrics)
          (font-metrics-descent metrics))
  (save-png surface "text.png"))
```

`make-typeface` selects the platform default. `typeface-from-family` requests
a named system family/style, while `typeface-from-file` opens a font file and
an optional collection index. `font-glyph-path` and `simple-text-path` expose
Skia's glyph outlines as ordinary owned `skia-path?` values. See the API
reference for ownership, metrics, and accepted style names.

## Shaders and gradients

Version 0.3 adds reference-counted shader resources and attaches them to ordinary
paints. The basic gradient API is intentionally Racket-level rather than a raw
C-array interface:

```racket
(with-skia ([s (make-surface 640 240 #:background 'white)]
            [gradient (make-linear-gradient-shader
                       40 0 600 0 '("#326DE6" "#16A598" "#F38C42")
                       #:positions '(0 1/2 1))]
            [paint (make-paint #:shader gradient)])
  (draw-rounded-rect (surface-canvas s) 40 40 560 160 24 24 paint)
  (save-png s "gradient.png"))
```

Tile modes are `'clamp`, `'repeat`, `'mirror`, and `'decal`. Image shaders can
tile an `image?` independently on x and y; blend shaders combine two shader
outputs using the same blend-mode names as paints. The native paint/shader relationship is reference counted, so closing the
supplied shader wrapper does not invalidate a paint that already retained it.
`paint-shader` returns a distinct owned native reference from the m119 C shim.
Shader-local matrices are not yet public API.

## Encoded images and codecs

Version 0.4 adds high-level encoded image I/O without exposing native codec or
stream pointers. Encoded bytes are copied into Skia-owned data, and encoded
output is copied back into ordinary Racket byte strings.

```racket
(with-skia ([source (make-surface 320 200 #:background 'white)]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source) 160 100 70 blue)
  (with-skia ([image (surface-snapshot source)])
    (define png  (image->png-bytes image))
    (define jpeg (image->jpeg-bytes image #:quality 90))
    (define webp (image->webp-bytes image #:lossless? #t))

    (define info (encoded-image-info-from-bytes jpeg))
    (printf "~a × ~a, ~a\n"
            (encoded-image-info-width info)
            (encoded-image-info-height info)
            (encoded-image-info-format info))

    (with-skia ([decoded (image-from-bytes png)])
      (save-image decoded "copy.webp" 'webp #:exists 'replace))))
```

`image-from-file` and `encoded-image-info-from-file` provide file-backed entry
points. The probe API reports format, dimensions, color/alpha type, encoded
orientation, and the pinned codec shim's frame-info count without materializing
a public image object. `draw-image-subrect` maps a source rectangle directly to
a destination rectangle; `image-subset` instead creates a new owned image.

The implemented encoders are PNG, JPEG, and WebP. JPEG exposes quality,
subsampling, and alpha behavior; WebP exposes quality and lossy/lossless mode.
See the API reference for the exact option symbols and the m119 frame-count
semantics.

## Path effects, measurement, and boolean operations

Version 0.5 extends the vector side of the library without exposing native path
pointers. Path effects are owned, reference-counted resources and can be attached
to ordinary stroke paints:

```racket
(with-skia ([s (make-surface 640 240 #:background 'white)]
            [effect (make-dash-path-effect '(12 7) 3)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 6
                               #:cap 'round
                               #:path-effect effect)]
            [curve (make-path
                    '((move 40 180)
                      (cubic 140 20 480 260 600 60)))])
  (draw-path (surface-canvas s) curve paint)
  (save-png s "dashed-curve.png"))
```

Also available are corner, discrete, trim, compose, and sum effects. A paint
retains its own native path-effect reference, and `paint-path-effect` returns a
newly owned wrapper.

`make-path-measure` deliberately snapshots the supplied path. This differs from
raw `SkPathMeasure`, which stores a pointer to path data: mutating or explicitly
closing the original Racket path therefore cannot invalidate the measure.
Measurement is contour-based and supports length, closed-state queries,
position/tangent sampling, contour traversal, and segment extraction.

```racket
(with-skia ([p (make-path '((move 0 0) (line 100 0)))]
            [m (make-path-measure p)])
  (define-values (x y tx ty)
    (path-measure-position+tangent m 25))
  (printf "point=(~a,~a), tangent=(~a,~a)\n" x y tx ty))
```

Boolean operations return new owned paths: union, intersection, difference,
xor, reverse difference, simplification, and conversion to winding fill.

## Filters and effects

Version 0.6 adds three owned filter families that attach directly to paints and
can also be composed into native filter graphs:

```racket
(with-skia ([s (make-surface 420 220 #:background 'white)]
            [shadow (make-drop-shadow-image-filter
                     12 14 7 7 (rgba 20 35 60 150))]
            [paint (make-paint #:color "#F38C42" #:image-filter shadow)])
  (draw-rounded-rect (surface-canvas s) 90 55 220 110 22 22 paint)
  (save-png s "shadow.png"))
```

Color filters include 4×5 row-major color matrices, blend-mode filters, and
composition. Mask filters currently expose Gaussian blur with the four Skia
styles `'normal`, `'solid`, `'outer`, and `'inner`. Image filters include
Gaussian blur, drop shadow, shadow-only, color-filter wrapping, and composition.
An omitted image-filter input means “use the dynamically drawn source”; supplied
input filters are retained natively, so their Racket wrappers may be closed after
successful construction.

Paints accept `#:color-filter`, `#:mask-filter`, and `#:image-filter`. The three
getter functions return independently owned references, just like the shader and
path-effect getters. Image-filter blur defaults to `'decal` at its input edge;
the pinned m119 blur implementation does not support `'mirror`, so that tile
mode is rejected explicitly by this wrapper.

## Paths and scoped state

```racket
(with-skia ([s (make-surface 640 480 #:background 'white)]
            [p (make-paint #:color 'blue #:style 'stroke #:stroke-width 3)]
            [curve (make-path
                    '((move 0 0)
                      (cubic 60 -100 140 100 200 0)))])
  (define c (surface-canvas s))
  (with-canvas-state c
    (canvas-translate! c 200 240)
    (canvas-scale! c 1.5)
    (draw-path c curve p))
  (save-png s "curve.png"))
```

State scopes restore transforms, clipping, and save-stack depth after normal
return or an exception. They do not undo already drawn pixels. A protected
state cannot be popped by manual restore calls, even through another canvas
alias. Resource and state scopes use continuation barriers; resuming a
continuation into an expired native-resource scope is not supported.

## Coordinates and pixels

The initial origin is the top-left pixel corner. Positive x points right,
positive y points down, and positive degree rotation appears clockwise.
Rectangle arguments are **x, y, width, height**, not opposite corners.
`canvas-rotate!` uses degrees; `canvas-rotate-radians!` is explicit.

`rgba` channels, including alpha, are exact integers from 0 to 255. Inputs are
straight/unpremultiplied colors; the internal surface is premultiplied RGBA8888.
Accepted colors include `(rgb 255 0 0)`, `(rgba 255 0 0 128)`, `'red`,
`"#FF000080"` (RRGGBBAA), and `#x80FF0000` (AARRGGBB). String and integer
conventions intentionally differ and are documented in the API reference.

`surface->rgba-bytes` and `image->rgba-bytes` return copies of tightly packed,
row-major RGBA pixels, with straight alpha by default. Pass
`#:premultiplied? #t` for premultiplied output. No returned buffer aliases Skia
memory. Eight-bit premultiplication can lose color precision at low alpha;
fully transparent RGB values are not preserved by a premultiplied surface.

`current-skia-byte-limit` defaults to 256 MiB per checked buffer/surface or
encoded-input/output size. It is **not** a process memory budget: decoding,
encoding, snapshots, bridges, and copies may consume additional memory. Surfaces
are not custodian-memory-accounted. Dimensions are restricted to 1 through
32768 on each axis for public image resources.

## Interoperation with racket/draw

```racket
(require skia skia/bitmap)

(define bitmap
  (with-skia ([s (make-surface 320 240 #:background 'white)]
              [p (make-paint #:color 'blue)])
    (draw-circle (surface-canvas s) 160 120 80 p)
    (surface->bitmap s)))
```

The bridge copies and reorders premultiplied RGBA to premultiplied ARGB for
`bitmap%`. The resulting bitmap can outlive the surface. This is interoperability through pixels, not a Skia-backed `dc%`.

For an opt-in snapshot to an ordinary Racket `pict`, use `skia/pict`; its
logical backing-scale, color, allocation, and CPU/GPU rules are in the
[pict bridge guide](docs/PICT-BRIDGE.md).

For explicit copied interchange in the other direction—Draw `bitmap%`,
`color%`, and `dc-path%` values to Skia—use the separate `skia/racket-draw`
module. It preserves no live view or density metadata, applies loaded masks by
default when importing a bitmap, and returns a fill style alongside an exported
Draw path. See the [Racket Draw bridge guide](docs/RACKET-DRAW.md).

## Boundaries of this version

The library supports native PDF and SVG document output, shaped/paragraph/
bidirectional text, font management, animated-frame decoding, encoded-orientation
normalization, owned color spaces/codecs, path inspection and affine matrix
operations, and advanced filter graphs/crops. GPU/Metal/Vulkan contexts,
general 3D/perspective transforms, runtime effects, table color filters, and a
Skia-backed `dc<%>` remain outside the public API. Shader-local matrices and
general filter graphs require explicit raster
handling when the pinned SVG serializer cannot represent them faithfully.
PNG/JPEG/WebP are the exposed image encoders. PDF and SVG are output backends,
not input parsers/editors/renderers. See [PDF limits](docs/PDF-OUTPUT.md) and
[the narrower native SVG coverage](docs/SVG-OUTPUT.md#backend-coverage-and-limits).

Native resources are confined to the Racket thread that created them. The
implementation rejects cross-thread drawing and explicit destruction.
Synchronous CPU drawing and encoding can block the Racket scheduler; there is
no threaded or GPU renderer here. Create independent resources in workers
rather than sharing a resource. Parallel-place execution has not been tested.

## Layout

```text
main.rkt                 public drawing API
color.rkt                pure color values/conversions
bitmap.rkt               optional racket/draw pixel-copy bridge
private/native.rkt       lazy, version-checked C ABI binding
private/types.rkt        exact native struct layouts
private/lifetime.rkt     ownership cells and scoped cleanup
private/core.rkt         drawing/resource implementation
private/check.rkt        argument validation and option mapping
examples/                circle, gallery, text, gradients, codecs, path effects, filters, bitmap bridge
tests/                  pure, lifetime, and live-rendering suites
tools/                  explicit native installer and doctor
docs/                   API reference and ABI/source notes
```

See [API reference](docs/API.md), [ABI notes](docs/ABI.md),
[upstream sources](docs/SOURCES.md), and [third-party notice](NOTICE.md).


## Pictures and recording

Version 0.7 adds `picture?` and `picture-recorder?` wrappers over Skia's display-list recording API. A picture is an immutable recording of canvas
commands that can be replayed any number of times onto any canvas.

```racket
(with-skia ([picture
             (call-with-picture
              120 120
              (lambda (c)
                (with-skia ([p (make-paint #:color "#326DE6")])
                  (draw-circle c 60 60 36 p))))]
            [surface (make-surface 300 160 #:background "#F3F5F8")])
  (draw-picture (surface-canvas surface) picture #:x 20 #:y 20)
  (draw-picture (surface-canvas surface) picture #:x 160 #:y 20
                #:width 100 #:height 100)
  (save-png surface "pictures.png"))
```

For incremental use, `make-picture-recorder`,
`picture-recorder-begin-recording!`, and
`picture-recorder-finish-recording!` expose the underlying begin/finish cycle.
Use `picture->image` to rasterize a picture into an immutable `image?`.


## Expanded paths and SVG path data

Version 0.8 extends the path layer with relative commands (`path-rline-to!`,
`path-rquad-to!`, `path-rconic-to!`, `path-rcubic-to!`), direct conic
segments, rounded-rect insertion, path composition, point queries, and SVG
path-data conversion.

```racket
(with-skia ([p (svg-path->path "M 10 10 L 80 10 L 80 50 Z")])
  (path-add-rounded-rect! p 12 12 20 14 4 4)
  (define points (path-points p))
  (define svg-again (path->svg-path p))
  ...)
```

This stage is intentionally limited to SVG **path data** (`d=` content), not a
full SVG document parser or renderer.


## Font managers and positioned text blobs

Version 0.9 adds the native font-manager layer that future shaping code will
use for system font discovery and fallback, together with immutable positioned
`text-blob?` resources. This stage still does **not** perform shaping.

```racket
(with-skia ([fm (default-font-manager)])
  (define face (font-manager-match-character fm #\A #:languages '("en")))
  (when face
    (call-with-skia-resource
     face
     (lambda (tf)
       (with-skia ([font (make-font tf #:size 32)]
                   [paint (make-paint #:color 'black)]
                   [surface (make-surface 260 90 #:background 'white)])
         (define glyphs (font-text->glyphs font "AB"))
         (with-skia ([blob (make-positioned-text-blob
                            font glyphs '((0 0) (38 0)))])
           (draw-text-blob (surface-canvas surface) blob 20 58 paint)
           (save-png surface "positioned.png")))))))
```

`font-manager-match-character` can request a family/style and an ordered list
of BCP-47 language tags. A successful match returns a newly owned `typeface?`;
`#f` means the manager could not provide a matching face. `text-blob?` values
copy the supplied `SkFont` state into native blob storage and can therefore
outlive the Racket font/typeface wrappers used to construct them.

Text blobs take glyph IDs and **absolute positions within the run**. HarfBuzz
shaping is intentionally left for the next stage, where shaping output can be
converted to these positioned runs.


## HarfBuzz shaping

Version 0.10 adds an optional second native dependency: HarfBuzzSharp 8.3.1.2,
which packages HarfBuzz 8.3.1. Requiring `skia` still loads neither native
library eagerly. `make-shaper` is the first operation that needs HarfBuzz.

```racket
(with-skia ([face (make-typeface)]
            [font (make-font face #:size 42)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color "#326DE6")])
  (define run
    (shape-text shaper "office"
                #:language "en"
                #:features '("kern=1")))
  (draw-shaped-run canvas run 40 90 paint))
```

`shape-text` returns an immutable `shaped-run?` containing glyph IDs, UTF-8
cluster byte offsets, explicit glyph positions, and final x/y advances. Optional
`#:direction`, `#:script`, `#:language`, and `#:features` arguments map directly
to HarfBuzz run properties. This stage shapes one font run; it does not yet do
Unicode bidi paragraph resolution, script/fallback run segmentation, line
breaking, or paragraph layout.


## Paragraph text layout

Version 0.11 builds a lightweight paragraph layer above shaped runs. `layout-text`
performs explicit-newline handling, Unicode line breaking, alignment,
and font-metric-based baseline placement. `draw-text-layout` draws the
result using the layout's private font snapshot.

```racket
(with-skia ([font (make-font #:size 28)]
            [sh (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define layout
    (layout-text sh "A paragraph that wraps across several lines."
                 #:width 220
                 #:align 'center))
  (draw-text-layout canvas layout 20 20 paint))
```

A layout is an owned resource containing shaped lines and private font snapshots.
The caller's shaper can close after construction. Keep the layout open while
drawing, and release it with `with-skia` or `skia-close!`. With `#:width`, version 0.13 selects greedy line fits from UAX
#14 opportunities; a span with no legal opportunity is not emergency-split and
may expand the reported layout width beyond `#:width`.

`layout-text` remains a single-run-per-line API: it does not perform UAX #9
mixed-direction bidi resolution or script/font run segmentation. With
`#:direction 'auto`, HarfBuzz guesses the shaping direction; start/end alignment
uses the resolved shaping direction, including for single-glyph runs. Use `layout-mixed-text` when a line needs mixed-direction or fallback runs.


## Mixed-script and bidirectional layout

Version 0.12 adds a multi-run paragraph layer above `layout-text`. It resolves
ordinary mixed LTR/RTL text, segments by bidi level and HarfBuzz Unicode script,
and chooses fallback system fonts at grapheme-cluster boundaries.

```racket
(with-skia ([fm (default-font-manager)]
            [face (make-typeface)]
            [font (make-font face #:size 28)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define layout
    (layout-mixed-text shaper fm
                       "Racket שלום 123 مرحبا"
                       #:width 280))
  (draw-mixed-text-layout canvas layout 20 20 paint))
```

`mixed-text-layout?` exposes visual lines, and each `mixed-text-run?` exposes
its text, shaped run, visual x origin, bidi level/direction, script, and
fallback family (or `#f` for the base shaper). The layout owns snapshots of the
base font and exact fallback faces; the caller's shaper and manager may close.
Both layout types expose original input text and character source maps for
lines and mixed runs, including trimmed text and break insertions.

The mixed bidi resolver now implements ordinary UAX #9 resolution plus explicit
embeddings, overrides, and isolates. `LRE/RLE/LRO/RLO/PDF` use the directional
status stack; `LRI/RLI/FSI/PDI` use isolating run sequences, including FSI's
first-strong direction rule and the specification's overflow limits. Formatting
controls are omitted from HarfBuzz input after they have affected resolved
levels. Paragraph levels are resolved before wrapping and line-specific L1 is
reapplied after UAX #14 chooses visual line boundaries, so an explicit scope can
span wrapped lines without being restarted.

## Unicode line breaking

Version 0.13 replaces the whitespace-only wrapping policy with the default UAX
#14 revision 51 rules over Unicode 15.1 `Line_Break` data. Both paragraph APIs
can therefore wrap unspaced CJK text and respect opening/closing punctuation,
numeric context, non-breaking spaces, word joiners, Hangul, regional indicators,
emoji modifiers, and the Brahmic orthographic-syllable rules introduced in
Unicode 15.1. BK/CR/LF/NL hard separators form explicit layout lines.

The implementation uses the UAX #14 tailoring that keeps Racket default
grapheme clusters intact. SA text uses UAX #14's default AL/CM resolution in
the core resolver. Version 0.17 lets higher-level code supplement those breaks
with dictionary or hyphenation boundaries; emergency breaking inside otherwise-
unbreakable spans is still not synthesized.

## Paragraph justification

Version 0.14 adds `'justify` and `'justify-all` alignment to both paragraph
APIs. `'justify` fills wrapped non-final lines and leaves each paragraph's final
line at logical start; `'justify-all` also fills final and single lines. A
positive `#:width` is required for either mode.

Justification preserves HarfBuzz shaping and bidi/script/font-fallback run
boundaries. It expands only ordinary U+0020 inter-word spaces by shifting the
already-positioned glyphs. NBSP/NNBSP, CJK inter-character expansion, general
letter spacing, and Arabic kashida insertion are intentionally unchanged; those
require script- or language-specific policies beyond this stage.

## Unicode conformance tooling

Version 0.15 adds a development-time harness for the official Unicode 15.1
`LineBreakTest.txt` and `BidiCharacterTest.txt` corpora. The large upstream test
files are not vendored. Run `tools/run-unicode-conformance.sh` to download the
pinned files temporarily, or pass `--data-dir` to use an offline copy. The
line-break runner filters expected opportunities inside default grapheme
clusters to match this library's documented UAX #14 tailoring.

## Explicit bidirectional controls

Version 0.16 completes the explicit-control layer used by `layout-mixed-text`.
Embeddings, overrides, isolates, FSI, overflow behavior, bracket resolution in
isolating run sequences, and line-specific trailing resets are handled before
script/font segmentation. The controls themselves remain formatting metadata
and do not become drawable glyphs.

## External segmentation and hyphenation hooks

Version 0.17 adds `#:break-provider` to both paragraph APIs. A provider is a
procedure of two arguments, `(paragraph language)`, called once for each
hard-break-delimited paragraph when wrapping is enabled. It returns a list of
additional string indices or `layout-break-opportunity?` values. The indices
supplement normal UAX #14 opportunities and must fall on Racket default-
grapheme boundaries.

`make-layout-break-opportunity` can attach display-only text to a boundary. For
example, `(make-layout-break-opportunity 5 "-")` makes index 5 a legal break
and draws the hyphen only if that boundary is selected. This supports external
Thai/Lao/Khmer segmenters and language-specific hyphenators without building a
dictionary into this standalone Skia binding. In mixed bidi text the suffix
inherits the resolved level immediately before the break and does not alter the
logical paragraph's UAX #9 resolution.

## Script-aware justification

Version 0.18 extends `'justify` and `'justify-all` beyond U+0020 word spaces.
Han, Hiragana, Katakana, and Hangul runs gain inter-character opportunities
between adjacent CJK grapheme clusters, including compatible boundaries between
separate visual runs. Common punctuation is not turned into a stretch point.

Arabic runs use Unicode 15.1 Joining_Type data to find cursive boundaries where
U+0640 ARABIC TATWEEL can be inserted as display-only shaping material. The
logical line text and bidi paragraph remain unchanged; HarfBuzz reshapes the
justified display run, cluster offsets are mapped back to logical UTF-8
coordinates, and any small width remainder is absorbed at the same
cursive connections. Mixed lines distribute slack across word-space, CJK, and
Arabic opportunities instead of assigning it to one script. The candidate
selection is structural rather than a language-specific typographic ranking;
font-specific `jalt` policies and editorial kashida preferences remain outside
this stage.

## Color spaces and ICC color management

Version 0.19 adds explicit color-space metadata to the CPU image/surface path.
`make-srgb-color-space` and `make-linear-srgb-color-space` expose owned wrappers
around Skia's built-in spaces; gamma/equality helpers and transfer-function
conversion keep the native color-space object behind the Racket API.

ICC profiles can be imported from and exported to byte strings. Raster surfaces
and copied RGBA images accept `#:color-space`; snapshots retain that tag.
`surface->rgba-bytes` and `image->rgba-bytes` optionally take a destination
color space, so Skia converts pixels during CPU readback instead of merely
relabeling the channel bytes. Encoded-output ICC injection and arbitrary RGB
transfer/matrix construction are not part of this stage.

## Floating-point pixels (0.71)

See [FLOAT-PIXELS.md](docs/FLOAT-PIXELS.md) for Color4f values, F16/F32 storage, source-space gradients and explicit output quantization.

## Direct image operations (0.72)

See [IMAGE-OPERATIONS.md](docs/IMAGE-OPERATIONS.md) for CPU/GPU filter results, preserved offsets, image reads/scales, materialization and raw shader semantics.

## GPU formats and surface properties (0.73)

See [GPU-FORMATS.md](docs/GPU-FORMATS.md) for typed GPU targets, detached properties, explicit format-aware readback and configuration-aware staging.

## Advanced layers and canvases (0.74)

See [ADVANCED-CANVASES.md](docs/ADVANCED-CANVASES.md) for checked layer records, captured native drawables, scoped NoDraw/NWay/Overdraw canvases, and their output/ownership restrictions.

## Native streams and buffered ports (0.75a)

Package version `0.75` adds native memory/file input, dynamic-memory output,
owned codec/typeface/trusted-picture input and explicitly buffered Racket
port adapters. The live callback/streamed-publication bridge remains 0.75b.
See [STREAMS.md](docs/STREAMS.md).

## Compiler-free live ports (0.75b)

[Live streams](docs/LIVE-STREAMS.md) provides one-shot input and streamed output
through ordinary Racket ports using the existing precompiled SkiaSharp library.
No extra native library or compiler is required. It uses 64-bit Racket CS with
OS-thread support; live operations use a protected Racket callback service thread.
Run `python tools/validate-live-streams.py --racket /path/to/racket --require-renderers`.
Earlier compiler-dependent 0.75b delivery bundles are superseded.

### Codec size and subset queries (0.76a)

`codec-scaled-dimensions` and `codec-supported-subset` expose native encoded-pixel
negotiation without decoding or a crop/resampling fallback. See
[Codec queries](docs/CODEC-QUERIES.md) for native rounding, unsupported subsets,
EXIF coordinates, lifetime rules and validation. Native scanline sessions are available in 0.76b; incremental sessions
remain stage 0.76c.

### Native scanline decoding (0.76b)

Owned scanline sessions read or skip native decoder rows without a full-decode
fallback. Native JPEG scaling, explicit row mapping, detached typed batches and
terminal partial-input reporting are documented in
[CODEC-SCANLINES.md](docs/CODEC-SCANLINES.md). The native-stream and compiler-free
installation model is unchanged. Incremental decoding remains stage 0.76c.

### Retained incremental decoding (0.76c)

Owned byte-fed sessions retain their native decoder and initialized destination
between steps. See [CODEC-INCREMENTAL.md](docs/CODEC-INCREMENTAL.md) for PNG
chunk framing, partial-snapshot semantics, limits, and cancellation. No new
compiler, native helper or retained user-port callback is needed.

### Global caches and memory statistics (0.77a)

`graphics.rkt` exposes explicit global cache limits, usage, purges, and bounded
detached memory snapshots. See [GLOBAL-CACHES.md](docs/GLOBAL-CACHES.md). No
cache policy is changed by import, and no compiler/native helper is added.

### GPU context options and targeted control (0.77b)

`gpu.rkt` exposes immutable native context options, targeted surface/image flush,
and healthy-host release-and-abandon. See [GPU-CONTEXT-CONTROLS.md](docs/GPU-CONTEXT-CONTROLS.md).
Existing calls retain native defaults; no new compiler/native helper is needed.

### GPU diagnostics and interface selection (0.77c)

`gpu-memory-statistics`, `gpu-gl-interface-info`, and `gpu-gl-has-extension?`
return bounded detached diagnostics from a matching active context. GL factories
accept `#:gl-interface`; defaults are preserved. See [GPU-DIAGNOSTICS.md](docs/GPU-DIAGNOSTICS.md).

## 0.78b — Small remaining gaps

Native-backed `xyz-d50-concat` and `xyz-d50-invert` are public through `skia`. The null-surface factory is deliberately excluded; the existing scoped no-draw canvas remains the diagnostic alternative. See [contracts and acceptance](docs/SMALL-GAPS.md). No-open-gaps source policy is not 1.0 release approval.

## 0.78c — Public API stabilization

See [the API contract](docs/API-CONTRACTS.md) and [generated export/signature index](docs/PUBLIC-API.md). The policy distinguishes stable, experimental and private interfaces without changing existing exports. Runtime reflection is checked separately from native/rendering evidence; 0.78d release validation remains outstanding.

## 0.78d — Release candidate validation

The manual **Release candidate** workflow runs CI, full Acceptance and API inventory at one commit. Its final gate requires every reviewed matrix job/step and hashed evidence ZIP from the same attempt, then builds a deterministic source archive. See [release validation](docs/RELEASE-CANDIDATE.md). No tag, publication or 1.0 approval is automatic.
