# Document-link validation — 0.27

Base commit: `0d250497fcc5b5f61e3d95d5395ae4056ae41f4e`, the pushed 0.26 output
stage including both ICC/PNG fixes. The maintainer supplied a successful
541-case native run and the color-output artifacts. This patch does not alter
that encoder workaround.

## Apply and run

From the existing repository root, with the patch in `downloads`:

```bash
PATCH="downloads/skia-for-racket-0.27.0-document-links-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-document-links.sh
```

The script uses the selected interpreter for both `-l raco -- make` and all
execution. It compiles **all `tests/*.rkt`**, including dynamic-require targets;
it does not choose `raco` independently from PATH or delete compiled caches.
It runs source checks, inspector self-tests, five existing C ABI mirrors,
both symbol audits, doctor, the full suite, one combined example registry,
SVG/link-target inspection, and source-checksum regeneration.

| Check | Expected |
|---|---:|
| New pure/native tests | 25 / 27 |
| Full suite | 593 |
| Pure / lifetime / native | 225 / 6 / 362 |
| `--pure` cases | 231 |
| Required Skia / HarfBuzz symbols | 301 / 27 |
| New native structures | 0 |
| Python inspector self-tests | 14 |

`static-check.py` prints `racket_execution: NOT RUN` because that Python process
only checks source/installer structure. The later Racket compiler, doctor, and
suite are separate steps; successful static checks do not replace them.

## Review files

Open `output/document-links-0.27.review.html` and `output/document-links-0.27.pdf`.
The HTML uses **interactive SVG `object` elements**, not image-only SVG thumbnails.
It also links to each standalone SVG. The right-hand PNGs are independent raster
reference drawings; they are not PDF/SVG rasterizations and have no interactivity.

| Suffix | Links | Destination views | Review |
|---|---:|---:|---|
| `.links.svg` | 4 | 2 | HTTPS, same-page note, forward/cross-file jump, local HTML |
| `.transforms.svg` | 5 | 1 | Rotation, clipping, two picture replays, return link |
| `.destinations.svg` | 4 | 2 | Cross-page return, Unicode target, query escaping, local top |

All SVG pages are 720 x 500 pt and should contain **no embedded images**.
The PDF has three pages of the same size, 13 Link annotations, and five named
destinations. The companion HTML is a static local click target. No link is
followed by the inspector.

The standard-library inspector checks coordinates, root-level invisible link
rectangles, destination views, URI aliases/escaping, graphics resource references,
cross-SVG fragments, relative files, reference PNG sizes, and interactive HTML.
For parser-based PDF rectangle and destination-page checks, install/use `pypdf`
in the Python environment and run:

```bash
python3 tools/inspect-document-links.py \
  --probe-prefix output/document-links-0.27 --pdf
```

Test actual buttons in the browser/PDF viewer. Links in a rotated shape use a
bounding rectangle, not an exact polygon; complex clips are likewise approximate.
Named SVG views pan to the captured point and retain the original viewport extent.
Opening a sibling SVG may replace the embedded document; refresh the review page
to reset it. A viewer may prompt before following external links.

## Authoring-environment boundary

The authored checks cover new source delimiters and suite structure, public
exports/signatures and guide coverage, Python/shell syntax, synthetic inspector
cases, and generated-patch parsing plus forward/reverse application against
fetched source contexts. Four complete baseline files are verified against their
Git blob hashes. This is **not a full-checkout test**.

Racket and the pinned native libraries are not installed in the authoring
container. Racket compilation, the new native tests/doctor, and the native visual
probe have therefore **not run here**. Browser click testing of native output
remains a host validation step. Synthetic files used for inspector testing are
not native rendering evidence. The full synthetic inspector fixture covers
three SVGs and a three-page PDF with 13 links and five destinations, using both
catalog destination dictionaries and string-based name trees. Earlier Unicode
conformance results are historical.
