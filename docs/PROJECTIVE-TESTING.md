# Validating perspective and general matrices

Baseline: `85f8292a5925cc14bad880675385e7d9c5a75067`, including the tested
0.31 SVG region-seam correction. This is 0.32.0; apply it to that baseline,
not to the original uncorrected 0.31 patch.

## Apply and validate

```bash
PATCH="downloads/skia-for-racket-0.32.0-projective-matrices-20260927.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-projective-matrices.sh
```

The validator runs the source checks, inspector self-tests, eight host C mirrors,
existing native symbol audits, compilation, doctor, the full suite, and one
combined visual registry. Compilation and every Racket execution use the same
selected interpreter. In particular `tests/*.rkt` are compiled explicitly;
dynamically loaded suites cannot silently reuse another Racket's compiled files.
Source sums are updated only after the preceding checks succeed.

**Expected tests: 971** (418 pure + 6 lifetime + 547 native).
The new suites contain **59 pure and 36 native** cases. `--pure` runs 424.
Native requirements remain **367 Skia / 27 HarfBuzz**; no native library upgrade
or additional symbol is required.

The matrix-only pure suite is independent of `main.rkt` and can be run without
loading the native libraries:

```bash
"$RACKET" -l raco -- test tests/projective-pure-test.rkt
```

Authoring validation does not substitute for the selected Racket/native run.
In this authoring environment Racket and the pinned native libraries were not
available: no claim of Racket compilation or native rendering is made. Source
structure, modified-source hashes/patch contexts, Python inspector tests, and
host C mirrors are separate checks. The delivery validation record states
exactly which checks ran.

## Native tests and doctor

Tests cover row/column packing, old translate/skew calls independently validating
readback, preservation of all sixteen coefficients, projected raster coverage,
retained depth across concatenation, affine compatibility, matrix/clip restoration,
multiple values, protected save floors, bad input, overflow rejection, detached
snapshots, cross-thread rejection, and expired surface/document canvases.

Both PDF and SVG tests cover preflight, rejection before the offending transform,
canonical affine vector-only output, explicit fallback, and picture provenance.
A general matrix outside a subsequent raster group is still reported as needing
fallback. State scopes retain the page lifetime guards.

Expected doctor line:

```text
General matrices passed: row/column ABI, retained depth, homogeneous divide, scoped restore, explicit PDF/SVG fallback; M44=64
```

## Review artifacts

Open `output/projective-matrices-0.32.review.html` and the actual PDF alongside it.
The left images are actual SVG files. The right images are independent 1440 x 1000
raster drawings, not renderings of the PDF/SVG. Each explicit embedded panel is
600 x 360 pixels; labels and checkerboards remain vectors.

| Page | Main checks | Embedded panels in each document format |
|---|---|---:|
| `.homography.svg` | Affine vector grid versus a projective grid; projective divide. | 1 |
| `.depth.svg` | Same image tilted in opposite directions; retained Z until projection. | 2 |
| `.scope.svg` | Full matrix restoration after an exception; fixed clip under a later transform. | 2 |

The PDF has three 720 x 500 point pages. The page headings should remain
extractable native PDF text. The SVG labels should be outlines. The first page's
affine panel must remain vector geometry, not be included in the raster group.

The runner writes four export audit reports, eighteen full matrix traces in
`.matrices.json` (six per backend), and two intentionally blocking **preflight
reports** in `.unsafe.audit.json`. It does not create an unsafe SVG or PDF.
The structural inspector checks matrix multiplication order, finite snapshots,
physical page sizes, embedded PNG sizes/CRC, vector labels, fallback provenance,
and preflight behavior. It does not certify visual equivalence.

With `pypdf` installed, also inspect the actual PDF's media boxes, native heading
extraction, and embedded image dimensions:

```bash
python3 tools/inspect-projective-matrices.py \
  --probe-prefix output/projective-matrices-0.32 --pdf
```

For visual diagnosis, compare the actual exports at multiple zoom levels. The
intended projection changes the geometry, not merely a readback matrix. The
projected panels are finite-resolution images by policy, not infinitely sharp
vector surfaces. There is no new PDF/SVG rasterization library in this stage.
