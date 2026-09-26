# Applying and validating 0.24

Apply to `soegaard/skia-for-racket` at
`36b4b44dae46e30bb07dcdb569a254c8fdd4d982` (shared vector output).
The previous PDF, SVG, output-page/text-policy, codec, and ICC implementations
are retained. The new geometry implementation is a separate module with a
small private core bridge, rather than another large insertion into core.rkt.

## Run from the repository root

```bash
PATCH="downloads/skia-for-racket-0.24.0-path-matrix-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-path-matrix.sh
```

The script runs static checks, eight synthetic inspector tests, codec/PDF/matrix
C layout mirrors, both native symbol audits, compilation, doctor, every source
suite, and the one combined visual runner. It then inspects the actual SVGs and
regenerates `SOURCE-SHA256SUMS.txt`. It fails at the first unsuccessful command.

Compilation uses the same selected interpreter as execution:

```bash
"$RACKET" -l raco -- make \
  main.rkt matrix.rkt output.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt \
  tests/*.rkt examples/path-matrix.rkt
```

This explicitly includes dynamically loaded native test suites. It does not
rely on `raco make run-tests.rkt` discovering dynamic dependencies, does not use
a separate PATH-selected raco, and does not delete compiled directories. The
script prints the selected interpreter, version, VM, and platform first.

Expected native symbol counts: **265 Skia**, **27 HarfBuzz**, zero missing.
New matrix layouts: **M33=36**, **M44=64**, M44 translation offsets **48,52**.
These are expectations for the live host run, not a claimed completed run.

The full runner has **398 cases**: 136 pure, 6 lifetime, 256 native. The new
suites add **24 pure + 30 native** cases. `--pure` runs 142 pure/lifetime cases.
Native checks cover independent ABI readback, canvas get/set/concat and clips,
PDF/SVG canvas expiry, path/contour snapshots, closure, conics, reconstruction,
measure frames and source lifetime, shader retention, and bounded snapshots.

## Visual artifacts

Open `output/path-matrix-0.24.review.html` in a browser and the actual
`output/path-matrix-0.24.pdf` in a PDF viewer. All three pages are 720 x 500 pt.
The first two SVGs should be completely vector, including outlined labels.

- `inspection`: original and raw-rebuilt geometry overlay, control points,
  closed versus open contours, and generated closing-line counts.
- `frames`: nine copies of one arrow, whose origins lie on a cubic curve and
  whose x-axes follow its sampled tangents.
- `shaders`: two matching filled shapes (canvas versus path transform), then
  three fixed rectangles with different local shader coordinates. Only the
  shader panel is explicitly rasterized, as one 1220 x 212 PNG.

The `.reference.png` files are separate raster drawings from the same callbacks,
NOT rasterizations of the generated vector files. The HTML makes that distinction.

The standard-library inspector runs as part of the script. Optional actual PDF
page-size/text inspection requires pypdf:

```bash
python3 tools/inspect-path-matrix.py \
  --probe-prefix output/path-matrix-0.24 --pdf
```

The inspector reports structure, not visual equivalence. Actual font appearance,
curve alignment, clipping, and gradient behavior still need the viewer comparison.

## Authoring verification boundary

The authoring environment had no Racket executable or pinned Skia libraries.
The attempted complete checkout download also failed. Verification here consists
of new-file and changed-context source checks, explicit export/documentation
checks, test-case structure/count checks, C mirror compilation/execution, eight
passing synthetic inspector tests, and patch application/reversal against
fetched source contexts. Complete copies of main.rkt, run-tests.rkt and info.rkt
were checked against their Git blob hashes. This is not a full-checkout test,
Racket compilation, native rendering, or a new Unicode conformance result.

Nothing is pushed to GitHub. The patch does not contain native libraries, font
files, generated .zo files, or a fabricated probe output. The source checksum
manifest is regenerated from the actual patched checkout after the host run.
