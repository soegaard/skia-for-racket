# GPU DC consumer acceptance (0.60)

Stage 0.60 exercises real Racket clients through the 0.59 GPU DC API. It does
not introduce a new renderer, a persistent GPU DC, a backend-selection facade,
a CPU fallback for GPU failures, or a performance promise. The native pins,
public canvas/DC ownership rules and existing CPU/PDF/SVG paths are unchanged.

The package version is 0.60. The GPU DC capability declaration continues to
identify its **0.59 contract**; it is not a copy of the package version.

## Workloads

`tests/gpu-dc-consumer-fixtures.rkt` reuses the existing CPU consumer fixtures:

| Workload | Actual operations | Independent acceptance probes |
| --- | --- | --- |
| `pict` | Public `draw-pict`, text, bitmap, transformed shapes and composite `cellophane` | Red rectangle, bitmap color, navy text and isolated-group overlap colors |
| `plot` | Public `plot/no-gui` `plot/dc`, a labeled function, points, title and legend | Four curve landmarks, two point landmarks, title/legend ink |
| `styles` | Existing gradient/stipple/hatch/style oracle, alpha group and HiDPI tile | Linear/radial direction, all four tile colors, HiDPI tile colors, hatch lines/gaps |
| `geometry` | Clipping, isolated alpha, overlapping copy, translation and nonuniform scale | Interior/exterior clip points, group opacity, immutable-copy colors and transformed geometry |

Each runs directly, as `record-dc%`'s recorded procedure, and as a recorded datum
that is **written, read, and decoded with `recorded-datum->procedure`**. There is
no private recording-format decoder. Direct `pict`/`plot` and all replay modes
must restore the destination state returned by the existing `consumer-state`
helper. Direct style/geometry sequences deliberately change drawing state and
make no restoration promise.

Upstream `record-dc%` does not record `copy`. The geometry fixture therefore
records its source rectangles, clipping, alpha and transforms, then performs
`copy` **directly on the destination after replay**, identically on every path.
It does not claim that a copy operation was serialized or replayed by Racket.

`pict` is constructed with a temporary CPU Skia metric DC and retained after
that DC closes. Direct plots use their destination's actual plot layout;
recorded plots use their recorder's layout. Plot probes use those layouts,
rather than assuming identical font metrics from different layout providers.

## Native matrix

Every workload/mode runs at these extents:

| Case | Physical pixels | Logical dimensions | Purpose |
| --- | --- | --- | --- |
| `1x` | 320 x 240 | 320 x 240 | Ordinary raster scale |
| `2x` | 640 x 480 | 320 x 240 | HiDPI geometry |
| `asymmetric` | 400 x 360 | 320 x 240 | Independent X/Y device scale |
| `fractional` | 641 x 481 | 320.5 x 240.25 | Fractional logical dimensions and unequal ratios |

Three paths are captured: ordinary CPU `skia-dc%`, a borrowed native GPU surface
via `call-with-gpu-surface-dc`, and a real native GPU final target reached via
`call-with-gpu-frame-dc` and the existing presenter state machine. The last
adapter substitutes **only window acquisition/presentation** with an offscreen
GPU target; the DC, staging surface, snapshot and final GPU-to-GPU draw are real.
Readback happens from that final target after the frame DC has expired.

There are **144 captures**: 4 workloads x 3 modes x 4 extents x 3 paths.
The CPU comparison uses its own initial matrix, not the GPU renderer adapter.
Its backing dimensions are physical; these particular consumers receive an
explicit 320 x 240 scene size. This is not a claim that the two classes expose
identical `get-size` semantics for arbitrary clients.

Every capture must independently pass its semantic probes. In addition, recorded
procedure/datum captures on the same path may differ by at most 2 per 8-bit
channel, and GPU borrowed-surface/final-frame captures by at most 3. This yields
96 bounded comparisons. **Full CPU/GPU byte equality is not required.**
Independent probes cannot certify every pixel of the style gallery; the review
captures remain available for visual inspection. No reference-Cairo pixel
identity, universal font parity or all-`dc<%>` compatibility claim is made.

Each of the 96 GPU capture DCs must expire. Drawing, state access and readback
through retained references must reject, and later callbacks must not revive
earlier DCs. The native context must close before the worker reports success.

