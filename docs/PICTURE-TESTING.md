# Persistent-picture validation

Apply the complete 0.33 patch once to the updated 0.32 checkout at
`9c2bc04e00ff9bc42b6606e0aee7703ee06e1d24`, which includes the numeric SVG
point-length inspector fix. Preserve the earlier ICC, region, and annotation fixes.

```bash
PATCH="downloads/skia-for-racket-0.33.0-persistent-pictures-20260927.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-persistent-pictures.sh
```

The selected executable invokes `raco make`, compiles every `tests/*.rkt`, runs
doctor and all suites, and creates the combined probe registry. It then launches
a **separate Racket process** using the same executable to decode the generated
trusted SKP and write its raster/metadata results. No PATH-selected `raco` is used.

Expected counts: **1042 Racket tests** (449 pure + 6 lifetime + 587 native).
The new suites contain **31 pure / 40 native** tests; `--pure` runs 455 total.
Roundtrip tests include retained-depth matrices replayed under a later outer
perspective transform, where prematurely discarding Z would be observable.
Required symbols: **377 Skia / 27 HarfBuzz**. There are no new native structs;
the eight preceding host-C mirrors still run. The inspector has **22 self-tests**.

## Review artifacts

Open `output/persistent-pictures-0.33.review.html` and the PDF alongside it.
The HTML shows actual SVGs next to independent raster drawings. Those reference
PNGs are not rasterizations of the PDF or SVG and cannot prove viewer fidelity.

| Suffix | Check | Embedded images per SVG/PDF page |
|---|---|---|
| `.roundtrip.svg` | Live versus saved/loaded native drawing; expected opaque-import report. | None |
| `.indexed.svg` | Two clipped windows into the same R-tree recording. | None |
| `.shaders.svg` | Retained repeat/mirror shaders after source-picture closure. | Two 600 x 360 PNGs |

The first page and combined PDF deliberately use report policy. Their audit
reports have **`blocking: true`**, solely because imported picture provenance is
unknown. The indexed and shader pages are strict exports with no blocking
findings. Four additional `.opaque.audit.json` preflights verify that unknown
imports stay unknown with and without a raster boundary, on both backends.

The example writes `.cache.skp`, `.expected.rgba`, and `.pictures.json`. The
fresh-process command writes `.fresh.png`, `.fresh.rgba`, and `.fresh.json`.
The inspector requires the 240 x 140 raw RGBA buffers to be identical. It checks
nominal/cull extents and native counters but does not compare native IDs across
processes, where numeric reuse is valid. Stream version 103 is distinct from
native milestone 119.

```bash
# Recheck existing files, with optional PDF structural checks (requires pypdf):
python3 tools/inspect-persistent-pictures.py \
  --probe-prefix output/persistent-pictures-0.33 --pdf
```

Do not use `tools/replay-picture-probe.rkt` on untrusted external SKPs: it
explicitly opts into native trusted decoding. It is a development probe, not a
safe file-viewing service.

The successful validator's last step regenerates `SOURCE-SHA256SUMS.txt`.

## Authoring validation boundary

Racket compilation, native execution, new native probe generation, and the
fresh-process replay were not available in the authoring environment. Local
checks cover new/changed source structure, test-suite and assertion shapes,
export documentation, native declarations against the pinned C shim, Python
self-tests and synthetic end-to-end fixtures, existing host-C mirrors, and exact
patch application/reversal. Synthetic fixtures test the inspector only.

Complete reconstructed files that match the pinned repository's Git blob hashes
are verified as complete. Historical core/native/documentation modifications are
checked against fetched current source contexts; this is not full-checkout build
verification. The standalone validation record lists these boundaries.
