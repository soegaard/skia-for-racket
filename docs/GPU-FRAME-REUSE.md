# GPU frame staging reuse — 0.62

## Scope and unchanged public API

The 0.61 `skia/render-canvas` factory and the concrete raster/GPU canvas classes
are unchanged. Application paint callbacks need no changes. `get-dc` remains
callback-only in the common API. GPU drawing contexts expire on every callback
exit and are never revived. Raster storage and persistent raster access are
unchanged. CPU-only imports do not initialize a GUI or a GPU context.

The optimization applies to `call-with-gpu-frame-dc`, including concrete GPU
canvases and the common GPU/automatic canvas paths. The separately borrowed
`call-with-gpu-surface-dc` API retains its existing ownership contract.

## Chosen optimization

The pre-0.62 frame path creates a staging GPU surface for each DC callback, draws
the scene, snapshots that surface on the GPU, and copies it onto the presenter's
borrowed target. This release retains the staging wrapper across compatible
frames rather than drawing directly into the window target:

```text
presenter owns one staging GPU surface
             |
       fresh frame DC
             |
     draw, clear, alpha groups
             |
      GPU snapshot + Src copy
             |
     borrowed presenter target
             |
       normal presentation
```

Keeping the commit boundary avoids exposing partially rendered callback content
to the presenter target after an application exception or continuation escape.
It also preserves existing explicit root-snapshot/readback semantics and
cross-backend color behavior. The GPU snapshot and GPU-to-GPU copy still happen;
this is not zero-copy or direct-to-drawable rendering.

The selected native acceptance gate compares a 32-frame reusable run against a
private fresh-allocation reference. It requires **1 creation and 31 reuses** for
the reusable run, versus **32 creations and no reuses** for the reference. These
are test requirements, not a benchmark result claimed by the source code.

## Ownership and compatibility key

Each presenter owns its cache, and each presenter has one fixed context/backend.
A cache hit requires the exact physical width and height. The cache is not
indexed globally, not shared between presenters, and not retained through a
public expired frame. Frame invalidation clears its private cache reference.

Logical width/height and X/Y device scales are recalculated for every fresh DC.
Logical-only scale changes do not require replacement of compatible physical
storage. Rotating swap-chain/backbuffer identities do not change the staging
key. The staging format remains the same format chosen by `make-gpu-surface`;
no public configurable format or color-space selection is added here.

Physical resize retires the old wrapper before constructing the replacement.
Returning to an earlier size constructs a new target rather than keeping a
size-indexed pool. A hidden or zero-drawable window does not acquire a frame; its
one previously allocated idle target can remain until a later resize or close.

Every DC callback has fresh drawing state and its own alpha stack. The root is
cleared before drawing, and incomplete alpha groups are discarded by the
existing DC scope cleanup. A failed or escaped **DC scope** retires its staging
target. A later presenter cancellation after a successfully completed DC scope
(such as a resize/hide during the enclosing callback) can retain the staging
wrapper; the next DC still clears it and checks its physical extent.

The allocation-size limit is checked on a cache hit as well as a miss. Closing a
cache while it is borrowed, nested borrowing, cross-thread use, construction in
a future, and reentering a captured completed continuation are rejected.

Presenter closure retires its staging wrapper **before** its adapter closes the
context. Existing finalizer, custodian, explicit close and deferred close paths
converge at that boundary. `skia-close!` queues GPU resource retirement through
the normal ownership mechanism; this change does not insert a GPU completion
wait into normal painting. If disposal throws, the cache remains rooted and
quarantined instead of retrying an indeterminate release or reusing that target.
Quarantine intentionally has no automatic recovery path.

## Memory and performance limits

At most one staging **wrapper** is cached per presenter. This is not a bound on
all GPU allocations or on peak memory: snapshots, native copy-on-write, alpha
surfaces, pending command buffers, and retired resources awaiting domain cleanup
can use additional storage. Multiple live presenters each retain their own
staging target, so idle retained memory is a tradeoff for fewer constructor calls.

The public DC object itself is still recreated every frame. Alpha-group targets
are not pooled. Snapshot creation and the final copy are not eliminated. Native
Skia can reuse or allocate driver storage independently of these wrapper counts.
No frame-rate, latency, GPU-time, physical-display or zero-allocation result is
implied by passing the constructor-count gate.

