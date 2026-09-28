# Offscreen Metal validation

Implementation baseline: `dca0aa876b1b42f293db2fef235eecee0ed7cd5a` (0.40,
"Add GPU image support"). The maintainer supplied a passing 0.40 automated
macOS/aarch64 run, including all GPU-image tests and retained workflows. The
preceding OpenGL window also passed manual visual inspection. These are
historical baseline results, not a 0.41 Metal-rendering result.

## Complete run

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The runner creates a fresh `output/gpu-0.41-*/` directory. On macOS, required
mode runs both OpenGL and Metal. No optional absence becomes a required pass.
`GPU_MODE=optional` permits initial unavailability only; a rendering, test,
comparison or teardown error still fails. `GPU_MODE=off` explicitly omits live
GPU work and does not establish Metal support. Linux/Windows retain OpenGL
checks and explicitly report the macOS-only Metal/parity checks as not run.
`REQUIRE_HARDWARE=1` additionally requires hardware-reported renderer/device
names for live rendering, not merely a successful construction probe.

The same selected Racket compiles all dynamically loaded modules, runs the CPU
regressions, the existing GPU pure suites and the 34 new Metal pure source
cases. The shared 33-case surface and 42-case image suites then run separately
on OpenGL and Metal. A further 8-case Metal-specific suite checks ownership,
yieldable application scopes, GC, shutdown and abandonment. The 9-case
cross-backend suite checks rejection and explicit CPU transfer in both
directions. Counts are executable-source cases, not a claim of tests run in
the authoring environment.

The rendering sequence also includes three fresh Metal context/smoke/readback/
close cycles, the eight shared scenes on each backend, and both retained-image
workflows on each backend. Original wrappers close before retained replay;
resident drawing and final CPU download have separate transfer traces.

The earlier three-cycle OpenGL and construction-only Metal probes remain.
The diagnostic window is still OpenGL-only. Its automated checks are not a
new visual inspection and do not establish Metal presentation.

## Review artifacts

| Prefix or file | Meaning |
|---|---|
| `offscreen-opengl.*`, `offscreen-metal.*` | Shared surface suite and eight CPU/GPU scene pairs per backend. |
| `images-opengl.*`, `images-metal.*` | Shared image suite, two retained workflows and post-teardown CPU image per backend. |
| `metal-lifecycle.*` | Three exact Metal smoke PNGs and the Metal-specific native suite. |
| `cross-backend.*` | Actual OpenGL/Metal native rejection and explicit two-way transfer suite. |
| `parity.review.html` | CPU/OpenGL/Metal columns for all ten shared scene/workflow comparisons. |
| `parity.inspection.json` | Revalidated raw diagnostics, pixel comparisons, lifecycle and cross-backend acceptance. |
| `window.*` | Existing OpenGL framebuffer/resize/swap diagnostic; no Metal presenter. |
| `validation.json` | Selected commands, skips, run ID and scope of the successful result. |

The combined inspector does not trust previously generated success JSON. It
reads the raw diagnostics and PNGs again, validates native backend IDs, queue
ownership, test coverage, context identity, closed counts and transfer traces,
and compares OpenGL output directly with Metal output. CPU references must
agree before that comparison. A shared run identifier prevents accidentally
combining reports from different validation directories/runs.

Exact samples check orientation, alpha, known source colors, image subsets and
filters. Existing explicit per-scene numerical tolerances cover differences in
sampling, antialiasing and shader arithmetic. A tolerance failure is reported,
not silently widened. Review geometry edges, text, shadows, transformed images
and alpha in `parity.review.html`; these checks do not promise universal pixel
identity. Device names, native version and platform are retained with results.

No successful inspection or review is published after failed checks. A failed
reinspection removes stale success files for that prefix. Source sums are
regenerated **last**, only after every selected automated check succeeds. The
C ABI mirrors are still local layout checks, not evidence of Metal execution.

## Headless Metal-only checks

These commands do not create a Racket GUI/OpenGL host:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" tools/gpu-metal-doctor.rkt --prefix output/metal-lifecycle &&
python3 tools/inspect-gpu-parity.py --probe-prefix output/metal-lifecycle &&
"$RACKET" tools/gpu-offscreen-doctor.rkt --backend metal --prefix output/offscreen-metal &&
python3 tools/inspect-gpu-offscreen.py --probe-prefix output/offscreen-metal &&
"$RACKET" tools/gpu-image-doctor.rkt --backend metal --prefix output/images-metal &&
python3 tools/inspect-gpu-images.py --probe-prefix output/images-metal
```

Use the complete runner for the cross-backend review; it supplies the matching
`SKIA_GPU_VALIDATION_RUN` environment variable to all required diagnostics.
Standalone individual inspectors do not require a combined-run identifier.

## Delivery integrity and evidence

`tools/test-patch-delivery.py` checks unified-hunk line counts and meaningful
context. Its regression suite exercises ordinary forward/reverse Git patch
application, a malformed postimage count, omitted body lines, zero/blank
context, new files and unchanged later documentation. It does not authorize
`--unidiff-zero`, `--recount` or a forced application as a delivery workaround.

```bash
python3 tools/test-patch-delivery.py --patch /path/to/the-delivery.patch
git apply --check --verbose /path/to/the-delivery.patch
```

The authoring report separates complete source files verified against pinned
Git blob hashes, exact fetched documentation contexts, pure Python/C checks,
and host execution that has not been performed. No Racket/native/platform
passing count may be inferred from source parsing or mock subprocess tests.
The user-supplied host results, not an unavailable authoring GPU, establish
actual offscreen Metal parity.
