# GPU backends and shared validation — 0.51

0.51 adds a narrow Direct3D external-resource handoff API. The common drawing
and parity contracts below remain unchanged. See [Direct3D interop](GPU-D3D12-INTEROP.md)
for retained single-use descriptors, explicit fences, GPU copies and scoped
canvas borrowing. This is not unrestricted zero-copy or cross-device interop.

## One drawing API, explicit execution

The implemented Ganesh backends are `opengl`, `metal` and `direct3d`.
Surfaces, canvases, GPU images, explicit uploads/readbacks, retained context
identity, cache controls, bounded document rasterization and presenter frames
use the existing common APIs. Backends still have different native hosts,
ownership and synchronization requirements. “Parity” does not mean that all
native interoperability or presentation features are identical.

The default natives remain SkiaSharp 3.119.1 / Skia ABI 119.0 and
HarfBuzzSharp 8.3.1.2. GUI `auto` selection is unchanged: Metal on macOS,
OpenGL elsewhere. Explicit hardware selection never silently becomes WARP,
another backend, or CPU drawing.

## Source-only capability declarations

```racket
(require skia/gpu)

(gpu-backends)                         ; '(opengl metal direct3d)
(gpu-backend? 'direct3d)                ; #t
(gpu-backend? 'vulkan)                  ; #f
(gpu-backend-capabilities 'direct3d)    ; immutable hash
```

These operations do not load a native library, resolve GPU symbols, create a
context, or initialize a GUI. Invalid backend values raise an argument error.
The result and its nested hashes/strings are immutable, detached metadata.

A result contains `backend`, `native_backend`, `engine`, `platforms`,
`owned_context`, `software_selection` and a `features` hash. Here,
`owned_context` describes direct construction with `make-gpu-context` without
a supplied host provider; it is false for OpenGL. The separate EGL helper can
still own its OpenGL host/context. Platform declarations describe wrapper
paths, not the required CI matrix or proof that a device exists.

Every result also explicitly contains:

```racket
'scope "wrapper-declarations"
'native_probe_performed #f
'runtime_availability "not-probed"
'hardware_acceleration_verified #f
'visible_pixels_verified #f
'performance_measured #f
```

The false evidence fields mean **not verified by this query**, not that the
machine lacks hardware or that rendering has failed. Successful native
construction, context diagnostics and actual validation are separate evidence.
Use `gpu-context-info` for a context that has actually been created.

| Feature key | OpenGL | Metal | Direct3D |
|---|---|---|---|
| `offscreen` | Implemented | Implemented | Implemented |
| `images` | Implemented | Implemented | Implemented |
| `explicit_transfers` | Implemented | Implemented | Implemented |
| `cache_controls` | Implemented | Implemented | Implemented |
| `presentation` | Implemented | Implemented | Implemented via DXGI |
| `document_executor` | Implemented | Implemented | Implemented in 0.50 |
| `external_resource_interop` | Scoped GL borrowing/copy | Not implemented | Same-device copy/scoped drawing (0.51) |

The registry is `private/gpu-backends.json`. Racket argument checks and native
ID lookup, the Python inspectors, and the pure metadata doctor use that same
source. It is not a registry of native symbol groups: the private `dxgi` symbol
group and backend-specific GL/Metal/D3D APIs remain distinct.

## Direct3D document rendering

A Direct3D context now works with the existing `skia/gpu-output` executor:

```racket
(require skia/gpu skia/gpu-output)

(define context
  (make-gpu-context #:backend 'direct3d #:adapter 'warp))
(define executor (make-gpu-raster-executor context))
```

Pass `executor` as `#:raster-executor` to `draw-output-group`, exactly as for
OpenGL or Metal. The borrowed executor does not own `context`; close the
context after its resources and work are retired. The existing lazy owned
executor form also accepts a factory creating a Direct3D context.

Representation policy is unchanged. Vector-only and require-vector checks
still precede GPU creation; authoring is captured once; links and native text
cannot be silently discarded. A selected GPU raster group performs an
explicit readback and returns a CPU-owned image for document retention.
Completed Direct3D execution is reported with backend `direct3d`, transfer
`gpu-to-cpu`, and one readback, not mislabelled as native vector output.

The existing 42-case document suite is reused. Its retained documents test
four scenes in CPU/GPU variants and PDF/SVG formats: **16 files**. The eight
GPU groups perform eight readbacks. Serialization after GPU teardown, vector
surroundings, links, placement, embedded SVG image pixels and PDF structure
are checked. PDF rendered pixels and PDF/A conformance are not certified.

## Authoritative surface identity

`gpu-surface-info` first checks the real recording-context pointer and native
backend against its owning domain. Only after that check does the shared pure
helper stamp `backend`, `native_backend`, `context_generation`,
`context_matches`, `storage`, `width` and `height` into the description.

A specialized constructor no longer has to remember the symbolic backend
field that was omitted by the initial 0.49 DXGI adapter. Constructor labels
cannot override validated identity. Native mismatches still fail; this change
does not turn a failed native check into a metadata-only success.

## Shared validation command

The standalone driver requires installed natives, the chosen Racket
interpreter and a usable native host. It does not install dependencies or
change the default backend. Run from the source repository:

