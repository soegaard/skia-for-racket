# SVG output: application and validation

## Baseline and status

This change is based on the pushed PDF-output commit
`246f70cd80e26bc5d8da126e86ff7e520225a5f7` (0.21.0). The maintainer reported the
PDF tests passing and supplied the three-page PDF and raster references. The
existing PDF, color/ICC, and codec implementations are retained.

The new stage adds **16 pure and 27 native cases**. Expected totals are
**92 pure + 6 lifetime + 197 native = 295 source test cases**. `--pure` runs
98 cases. There are **249 required Skia symbols**, **27 HarfBuzz symbols**, and
**no new native struct layouts**. SVG adds only:

```text
sk_svgcanvas_create_with_stream
sk_canvas_destroy
```

**Authoring verification:** delimiter/string and source-structure review of
new/changed code, export/documentation checks for the additions, Python
inspector compilation and six synthetic inspector self-tests, and patch
application/reversal against fetched source contexts. This was not a complete
repository checkout validation. Racket compilation, native symbol audits,
Racket tests/doctor, and native SVG generation/rendering have NOT been run in
the authoring environment. Synthetic XML tests validate the inspector, not the
Skia SVG backend or the Racket XML finalizer.

## Apply and run

Run from the existing repository root, with the downloaded patch in `downloads`:

```bash
PATCH="downloads/skia-for-racket-0.22.0-svg-output-20260926.patch"

RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&

python3 tools/static-check.py &&
python3 tools/inspect-svg-output.py --self-test &&

cc -std=c11 -Wall -Wextra -pedantic \
  tools/check-codec-abi.c -o /tmp/skia-codec-abi-check &&
/tmp/skia-codec-abi-check &&
cc -std=c11 -Wall -Wextra -pedantic \
  tools/check-pdf-abi.c -o /tmp/skia-pdf-abi-check &&
/tmp/skia-pdf-abi-check &&

bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&

"$RACO" make \
  main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt \
  tests/svg-pure-test.rkt tests/svg-native-test.rkt \
  examples/svg-documents.rkt &&

"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&

mkdir -p output &&
"$RACKET" examples/svg-documents.rkt output/svg-documents-0.22 &&
python3 tools/inspect-svg-output.py --probe-prefix output/svg-documents-0.22 &&
python3 tools/update-source-sums.py
```

Expected individual Racket suite sizes, in runner order:

```text
54   original pure
6    lifetime
10   codec pure
12   PDF pure
16   SVG pure
132  original native
17   codec native
21   PDF native
27   SVG native
```

The output inspector uses Python's standard library only. Its `--self-test`
mode is synthetic and can run before native generation. `--probe-prefix`
parses the actual generated files and applies stronger probe-specific checks.

## Visual review

Open `output/svg-documents-0.22.review.html` in a browser. It displays the
browser-rendered SVG next to the separately drawn raster reference for each
of the three probes. The `.reference.png` files are NOT SVG rasterizations.
No image in the authoring report substitutes for native SVG output.

| Suffix | Logical size | Required structural properties |
| --- | --- | --- |
| `.vectors.svg` | 720 × 520 | Paths, linear gradient, intersect clip; no embedded image or native text. Labels are outlines. |
| `.text-images.svg` | 800 × 540 | Native text and outlined glyph paths, one embedded image, recorded vector picture replay. |
| `.effects.svg` | 720 × 480 | Two explicit raster groups (610 × 440 pixels each); remaining paths/labels are vectors. |

Check the vector curve, clipping edges, gradient direction, rotated geometry,
native text spacing, outlined shaping, image transparency, picture sizes,
shadow/blur boundaries, and dashed path. Native SVG text depends on the
viewer’s fonts; the outline sample is intended to remove that dependency for
its glyph geometry. Zoom into each actual SVG, not just its reference PNG.

The structural inspector reports resource references, font-family declarations,
text samples, and embedded image format/dimensions. A structurally valid SVG
can still differ visually from the raster backend, especially for unsupported
operations. See the compatibility table in [the SVG guide](SVG-OUTPUT.md).

## Regression boundaries

The ordinary runner includes all PDF and codec suites. The full Unicode
conformance run is separate and can be repeated with:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket" \
  bash tools/run-unicode-conformance.sh
```

No new conformance total, leak-measurement result, benchmark, GPU result, or
cross-platform renderer-equivalence result is claimed for this stage.
`SOURCE-SHA256SUMS.txt` is intentionally not patched: the final command
regenerates it from the complete local checkout.
