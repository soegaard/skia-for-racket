# Applying and validating the advanced-filter stage

Apply the 0.25 patch to `soegaard/skia-for-racket` commit
`cd046ac6eb92d7c0534b70900a341b1014cd6fbe` (path inspection and matrix support).
The maintainer reported the 0.24 suite and probes green: 398 source cases,
265 Skia symbols, 27 HarfBuzz symbols. This patch preserves that implementation.

## Complete local sequence

```bash
PATCH="downloads/skia-for-racket-0.25.0-filter-graphs-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-filter-graphs.sh
```

The script uses the selected interpreter for both compilation and execution.
It prints the executable, version, VM, and architecture. Compilation explicitly
includes **all** `tests/*.rkt`, including dynamically loaded native suites:

```bash
"$RACKET" -l raco -- make \
  main.rkt matrix.rkt output.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt \
  tests/*.rkt examples/filter-graphs.rkt
```

No separate `raco` is selected through PATH. Compiled test directories are not
routinely removed. As in 0.24, this prevents the omitted-dynamic-suite build
problem seen with the stale 8.12 SVG test file.

Expected full suite: **472 cases** — 166 pure, 6 lifetime, 300 native.
New suites: **30 pure + 44 native**, including all new constructor families,
crop placement, identity optimizations, ordered inputs, copied kernels,
creator-thread checks, source/graph retention, PDF output and bounded SVG output.
`--pure` runs 172 pure/lifetime cases. Ten Python inspector self-tests are
separate from the Racket total.

Expected required symbols: **285 Skia / 27 HarfBuzz**, zero missing.
New C layouts: `sk_isize_t` 8, `sk_ipoint_t` 8, `sk_point3_t` 12 bytes.
The script retains the codec, PDF, and M33/M44 layout checks as well.
It runs the source checker, inspector self-tests, four C mirrors, both symbol
audits, compiler, doctor, complete test runner, example and SVG inspector, then
regenerates `SOURCE-SHA256SUMS.txt`. A failure stops the sequence.

## Visual review

Open `output/filter-graphs-0.25.review.html` and
`output/filter-graphs-0.25.pdf`. Each page is 720x560 points.

The registry has three pages, six panels per page:

| Page suffix | Panels |
|---|---|
| `.graphs` | Shadow/source merge, multiply, arithmetic average, crop-after-blur, crop-before-blur, and composition. |
| `.kernels` | Dilation, erosion, edge convolution, displacement, affine image transform, and magnifier. |
| `.sources` | Image, picture, shader, tile, distant diffuse light, and spot specular light. |

The PDF receives native filters. The SVGs use **six explicit 416x256 PNG groups
per page**, while checkerboards, borders, and labels remain vector. The
`.reference.png` files are independent native raster renders at 144 DPI, not
SVG/PDF rasterizations. The HTML labels make the distinction explicit.

Check crop-after's hard boundary against crop-before's outward blur, the merge
layer order, morphological size changes, matrix-transform geometry, and
lighting at the soft alpha edges. Inspect the actual PDF as well as the PNGs:
native PDF filtering can choose different internal rasterization paths.

The standard-library inspector validates SVG page sizes, outlined text,
resource references, image counts/dimensions and PNG chunk CRCs. It does not
prove visual equivalence. Optional PDF inspection requires `pypdf`:

```bash
python3 tools/inspect-filter-graphs.py \
  --probe-prefix output/filter-graphs-0.25 --pdf
```

The optional check verifies three MediaBoxes and extractable headings and
reports image/font resources without assuming that native PDF filters are
vector. It is not a conformance or color-fidelity certificate.

## Authoring checks and their boundary

The authoring environment has no Racket executable or pinned native libraries.
A complete checkout download was attempted but failed. Work is based on fetched
current source contexts and complete files recovered from earlier patches;
this is **not a complete checkout**. Full copies of the current main module, test runner, and package metadata
were checked against the Git blob hashes returned by GitHub.

Completed checks: new/changed source structure, test-suite structure and counts,
new export/documentation coverage, C mirror compilation/execution, Python and
shell syntax, ten synthetic inspector tests, synthetic PDF inspector exercise,
and forward/reverse/reapply checks of the patch against the available source
contexts. None of these is Racket compilation or native Skia execution.

No native PDF/SVG from this new stage has been generated or visually validated
here. The maintainer's local run remains required. Previous Unicode conformance
results are historical, not a new run for this release. No fonts, native
libraries, compiled bytecode, or fabricated rendering results are included in
the patch. Nothing is pushed to GitHub.