## I/O accounting and GUI

Drawing and capture use separate `current-gpu-io-ledger` scopes. Drawing must
contain no wrapper `readback` event. Every intentional GPU capture must contain
exactly one, providing a positive control that the ledger is active. Final
frame paths must include a GPU snapshot. This audits wrapper transfers, not
unobservable operations inside the driver.

The GUI worker runs the 12 workload/mode pairs at two actual window sizes. Each
pair first gets a **complete normal frame with no capture**, including the
present request. That ledger must contain a GPU snapshot, exactly one
`present-request` and no readback. A separate inspection frame explicitly reads
the GPU DC backing. Both DCs expire before `refresh-now` returns.

The actual frame dimensions, independently in X and Y, determine probe pixel
coordinates. CPU references use the same measured dimensions. No fixed 1x or
Retina factor is assumed. The second size must be wider than the first.
Automatic repainting is disabled for these controlled frames; the selected
0.59 GUI suite still exercises the ordinary eventspace/lifecycle path first.

This produces **48 GUI-process captures**, 24 normal presentation ledgers and
24 separately accounted inspection transfers. Same-path procedure/datum
comparisons add 16 bounded comparisons. GUI captures describe the DC backing,
**not an independently read window back buffer or physical screen scanout**.
The offscreen native suite separately checks final GPU-copy target pixels.

## Running

Install the pinned native libraries first. Use one selected Racket consistently:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

python3 tools/update-source-sums.py --check
python3 tools/test-gpu-dc-consumers.py
"$RACKET" run-tests.rkt
python3 tools/validate-gpu-dc-consumers.py --racket "$RACKET" --require-gui
"$RACKET" examples/gpu-dc-consumers.rkt
```

The validator selects Metal on macOS, EGL/offscreen plus OpenGL/GUI on Linux,
and Direct3D on Windows. `--adapter warp` requires `--backend direct3d`.
Without `--require-gui`, GUI checks are explicitly **not run**, not reported as
passed. The native workers do not support `--backend opengl`; their OpenGL
path is the explicitly managed EGL context. The example supports `opengl`.

The validator always runs and checks the complete selected **0.59 baseline
validator** before the new workloads. There is no bypass flag. Missing backends,
missing displays for selected GUI checks, nonzero exits, timeouts, missing or
duplicated completion markers and incomplete matrices are fatal.

It uses a new evidence directory under `output/gpu-dc-consumers-0.60-*`, or a
new path supplied with `--directory`. Existing directories are not reused.
`--timeout` is a positive, finite per-command bound; the nested baseline driver
receives a bounded overall allowance for its multiple commands.

### Evidence

`validation.json` records runtime identity, source hashes, selected backends,
completed gates and command logs. `baseline/` retains the unchanged 0.59
validator's results. `native/` and, when selected, `gui/` contain:

* raw premultiplied `.rgba` captures and the worker's run-tagged JSON report;
* `inspection.json`, with SHA-256 hashes, independent probes and bounded comparisons;
* `.png` and `review.html`, generated only after all selected suite pixel checks pass.

PNG encoding converts premultiplied captures to straight alpha. The inspector
rejects duplicate JSON keys, non-finite coordinates, mismatched identities,
old run tokens, duplicate/missing cases, unsafe filenames, symlinked capture
files, wrong byte lengths, missing lifecycle checks, missing transfer controls
and implicit readbacks. Source-manifest checks and fingerprints run before
and after validation. These are same-run evidence checks, not cryptographic
attestation against a malicious process that forges both code and output.

## CI and scope

The existing **GPU DC** workflow runs the expanded validator under Linux
Mesa/Xvfb on Racket 8.18 and 9.3, retaining native and GUI evidence. An additional
Windows/Racket 9.3 job requires the native D3D12 WARP consumer matrix; it makes
no GUI claim. The ordinary source job also runs the Python inspector/runner
regressions. All selected gates fail closed.

The normal `CI required` aggregate and repository branch-protection settings
are unchanged. Both workflows must be checked when accepting this stage.
A workflow definition is not evidence that it has executed successfully.
Software-driver CI does not establish hardware performance, physical output,
or macOS Metal acceptance. Run the selected host gate for those backend
semantics, and inspect actual desktop output separately.
