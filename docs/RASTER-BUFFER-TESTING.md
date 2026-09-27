# Raster-buffer validation

Baseline: `b4a4439523be263a77f127c6c661c5cd92d2ff24` (0.36, CPU color filters,
including the all-omitted ARGB identity fix). Apply the 0.37 patch once.

```bash
PATCH="downloads/skia-for-racket-0.37.0-raster-buffers-20260927.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-raster-buffers.sh
```

The validator uses the exact selected Racket executable for `-l raco -- make`,
all tests (including every dynamically loaded `tests/*.rkt`), all selected
doctors, and the combined visual probe. It runs nine existing host-C ABI
mirrors. The symbol audits should report **392 Skia / 27 HarfBuzz** bindings.
No new native record layout is added.

The stage adds **33 pure + 40 native** RackUnit cases. The expected cumulative
suite is **1,349 tests**; `run-tests.rkt --pure` includes **600** pure/lifetime
cases. These counts do not represent assertions or Python inspector tests.
The inspector contains **22 synthetic self-tests** (two require optional pypdf).

## Review artifacts

Open `output/raster-buffers-0.37.review.html` and its linked PDF. The combined
runner writes three PDF pages, three SVGs, three raster references, six separate
source snapshot PNGs, four export audits, group decisions, actual native memory
samples, and an inspection JSON report. No source sums are updated until all
selected checks succeed. The inspection report is published only on success.

| Page | Visual check | Primary image placements in each format |
|---|---|---|
| `stride` | Original striped RGBA buffer versus a filled 80 x 48 subset; alpha strip remains visible. | Two 160 x 96 images. |
| `canvas` | Direct canvas card versus a later small pixmap edit of the same storage. | Two 160 x 96 images. |
| `snapshots` | Unchanged old snapshot versus modified pixels scaled into a distinct larger buffer. | One 160 x 96 and one 320 x 192 image. |

All six output groups should choose native replay. There should be **zero
`draw-rasterized` events**, no new 600 x 360 panel fallback, and no whole-page
raster image. Source images themselves remain raster content. Labels and
checkerboards stay outside the images as ordinary document drawing.

The references are independent raster placements of the **same snapshot
inputs**, not PDF/SVG rasterizations and not a second implementation of buffer
semantics. Native tests and `.samples.json` check stride, zero padding, forbidden
access, buffer/source independence, snapshot independence, and premultiplication.
The structural inspector checks dimensions, drawn resource references, audited
native decisions, and exact memory samples. It does not assert visual equality.

PDF inspection uses pypdf when installed in the selected Python environment.
`CHECK_PDF=1` makes it mandatory; `CHECK_PDF=0` skips it explicitly. The default
`auto` reports a skip instead of claiming a PDF check. PDF traversal follows Form
XObjects and counts executed image draws, not soft masks or just definitions.

## Authoring-environment status

No Racket compiler or libSkiaSharp execution was available in the authoring
container. Compilation, RackUnit, doctor, and native rendering must be run on the
host. Python inspector self-tests, static source/test structure checks, and the
host-C mirrors were run here. See the delivered validation JSON for exact patch
checks and the distinction between whole-file and affected-context verification.
