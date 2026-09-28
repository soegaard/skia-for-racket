# GPU image validation

> Historical validation sequence. For the current combined OpenGL/Metal
> run use [GPU-METAL-TESTING.md](GPU-METAL-TESTING.md). Do not reapply an
> earlier patch to an updated checkout.

Baseline: `0eea009d393500cda7dc4a6848579c09300f53db` (0.39). The maintainer's
macOS/aarch64 / Apple M4 Pro automated 0.39 validation and interactive window
inspection passed before this work. Those results do not establish a 0.40 pass.

Run from the repository root, with the same Racket executable used for the
preceding revisions:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The runner retains the CPU regressions, ABI mirrors, 0.38 OpenGL/Metal probes,
and 0.39 offscreen/window checks. It then adds the GPU-image live suite and two
image workflows before regenerating `SOURCE-SHA256SUMS.txt` last. Each run has
its own `output/gpu-0.40-*/` directory. Prior probe JSON keeps its original stage
label, since those are deliberately unchanged regression diagnostics.

The image stage adds **33 pure and 42 live RackUnit source cases**. The pure
suite exercises real lifetime/domain bookkeeping with mock native operations;
`run-tests.rkt --pure` requires no Skia library or GUI. The live suite requires
two independent GL hosts, uploads/snapshots/subsets, native retained graphs,
mutable paint and recorder transitions, explicit transfers, CPU/PDF/SVG/SKP
rejection, and cross-context rejection. The existing foundation and surface
suites remain part of validation rather than being replaced by these tests.

The source-structure checker verifies executable suite placement and advertised
counts. It is not a Racket reader/expander. Successful Python tests or C mirrors
are not a substitute for `raco make`, RackUnit, or native rendering.
The added Python checks include 35 synthetic image-inspector cases and nine
mocked validator-orchestration cases; none of those tests loads a GPU library.

`gpu-image-doctor.rkt` runs both image workflows:

* `upload-reuse`: explicitly upload an independent CPU pattern, make a GPU
  subset, build shader/local-matrix/SkSL/filter/paint/picture dependencies,
  close the original wrappers, drain their queued references, and replay twice.
* `snapshot-graph`: draw the pattern into a GPU surface, snapshot it, redraw
  the source with magenta and close it, then construct and replay the retained
  graph in the same way. The CPU reference has its own CPU source/snapshot.

Resident preparation/replay and final output transfer use separate diagnostic
ledgers. Reuse must have no explicit CPU wait/readback. Final output uses an
explicit completed readback. Driver-internal stalls/copies are not measured.
A separate image is detached using the GPU-image staging readback path; it is
checked and encoded only after both GPU contexts are closed.

Review `images.review.html`, `images.inspection.json`, and
`images.diagnostic.json`. There are four CPU/GPU scene PNGs and one detached
8x8 pattern. The inspector validates actual PNGs, exact corner/alpha and known
image/subset/filter samples, bounded content-ROI comparisons, native identity,
context generations, zero remaining children/releases, and the two ledgers.
It uses the existing image-comparison tolerances (mean channel error <= 1.5;
<= 2% of ROI pixels with channel error > 24), not universal pixel identity.
A failed rerun removes stale successful review/inspection outputs for its prefix.

Targeted rerun after compilation:

```bash
"$RACKET" tools/gpu-image-doctor.rkt --prefix output/gpu-images-0.40-manual &&
python3 tools/inspect-gpu-images.py --probe-prefix output/gpu-images-0.40-manual
```

`GPU_MODE=optional` may skip initialization unavailability; a test/render/cleanup
failure still fails. `GPU_MODE=off` explicitly omits all live GPU checks. Neither
is a complete GPU pass. `REQUIRE_HARDWARE=1` requires a hardware-reported driver
string, not independent hardware attestation. Windows/Linux require their own
real runs. The existing Metal probe establishes construction/teardown only.

The authoring environment did not have Racket or a runnable Skia library.
Its executable checks cover Python self-tests, source structure, a C ABI mirror,
and patch contexts, not Racket/native execution. Complete modified source files
were compared to the pinned Git blob hashes; larger core/native/document edits
were built and application-tested from fetched exact contexts, not a complete
repository checkout. The delivery's authoring report records those limitations.
