# Runtime effects: application and validation

Baseline: `aed63287d0d375513db5c8577b4b72de2ec5a3d8`
(`Add document annotation support`). The maintainer's preceding log reports all
593 tests, both symbol audits, and the annotation doctor passing.

## Apply once to the pushed 0.27 baseline

```bash
PATCH="downloads/skia-for-racket-0.28.0-runtime-effects-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-runtime-effects.sh
```

This is a complete stage patch, not an additive fix for an older 0.28 patch. Do
not apply earlier 0.26/0.27 fixes again. Their pushed implementations are retained.
The script uses the selected Racket for both compilation and execution and
explicitly compiles **all** `tests/*.rkt`, including dynamic-require targets.
It does not select an independent `raco` from PATH or delete compiled directories.

## Expected host results

- 38 new pure and 39 new native cases: **670 total** = 263 pure + 6 lifetime +
  401 native. `--pure` runs 269 cases.
- **319 required Skia symbols**, **27 required HarfBuzz symbols**.
- On a 64-bit host: reflection records uniform=40, child=24 bytes; uniform
  offset/type/flags fields at 16/24/32 bytes.
- New doctor: mixed reflection, runtime shader/filter/blender rendering,
  retained input lifetime, and structured compiler diagnostics.
- Four explicit 624x224 effect PNGs in each of the three SVGs.

No new Unicode conformance run is implied by these totals. The byte-layout
mirror and symbol lookup are necessary checks, not sufficient evidence that a
custom native library is compatible. Use the pinned SkiaSharp package.

## Single combined visual runner

Open `output/runtime-effects-0.28.review.html` and
`output/runtime-effects-0.28.pdf`. The runner writes:

| Suffix | Content |
|---|---|
| `.uniforms.svg` | Alpha/color uniform, procedural bands, changed matrix/phase, integer and array uniforms. |
| `.children.svg` | Ordinary gradient child, image child, nested runtime shader, typed shader/filter/blender inputs. |
| `.pipeline.svg` | Runtime color filter, existing filter composition, custom paint blender, retained inputs after close. |
| `.trace.json` | Actual reflected uniform sizes/offsets/types/flags and child slots. |

Each SVG also has a `.reference.png` counterpart. References are independent
raster drawings from the callbacks, **not renderings of the exported PDF/SVG**.
Both vector outputs use explicit rasterization for the bounded effect panels;
labels, panel borders, and checkerboards remain vector. This does not establish
native PDF/SVG serialization support for arbitrary SkSL or custom blenders.

The standard-library inspector checks SVG dimensions, outlined labels, resource
references, embedded PNG dimensions/CRCs/bounded scanline inflation, and the
reflection trace. Its self-tests use synthetic fixtures, not Skia output.

Optional actual PDF parsing requires `pypdf` in the selected Python environment:

```bash
python3 tools/inspect-runtime-effects.py \
  --probe-prefix output/runtime-effects-0.28 --pdf
```

It checks three 720x500-point MediaBoxes, native text headings, and four bounded
image resources per page, excluding their alpha masks. Open the actual vector
files as well: structure checks do not establish visual equality.

## Authoring-environment validation boundary

The changed existing code files were reconstructed as complete files and checked
against their current GitHub blob SHA-1 values before editing. Documentation
edits use separately fetched current header contexts. Git parses the generated
patch and forward/reverse application is checked on the assembled baseline.
This is stronger than the earlier core/native context-only patch generation,
but **not a claim that every historical documentation file was recovered**.

Racket compilation, the 670 Racket cases, live native rendering, and the new
visual outputs have **not** been run in the authoring environment. Performed
checks are recorded separately in the delivered validation JSON. Host-C mirrors
and synthetic Python inspection cannot replace the selected-Racket/native run.

The final successful host-script step regenerates `SOURCE-SHA256SUMS.txt`.
No native binaries or fonts are included, and no repository changes are pushed.
