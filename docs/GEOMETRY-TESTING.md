# Structured geometry validation (0.31)

## Baseline

Apply this patch **on top of the working 0.30 tree**, not on top of 0.29 alone.
During authoring, both GitHub branch/commit reads and `info.rkt` still returned
`aa94a31509635090fdd2677ab393e8e005927dbb` (0.29). The baseline used here is that
visible source plus the exact 0.30 canvas-primitives patch reported tested by
the maintainer. It is not presented as a verified newer GitHub commit.

## Expected host results

38 new pure cases + 42 new native cases = **80 additions**.
Complete expected suite: **876 cases** (359 pure, 6 lifetime, 511 native).
`--pure` runs 365. Required symbols: **367 Skia / 27 HarfBuzz**.
New layouts on a 64-bit host: **48-byte lattice, 16-byte RSXform**;
lattice bounds/colors offsets: **32/40**. Cell-type array elements are one byte.

```bash
PATCH="downloads/skia-for-racket-0.31.0-structured-geometry-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-geometry-primitives.sh
```

One selected interpreter compiles all test modules using
`"$RACKET" -l raco -- make ... tests/*.rkt`. No bare `raco` is selected from PATH.
The script runs source checks, the new inspector's 14 self-tests, seven host-C
mirrors, symbol audits, doctor, all suites, the visual registry, structural
inspection, and finally source-checksum regeneration.

## Review

Open `output/geometry-primitives-0.31.review.html` and its linked PDF.
All three pages are 720 x 500 points. SVG labels/checkerboards remain vector.

| Page | SVG embedded images | Review focus |
|---|---|---|
| regions | 0 | Boolean holes, integer staircase versus original curve, detached rectangles, local boundary clip |
| images | 4 of 600 x 224 | Fixed borders, small destinations, transparent/fixed-color cells, anchored/tinted sprites |
| meshes | 4 of 600 x 224 | Vertex-color interpolation, texture mapping, colored and textured cubic patches |

PDF submits the first three image-grid panels natively; the atlas and four
mesh/patch panels are explicitly rasterized. Audit reports record this difference.
The `.reference.png` files are independent drawings at 144 DPI, **not**
rasterizations of the PDF/SVG files. `.regions.json` records the same detached
region decomposition while authoring PDF, SVG, and raster reference output.

Optional PDF inspection requires `pypdf`:

```bash
python3 tools/inspect-geometry-primitives.py \
  --probe-prefix output/geometry-primitives-0.31 --pdf
```

The inspector checks XML structure, image dimensions/CRCs, audit classifications,
region snapshot consistency, reference sizes, and optional PDF headings/sizes.
It does not establish visual fidelity or native heap bounds.

## Authoring validation boundary

Racket and the Skia shared libraries were not available for execution in the
authoring container. A network clone also failed. Source was recovered from
previous deliveries; complete affected files were hash-checked where available,
and core/native/type edits use fetched source and exact 0.30 patch contexts.
This is **not** a complete-checkout or Racket/native validation claim.

The delivery is a generated unified diff, checked for parsing, forward/reverse
application, exact reconstruction of authored files, and whitespace errors.
The new code/test structures and assertion arities, shell/Python syntax,
seven host-C mirrors, and 14 synthetic inspector tests were checked locally.
The inspector also passed end-to-end checks on synthetic non-Skia SVG/PDF,
audit, trace, and PNG fixtures. These test the inspector, not native rendering.
The new native probes and full suite still require the host run above.
