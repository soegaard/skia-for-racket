# EGL and external GL validation

Implementation baseline: `e5f93e529fd875661a0b0019d5b9d897ff8c9dc0` (0.42).
The maintainer's 0.42 automated and interactive checks passed on macOS/aarch64.
That acceptance does not establish a new EGL or external-storage pass.

## Two deliberately separate runners

The existing desktop runner retains CPU, OpenGL, Metal, lifecycle, parity, and
presentation checks. It now also exercises external GL borrowing/copy through
the existing native GUI GL host, then inspects the resulting PNGs and ledger.
On macOS:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket" bash tools/validate-gpu.sh
```

All artifacts go to a fresh `output/gpu-0.43-*/`. The new report is
`interop-opengl.review.html`; the existing presentation and parity reports
remain separate. This runner explicitly records EGL headless validation as
**not selected**, even on a Linux desktop.

For actual display-server-free validation, use the Linux-only runner with a
matching Racket and pinned native Skia/HarfBuzz installation:

```bash
RACKET="/path/to/racket" bash tools/validate-gpu-headless.sh
```

The runner removes `DISPLAY`, `WAYLAND_DISPLAY`, and `MIR_SOCKET` from **all**
child environments. It neither creates a window nor invokes a GUI presenter.
The exact selected Racket compiles all its dynamic EGL/interop modules and
executes the CPU regressions, pure tests, and live probes. A fresh directory
`output/gpu-0.43-headless-*/` carries one shared validation-run identity.

Configuration is explicit and propagated to every headless probe:

```bash
RACKET="/path/to/racket" \
SKIA_EGL_PLATFORM=device SKIA_EGL_DEVICE_INDEX=0 SKIA_EGL_SURFACE=pbuffer \
  bash tools/validate-gpu-headless.sh
```

Defaults are `surfaceless`, index zero, and `surfaceless` surface. A missing
requested extension/device/configuration does not try a different platform or
hidden window. `REQUIRE_HARDWARE=1` rejects software/unclassified renderer
strings. Without it, a correctly labelled software GL run is valid execution
evidence for that software configuration, not evidence of hardware acceleration.
No timing or speedup conclusion follows from these checks.

Both runners support `GPU_MODE=required` (default), `optional`, and `off`.
Optional headless mode can skip an unavailable **initial** EGL/Ganesh lifecycle
probe. Once that probe succeeds, all subsequent surface/image/interop failures
fail the run; they cannot become availability skips. An off run executes CPU
and pure checks and explicitly leaves live headless/interop gates unverified.
`SKIP_C_ABI=1` is an explicit incomplete-ABI choice, not a silent skip.

## New source cases and executed workflows

The added pure suite has 37 RackUnit source cases covering option validation,
provider binding/restoration, ownership, failure paths, child guards, and
external-GL exclusion. Ten EGL-native source cases exercise actual binding/API
restoration, independent-context display lifetime, owned/borrowed provider
rules, and Ganesh reuse. Thirty-two external-GL source cases exercise the FBO and
texture boundary, both origins, source mutation/deletion, retained content,
wrong-context/unsupported storage, exceptions, state transitions and cleanup.
Source counts are not Racket execution claims.

The headless runner performs three fresh native EGL/Ganesh render/readback/
teardown cycles, then runs the unchanged 33-case surface suite and eight
shared drawing scenes, the unchanged 42-case image suite and two retained-graph
workflows, and the new external GL suite/workflow. CPU detachment/encoding after
context teardown is checked separately from GPU rendering.

The interoperability workflow creates host-owned RGBA8 texture/FBO/stencil
objects. It makes an owned GPU copy, renders blue into the actual borrowed host
framebuffer, verifies host names survive, deletes the external source, and
checks the independent copy's original asymmetric pixels. Three small PNGs
show the original host pixels, the changed host framebuffer, and the surviving
copy. Explicit validation readbacks are outside the resident-operation ledger.
The ledger must contain no hidden readback or adoption. The two default
external-return completion waits are intentional; they are not presenter-frame
waits and are not reported as zero-wait interop.

`inspect-gpu-headless.py` validates raw JSON and actual decoded PNG samples.
The combined gate re-runs the existing surface and image inspectors rather than
trusting saved `inspection.json` success flags. It requires a single run,
architecture, Racket identity, EGL configuration and renderer, genuine EGL
procedure-table contexts, matching Ganesh backend/context IDs, correct coverage,
exact smoke pixels, and closed domains with no outstanding wrapper/release
counts. Existing scene tolerances are not widened.

The combined report is `headless.review.html`, with `egl-lifecycle.*`,
`offscreen-egl.*`, `images-egl.*`, and `interop-egl.*` below the same directory.
Review the ten drawing/workflow comparisons for unexpected raster differences.
No window pixels are generated or certified by this gate.

## Authoring evidence versus host acceptance

The delivery's authoring report separates Python synthetic tests, source
structure, pinned-file verification and patch application from real execution.
The authoring environment can exercise native EGL/GL through Python ctypes:
its four surfaceless/device × surfaceless/pbuffer configurations ran on Mesa
llvmpipe with display variables absent, querying RGBA8/stencil8 attachments,
checking GL pixels, sibling context survival and API restoration. That probe
does **not** execute the Racket wrapper or Ganesh and is not the acceptance
result for this release. Hardware EGL drivers, Racket expansion/RackUnit, and
Mac/Windows external GL use still require actual host runs.

Patch delivery uses normal Git-generated hunks and forward/reverse application
checks, not relaxed context flags. `SOURCE-SHA256SUMS.txt` is regenerated only
as the final selected runner step. Preserve failed diagnostics rather than
replacing them with an old successful run's files.
