# Canvas primitive validation

## Baseline and expected checks

Apply the complete 0.30 patch once to the pushed 0.29 baseline:
`aa94a31509635090fdd2677ab393e8e005927dbb` (Add output capability audit).
The maintainer reports passing 0.29 tests. Earlier ICC/PNG fixes, annotation
corrections, runtime effects, and audit implementations are retained.

This stage adds **28 pure + 40 native = 68 cases**. Expected complete suite:
**796 cases: 321 pure + 6 lifetime + 469 native**. `--pure` runs 327 cases.
Required symbols become **336 Skia / 27 HarfBuzz** (17 new Skia callouts).
No new native struct layouts: point/rectangle buffers reuse the pinned formats;
SkRRect is opaque and only lives in synchronous, scoped native temporaries.

## Apply and run

```bash
PATCH="downloads/skia-for-racket-0.30.0-canvas-primitives-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-canvas-primitives.sh
```

The selected Racket also invokes `raco make` through `-l raco -- make`.
Every `tests/*.rkt` is compiled explicitly, including dynamically required suites.
The script does not select a separate `raco` from PATH or delete compiled trees.
It checks source structure, runs the inspector's synthetic self-tests, compiles
all six prior C mirrors, audits both native libraries, compiles, runs doctor and
all test suites, renders the combined registry, inspects SVG/report structures,
and regenerates `SOURCE-SHA256SUMS.txt` only after those steps succeed.

Expected new doctor message:

```text
Canvas primitives passed: arcs/rrects, clip queries, group opacity, protected restore, SVG layer audit
```

## Visual registry

Open `output/canvas-primitives-0.30.review.html` and the actual
`output/canvas-primitives-0.30.pdf`. There are three 720 x 500 point pages:

| Suffix | Check | SVG images |
| --- | --- | --- |
| `.geometry.svg` | Round/square point sprites; line pairs and open polyline; arcs; asymmetric corners and hollow rounded frame | one 600 x 224 PNG |
| `.clips.svg` | Rounded clip; draw-color; clip-before-transform; local/device query trace | none |
| `.layers.svg` | Per-object versus group alpha; filtered layer; m119 content-bound restriction | three 600 x 224 PNGs |

PDF submits points and layers to the native backend. SVG explicitly rasterizes
only those unsupported groups. Labels and the remaining geometry stay vector.
Compare actual PDF/SVG renderings with the independent 1440 x 1000
`.reference.png` drawings. The reference PNGs are **not** PDF/SVG rasterizations.

The first two opacity panels should differ in the overlap. The group-opacity
panel composites the already-opaque blue/orange group once. The content-bounds
panel intentionally draws outside declared bounds to demonstrate the pinned
unfiltered layer's restriction; this is not recommended application usage.
For reliable authoring, omit bounds or enclose all potentially rendered content.
The layer-paint blur should affect the completed shape group, not the labels.

Four `.audit.json` files record the PDF and each SVG's observed features.
`.queries.json` records native local/device clip bounds separately for PDF, SVG,
and the independent raster reference. Device grids differ across backends;
identical native device coordinate numbers are not expected.

Optional PDF inspection requires `pypdf`:

```bash
python3 tools/inspect-canvas-primitives.py \
  --probe-prefix output/canvas-primitives-0.30 --pdf
```

It checks three PDF page sizes and extractable headings. It does not validate
pixel identity, native vector preservation of every layer, font embedding, ICC,
PDF/A, link interaction, or memory reclamation. The standard-library inspector
checks SVG structure, embedded PNG dimensions and CRCs, output audit feature
statuses, and the query trace. Its 14 self-tests use synthetic data, not Skia.

## Scope of authoring validation

Racket and native Skia are not available in the authoring container for this
stage. No new live-test or native-rendering result is claimed. Source structure,
assertion shapes, Python/shell syntax, inspector self-tests, and C mirror runs
are checked there. The code baseline was recovered from earlier deliveries;
affected regions were checked against the pushed GitHub sources. The patch is
validated by application/reversal/reapplication against those recovered source
contexts, not described as a fresh full Git checkout. See the accompanying
validation JSON for the detailed boundary.
