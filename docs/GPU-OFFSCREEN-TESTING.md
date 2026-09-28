# Offscreen OpenGL validation

> Historical validation sequence. For the current combined OpenGL/Metal
> run use [GPU-METAL-TESTING.md](GPU-METAL-TESTING.md). Do not reapply an
> earlier patch to an updated checkout.

Baseline: `f2aa79db1a8c24045445623c42930ebc09cc0527` (0.38, including the passing
GC-test correction). Apply the 0.39 patch once. Do not reapply either 0.38 patch.
The delivered source bundle is not a complete checkout.

## Complete selected-interpreter run

From the repository root on macOS:

```bash
PATCH="downloads/skia-for-racket-0.39.0-offscreen-opengl-20260928.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The runner uses this exact executable for `-l raco -- make`, ordinary CPU/native
RackUnit tests, all dynamically loaded test modules and the live diagnostics.
Python is selected by `PYTHON` in the shell/PowerShell entry point. A C11 compiler
is required for the existing ABI mirrors (including the GPU mirror); set `CC`
when necessary. CPU native assets must already be installed. On Windows use
`tools/install-native-windows.ps1` and `tools/validate-gpu.ps1`; a supported
Racket GUI installation and working desktop GL driver are also required.

One fresh `output/gpu-0.39-*/` directory receives all results. The sequence is:

1. Existing source/installer checks, the GPU source checker, 12 Windows-installer
   synthetic tests, 20 foundation-inspector tests and 34 offscreen/window
   inspector tests, then ten existing host-C ABI mirrors.
2. Compilation of all ordinary/GPU suites, scene registry and tools; CPU symbol
   checks and doctors; the complete ordinary regression runner, including the
   original 64 GPU-foundation pure cases and 35 new GPU-surface pure cases.
3. The existing three-cycle OpenGL foundation probe, plus the Metal construction
   probe on macOS. These remain distinct from the new surface tests.
4. `gpu-offscreen-doctor.rkt`: a separate 33-source-case live GPU suite with two
   native GL domains, followed by eight direct CPU/GPU scene pairs and a detached
   image check after both contexts are closed. Then actual PNG/trace inspection.
5. `gpu-window-doctor.rkt`: three resizes, GPU draw/blit/submit/swap, native format
   and size queries, expiration and release checks. Then window-trace inspection.
6. `SOURCE-SHA256SUMS.txt` regeneration, last, after every selected step succeeds.

Source-case counts are checked structure, not new execution claims. Inspector
self-tests exercise synthetic inputs and are not Racket/GPU tests. The ordinary
CPU symbol requirements remain 392 Skia / 27 HarfBuzz. Surface/window callouts
have a separate nine-entry inventory, reusing existing record layouts.

`GPU_MODE=required` is the default; unavailable selected GPU checks fail.
`GPU_MODE=optional` permits explicitly diagnosed initialization unavailability,
not rendering/comparison/cleanup failures. `GPU_MODE=off` skips live GPU work
explicitly but still compiles the relevant source and runs pure/CPU tests.
`REQUIRE_HARDWARE=1` additionally rejects software or unclassified GL renderer
strings; it is a driver-string requirement, not independent hardware attestation.
`SKIP_C_ABI=1` records an explicit incomplete ABI check. Every skip is retained in
the overall report and must not be described as a complete GPU acceptance run.

## Review artifacts

The foundation probes retain `opengl.*` and `metal.*` artifacts.
The new offscreen prefix is `offscreen`:

- `offscreen.diagnostic.json`: actual context snapshots, native suite failure
  count, per-scene GPU target data and transfer events, both context teardowns.
- `offscreen.{paths,gradients,images,filters,runtime,text,mesh,perspective}.{cpu,gpu}.png`:
  sixteen 420 x 260 images, directly rendered on their respective targets.
- `offscreen.detached.png`: exact 8 x 8 CPU image used after GPU teardown.
- `offscreen.inspection.json` and `offscreen.review.html`: validated numerical
  metrics and side-by-side CPU/GPU images. They publish only after inspection passes.

The window prefix is `window`; it produces diagnostic/inspection JSON and review
HTML, but deliberately no per-frame CPU screenshot. Inspection JSON reports
`visible_pixels_verified: false` and `manual_review_required: true`.
The overall `validation.json` records commands, return codes and skips. These
elapsed command times are not a GPU-completion benchmark.

## Pixel comparison contract

The four solid corner markers and two transparent-margin pixels must match
exactly. Each scene comparison uses the content rectangle x=24..395, y=52..233;
large blank margins cannot dilute the result. It checks mean absolute channel
error, the fraction of pixels with any channel error above 24, and foreground
area ratio (0.8..1.2, with at least 50 CPU foreground pixels).

| Scene | Mean absolute channel error, maximum | Fraction with error >24, maximum |
|---|---:|---:|
| paths | 2.5 | 0.04 |
| gradients | 1.2 | 0.015 |
| images | 1.5 | 0.02 |
| filters | 3.0 | 0.06 |
| runtime | 2.0 | 0.03 |
| text | 3.0 | 0.075 |
| mesh | 2.5 | 0.05 |
| perspective | 3.0 | 0.06 |

These are explicit initial acceptance bounds, not tolerances calibrated from a
0.39 hardware run. A mismatch fails and prints measured errors; inspect the
artifacts before changing a threshold. Do not simply widen bounds to pass.
Sampling, antialiasing, shader precision and text rasterization can differ by
backend, so universal CPU/GL/Metal byte identity is not demanded.

The same scene callback runs directly on each target, with independently created
CPU resources. A CPU PNG is neither a GPU screenshot nor a PDF/SVG rasterization.
The trace requires exactly one explicit completed readback per GPU scene, and
no CPU group intermediates. This does not certify every internal Skia algorithm
or every untested feature combination.

## Manual window check

After the automated run, inspect the actual onscreen frame and resizing:

```bash
"$RACKET" tools/gpu-window-doctor.rkt --interactive \
  --prefix output/gpu-window-0.39-manual
```

Check red/green upper corners, blue/yellow lower corners, the unmirrored scene,
correct aspect/scale after resizing, and the difference between logical and GL
pixel sizes on Retina/HiDPI displays. Close the window to finish; inspect the
resulting diagnostic. The tool requires at least three nonzero-sized frames.
It is not a finalized presenter API or a full minimized/multiwindow lifecycle
stress test. Metal window drawing and GPU images are still later work.

Linux starts with Racket GLX/X11 or XWayland, not true headless EGL/native Wayland.
Advertise only configurations actually run. The author's synthetic/C checks and
the preceding maintainer's 0.38 Apple Silicon pass do not establish Linux,
Windows, new 0.39 Mac rendering or visible presentation correctness.
