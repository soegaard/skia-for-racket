# GPU document-output validation

Implementation baseline: `f493314201d69973956c3e5485fda0b709dcad67` (0.43).
The maintainer accepted the macOS baseline and explicitly deferred Linux EGL
end-to-end validation to future GitHub Actions CI. That gate is not a blocker
for this revision and is not claimed to have passed.

## Run on the host

From the repository root, after applying the patch:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The runner uses the selected Racket for compilation and execution, retains the
CPU/offscreen/image/presentation/interop regression sequence, and then executes
`tools/gpu-output-doctor.rkt` for OpenGL and Metal on macOS, OpenGL elsewhere.
`GPU_MODE=required` is the default. Optional initial absence is explicitly
reported; a test/render/readback/inspection failure cannot become a skip. `off`
runs the CPU/pure checks without a document-GPU success claim.

All results are written into a new `output/gpu-0.44-*/` directory.
`SOURCE-SHA256SUMS.txt` is regenerated **last**, only after every selected check
succeeds. No hashes are generated from a source-only delivery bundle.

The source inventory adds **35 pure cases** and **42 live cases per selected
backend**. The pure tests cover lazy acquisition/closure, explicit absence,
thread/scope expiration, execution reports, and exact-target audit authority.
The live tests cover geometry, DPI/padding, CPU/GPU pixel checks, color-space
conversion, transparent/source compositing, nested inheritance and overrides,
foreign context/recorder rejection, errors before destination commit, strict
policy vetoes, and retained-resource cleanup. Source counts are not evidence of
an executed Racket suite.

## Actual document artifacts

For each backend, the doctor constructs **16 documents**: four fixtures, two
execution variants (CPU/GPU), and two formats (PDF/SVG). All documents remain
open until **both test GPU contexts have closed**; only then do they finish and
serialize their retained CPU-image references.

| Fixture | Purpose |
|---|---|
| `pattern` | Independent exact semitransparent/colored-marker expected pixels. |
| `effects` | Runtime SkSL and a padded drop shadow, with vector heading/rule/border outside. |
| `perspective` | Projective drawing inside a bounded fallback, not on the document matrix. |
| `nested` | Raster child inheriting the executor while the outer picture remains native. |

Every embedded raster is **210 × 144 pixels**, covering 140 × 96 logical units
on a **240 × 180-point** page, starting at **(32,44)** in top-left coordinates.
An external hyperlink remains document metadata outside the raster.

Inspect:

```
output-opengl.review.html
output-metal.review.html
output-opengl.inspection.json
output-metal.inspection.json
```

The HTML includes PNG pixels decoded from the actual SVG files, plus links to
both PDF and SVG documents. Open those links and review placement, transparency,
shadow padding, vector surroundings and hyperlink behavior. This is separate
from the already accepted interactive window checks; the document stage does
not change the presenter.

The standard-library inspector checks raw diagnostic JSON, not another
inspector's success flag. It verifies exact native coverage, selected context,
GPU surface backing, explicit completed readbacks, independent teardown and
single-invocation authoring. The `execute-output-group` audit must describe an
actual transfer, not just a plan. CPU references must perform no GPU IO.

For **SVG**, it parses the actual XML, checks vector shapes and hyperlinks,
resolves the used embedded image and affine transforms, verifies placement,
and decodes its PNG including CRC/filter checks. The independent pattern is
exact. Effects and perspective use explicit premultiplied-RGBA comparisons in
the content region: mean channel error at most 3, fraction of pixels with any
channel error over 24 at most 0.06. Orientation and clear-corner markers remain
exact. These are acceptance tolerances, not universal CPU/GPU byte identity.

For **PDF**, a bounded parser follows the actual plain cross-reference table,
page tree, referenced content streams and image/form resources. It checks page
size, a single invoked image of the expected pixel dimensions, matching alpha
mask size, effective placement, vector path operators and the live URL
annotation. It rejects unexpected encrypted/incremental/xref-stream formats.
This is intentionally a reader for the pinned diagnostic output, **not a general
PDF parser**. It does not render PDF pixels or certify PDF/A, font embedding or
ICC conformance. PDF visual inspection remains part of artifact review.

Inspection HTML/JSON are published only after all checks pass; failed
reinspection removes old success reports. PNG comparisons cannot establish a
speedup, and no performance result is produced by this stage.

## Future Linux CI

The existing Linux runner has the new document gate wired in using the same EGL
configuration and no display variables:

```bash
RACKET="/path/to/racket" bash tools/validate-gpu-headless.sh
```

It creates `output/gpu-0.44-headless-*/output-egl.review.html` after the existing
EGL/surface/image/interop checks. No GUI host or presenter is introduced.
Execution remains deferred to future CI, as agreed for the 0.43 baseline.

## Authoring checks versus host results

`tools/inspect-gpu-output.py --self-test` uses synthetic PDF/SVG/PNG fixtures.
`tools/test-validate-gpu-output.py` mocks child processes. Neither executes
Racket, Skia, EGL, Metal, or OpenGL. The source checker checks delimiters and
suite structure, not Racket expansion. Consult the delivery's authoring report
for executed checks and limitations; previous-stage host passes do not certify
new document functionality.