```bash
# macOS: common offscreen and presenter workloads through Metal.
python3 tools/validate-gpu-parity.py --backend metal --scope all --racket "$RACKET"

# Explicit desktop OpenGL.
python3 tools/validate-gpu-parity.py --backend opengl --host gui --scope all --racket "$RACKET"

# Linux without a display server: explicit EGL software/hardware environment.
python3 tools/validate-gpu-parity.py --backend opengl --host egl --scope offscreen --racket "$RACKET"
```

On Windows:

```powershell
python tools/validate-gpu-parity.py --backend direct3d --adapter warp --scope all
python tools/validate-gpu-parity.py --backend direct3d --adapter hardware --adapter-index 0 --scope all
```

`--scope offscreen` runs scenes, images, documents and cache/performance stress.
`--scope presentation` runs the shared redraw/timing workload.
`--scope all` runs both. EGL cannot be combined with presentation.
For offscreen Metal/Direct3D, `--host owned` is the default. The same owned
backend construction is used without an implicit GUI. A presenter explicitly
uses its GUI host. Existing doctors also gain `--adapter` and
`--adapter-index` options for Direct3D; malformed indices fail before creation.

Every invocation creates a fresh evidence directory and persistent command
logs. `--output PATH` selects a new parent directory; existing output is never
reused or overwritten. All `raco` work is invoked through the selected
`racket -l raco -- ...`, not an unrelated executable on `PATH`.

| Common implementation | Required workload |
|---|---|
| Offscreen doctor / inspector | 33 native cases; eight rich CPU/GPU scene pairs; explicit readback and detached-image teardown |
| Image doctor / inspector | 42 native cases; upload and snapshot workflows; retained graphs/subsets; no hidden normal-frame readback |
| Output doctor / inspector | 42 native cases; 16 actual PDF/SVG files; unchanged strict representation policy |
| Performance doctor / inspector | 20 cache cases; three scenes; 12 measured samples and three warmups; 3 × 180 retained-graph stress frames |
| Redraw doctor / inspector | Six recreated windows/contexts; 180 timed frames each; resize, coalesced redraw and resource envelopes |

The offscreen portion runs **137 native case executions**. Some are also run
by the retained 0.48 gate; this is intentional reuse, not additional distinct
test definitions. No scene tolerance or default stress size is relaxed.
Individual reports retain their existing workload/schema stages (0.41, 0.44,
0.45); `parity.inspection.json` identifies the 0.50 composed validation.

The aggregate checks selected interpreter identity, raw and inspected status,
backend/adapter identity, invocation ID, full counts, actual workload source
fingerprints, and source-manifest verification before and after execution.
It hashes retained files and publishes its success marker last. A timeout,
missing backend, failed doctor, malformed/foreign report, failed inspector,
changed source or incomplete workload remains a failure.

## Direct3D synchronization and timing

A live DXGI presenter pins its context with one internal resource. The shared
redraw resource envelope expects that one pin while ready and zero resources
after closure; it does not treat the pin as a leak or remove the ownership
protection to satisfy a generic zero-count assertion.

Direct3D presenter calls can wait for a buffer-reuse or resize fence. Timing
rows report `backend_fence_waits`, `retry_backend_fence_waits`, and
`backend_fence_waits_included_in_elapsed`. Per-window totals separately account
for waits in measured/retried calls and queued/cleanup work outside samples.
These totals must equal the DXGI host's real `blocking_fence_waits` counter.
The elapsed-time sample includes the successful call's `backend_fence_waits`;
`retry_backend_fence_waits` records preceding skipped attempts, whose durations
are not included in that successful sample. The existing normal I/O ledger
protocol is unchanged.

Occluded `Present` calls are not successful measured frames. Their callbacks
and waits are accounted for separately before a bounded retry. Callback time
is nested within host presenter-call latency. These are not isolated GPU
timestamps, display latency, a GPU hardware attestation or a speed ranking.
DXGI's numeric adapter identity and LUID are checked directly; no OpenGL-style
vendor or API-version strings are invented for it.

## Required CI and retained boundaries

The original required `d3d12` and `dxgi` jobs stay separate. Their original
checks execute first. The installed-package hook then requires offscreen
parity in `d3d12`, and shared redraw parity in `dxgi`. A parity failure fails
the job and therefore `CI required`; it is not informational or skippable.
The CPU, minimum-Racket, EGL and candidate-native-ABI jobs are unchanged.

New artifacts are copied from the isolated installed package before its
scratch home is removed. They include individual diagnostics/reviews, PNGs,
PDFs/SVGs, timing CSVs, the aggregate and failure records. No native libraries
or compiled payloads are included in this source delivery.

The 0.49 DXGI SDK/COM tests, shared 28-case presenter suite and 18 actual
swap-chain captures remain independently required. The new timing pass is
not a replacement for those checks and does not certify physical screen
pixels. The legacy GL construction/window probes, GL/Metal comparison
inspector, GL external interop and platform-specific native adapters remain
intentionally specialized. The new driver composes backend-independent
workloads rather than pretending those platform-specific operations are
universal.

The 0.49 baseline was accepted by the maintainer with the documented Linux
Racket-download exception. That historical exception does not add a skip path
to 0.50. New 0.50 runtime acceptance requires its own host/CI results.
