# Unified presentation validation

Baseline: `07db8f0356e2bb508e06a119adf7f19c9396f80e` (0.41). The maintainer's
macOS/aarch64 run of 0.41 passed CPU regression, the shared OpenGL/Metal suites,
Metal lifecycle, explicit two-way transfers, and all ten parity comparisons.
The corrected abandonment test is preserved. Those are preceding results,
not a new 0.42 execution or Metal window-pixel certification.

## Complete run

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The selected interpreter compiles every dynamic test/adapter/doctor/example,
including `gpu-gui.rkt`, and runs all prior CPU/foundation/offscreen/image/
Metal-lifecycle/cross-backend/parity checks. It then runs the new presentation
suite on OpenGL and, on macOS, Metal. `GPU_MODE=required` is the default.
`optional` permits explicit initial unavailability only; native test,
submission, cleanup and inspection failures still fail. `off` skips live GPU
work explicitly and cannot establish a presentation pass.

The ordinary test runner includes 53 presenter pure source cases. They test
frame expiry, zero/hidden extents, resize/scale generations, queued redraw
coalescing, callback escapes/exceptions, cleanup deferral across ordinary GPU
scopes and other windows, GC/custodian requests, same-queue borrowed registry,
and safe exceptional cleanup/quarantine. They use mock adapters, not a GUI.

The separate live suite contains 28 source cases per selected backend. It
checks real widget/context creation, ordinary canvas drawing, target geometry,
borrowed frame/canvas expiration, resize, hidden and minimized windows,
callback-time resize and close, wrong-thread/nested access, redrawing,
unbalanced saves, application-child close guards, and independent windows.
Source-case counts are checked against the doctor and inspector constants;
counts alone do not establish that RackUnit was run.

The presentation doctor then keeps two windows alive with distinct contexts,
renders three different framebuffer sizes in each, closes the first and
continues rendering the second, and checks target/context teardown. Each
normal frame's explicit I/O trace must be flush -> asynchronous submit ->
presentation request, with no frame readback or explicit CPU wait. Metal
frames use actual CAMetalDrawable textures, not the headless offscreen probe.

## Results

Each run writes to a fresh `output/gpu-0.42-*/` directory. New files are:

| Prefix/file | Evidence |
|---|---|
| `presentation-opengl.*` | GL presenter diagnostics, checked submission/ownership JSON and review HTML. |
| `presentation-metal.*` | Corresponding Metal presenter evidence on macOS. |
| `presentation.inspection.json` | Combined submission checks, only when all selected presenters passed and run/host identities agree. |
| `presentation.review.html` | Submission/lifetime report and visible-window review instructions. It contains no screenshot certification. |
| `parity.review.html` | Existing CPU/OpenGL/Metal offscreen and image comparisons, rerun in this invocation. |
| `validation.json` | Every selected command result, skips, separate rendering/parity/submission flags, and manual-review limitations. |

Success inspections are written atomically; failed reinspection removes stale
success outputs. No inspector treats a skipped/cancelled frame as submitted,
a queued CPU wait as normal asynchronous presentation, or a pending/quarantined
release as clean teardown. Source sums are regenerated **last**, after every
selected automatic check succeeds. A failing run writes `validation.failed.json`
and does not update `SOURCE-SHA256SUMS.txt` early.

The JSON field `presentation_submission_verified` is indexed by backend.
`presentation_summary_verified` means the combined native reports passed.
`visible_window_pixels_verified` and `metal_presentation_verified` remain false:
the automated run has not sampled what appeared on a physical display. This
is deliberately separate from successful native presentation submission.

## Required manual review

```bash
"$RACKET" examples/gpu-presenters.rkt --backend both
```

On Linux/Windows use `--backend opengl`. On macOS both windows use exactly the
same drawing callback. Check top-left red, top-right green, bottom-left blue,
and bottom-right yellow; perspective content and label orientation; resizing;
minimize/restore; moving between Retina/non-Retina displays when available;
and closing one window while the other remains responsive. Repeat with
`--backend auto` to check selection policy. Close windows normally to exercise
owner-side cleanup. Record the platform, device, native version and checks
actually performed rather than treating the JSON's false visible-pixel flag
as a rendering failure or silently changing it to true.

A visible-image problem is not fixed by loosening the inspector or adding a
normal frame readback. Inspect actual layer bounds/backing conversion, native
origin, color format/tag, submission order and drawable lifetime.

## ABI and authoring checks

`tools/check-presentation-abi.c` checks actual Core Graphics/Objective-C SDK
geometry and BOOL declarations on macOS. Elsewhere it explicitly reports local
mirrors only. The Metal adapter accepts 64-bit macOS; CGRect-returning method
IMPs are called with the ordinary C ABI so x86_64 structure-return conventions
are not guessed from objc_msgSend. Local mirror success is not execution of
Objective-C or a verification of a driver.

```bash
python3 tools/inspect-gpu-presentation.py --self-test
python3 tools/test-validate-gpu-images.py
python3 tools/test-patch-delivery.py
python3 tools/check-gpu-source.py --require-integration
```

These Python checks and C mirrors are not Racket compilation or native GPU
execution. The authoring delivery uses complete modified files verified against
pinned Git blob hashes plus exact fetched contexts for larger documentation;
it is not a full repository checkout. Its report records the exact check scope.
The emitted patch is Git-generated and must pass ordinary forward/reverse
`git apply --check`, hunk-count/context checks, and byte comparisons without
`--unidiff-zero`, `--recount`, or assumptions about a dirty user checkout.

No new platform-support, throughput, low-latency, physically displayed pixels,
or universal CPU/OpenGL/Metal byte-identity claim follows from authoring checks.
Nil drawables are explicit skips; acquisition can block. Aborted Metal frames
may wait for completion for safe cleanup, unlike normal submitted frames.