## Diagnostics

`gpu-presenter-info` adds a detached immutable `frame_target_cache` hash with:

- `policy`, `pixel_size`, `live_targets`, `busy`, `closed`, `quarantined`;
- `creations`, `reuses`, `retirements` and an explicit `counts` description.

Counts refer only to this presenter's staging surface. No native pointer, DC,
callback, surface or context is returned in the diagnostic hash. Pure imports
report no driver probe or performance measurement.

The private GPU I/O ledger gains `dc-frame-target` events with `action` equal to
`create`, `reuse` or `retire`, plus a reason and physical dimensions. Existing
readback/snapshot/presentation events remain. Absence of wrapper-recorded
`readback` events is not a measurement of arbitrary internal driver stalls.

`current-frame-target-reuse?` lives only in the private cache module. It selects
the fresh-allocation reference for tests and is not exported by `skia/gpu`,
`skia/gpu-dc` or the canvas API. The disposition is captured before entering the
callback, so changes made inside it do not change that borrow's cleanup policy.

## Acceptance and execution

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 tools/test-gpu-frame-reuse.py
"$RACKET" tests/gpu-frame-target-pure-test.rkt
python3 tools/validate-gpu-frame-reuse.py --racket "$RACKET" --require-gui
```

The default without `--require-gui` is a native headless gate. `--require-gpu` is
an alias for `--require-gui` for compatibility with the expanded render-canvas
workflow. On macOS the automatic native/GUI backend is Metal; on Linux the
native gate uses EGL and GUI uses OpenGL; Windows uses explicit Direct3D (WARP
in CI). `--adapter warp` must be paired with Direct3D. Missing backends, displays,
interpreter executables, completion markers, captures or cleanup are failures,
not skipped success or implicit CPU fallback.

The driver requires:

1. The 32 pure cache ownership/state cases, also included in `run-tests.rkt`.
2. The complete 0.60 native consumer gate in headless mode, or the complete 0.61
   raster/GPU/auto gate in GUI mode, including its prior consumer prerequisites.
3. The 14 actual native Ganesh tests: steady-state constructor counts, final
   target pixels compared with the fresh reference for all 12 real workloads,
   resize and independent logical scaling, separate presenters, failed/escaped
   callbacks, explicit snapshots, expiry, root clearing, and actual context close.
4. In GUI mode, real 0.61 reports for all three renderer selections. Each GPU
   and auto size has 12 normal consumer frames with at most one staging creation
   and at least 11 reuses. An exposure may warm the cache before measurement.
   Normal frame ledgers remain readback-free; inspection frames retain positive
   readback controls and the existing pixel oracles.

The GUI capture is the DC backing, not physical screen pixels. The native tests
separately inspect final targets after GPU-to-GPU commit. Fresh-reference pixel
comparison tolerates a maximum channel difference of 2 on the same backend;
independent existing consumer oracles still have to pass.

Evidence is written to a new `output/gpu-frame-reuse-0.62-*` directory. Start with
`validation.json` and `logs/`. `baseline/validation.json` and its retained review
pages, captures, comparison results and prerequisite reports provide the full
0.60/0.61 evidence. Constructor receipts distinguish pre-close counts from
post-close retirement and contain no claimed timing or driver-allocation metric.

The existing `render-canvas.yml` workflow selects this expanded driver on Linux
Racket 8.18/9.3 with Mesa/Xvfb and Windows Racket 9.3 with WARP. Existing ordinary
CI and GPU DC workflows remain unchanged apart from the source check registry;
branch-protection and the `CI required` aggregate are not modified. The patch
also corrects the baseline Windows Python path-separator assertion.

## Implementation verification boundary

Execution records, not the presence of a workflow or test file, establish a
backend pass. The delivery's `VALIDATION.md` states which checks were actually
run. Native and GUI results must come from the selected Racket installation.

## 0.73 configuration extension

The key now also compares the staging color/alpha format, copied color-space descriptor, requested samples and surface properties. The presenter/context remains the owner. Same-size configuration changes retire before replacement; no width/height-only cache hit is allowed for newly configured frame DCs. See [GPU-FORMATS.md](GPU-FORMATS.md).
