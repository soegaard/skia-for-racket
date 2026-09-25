# Vector-output refinement — application and validation

Version: **0.23.0**. Base commit:
`fa7d04e881df9f80a99e62e5f51aaa5ec30b02dc` (`Add SVG document output`).
The maintainer reported the 0.22 tests passing and supplied its SVGs and raster
references. That is the starting point, not a new test run for this patch.

## What was checked in the authoring environment

The new Racket sources and changed function bodies received delimiter/string,
module-export/documentation, and test-suite structure checks. The Python output
inspector compiles and passes eight synthetic tests. Its optional PDF path was
also exercised with a synthetic non-Skia three-page PDF. Forward/reverse patch
application and whitespace checks use fetched baseline **source contexts**.
A few complete small files were reconstructed and checked against their Git
blob hashes. A complete repository checkout could not be downloaded here.

**Racket compilation, the new Racket tests, Skia-native rendering, and the new
visual probes have not been run here.** There is no Racket executable or pinned
native library in this authoring environment. Syntax scans and synthetic parser
fixtures are not substitutes for those checks. The standalone JSON validation
record records the exact boundary.

## Expected host results

The patch adds **20 pure and 29 native cases**. Expected total: **344 source test
cases** (112 pure, 6 lifetime, 226 native); `--pure` runs 118 cases. The suites
are expected to report 54, 6, 10, 12, 16, 20, 132, 17, 21, 27, and 29 cases.
These counts are not assertion counts and are not claimed execution results.

Required symbols stay **249 Skia** and **27 HarfBuzz**. No new C layouts or
native package versions are introduced. Existing codec and PDF ABI checks stay
in the sequence. Native font snapshots use already-bound font/typeface calls.

## Apply and run

Run from the repository root. Store the downloaded patch in `downloads` first.
Do not reapply older PDF/SVG patches on top of this baseline.

```bash
PATCH="downloads/skia-for-racket-0.23.0-vector-output-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&

python3 tools/static-check.py &&
python3 tools/inspect-vector-output.py --self-test &&

cc -std=c11 -Wall -Wextra -pedantic \
  tools/check-codec-abi.c -o /tmp/skia-codec-abi-check &&
/tmp/skia-codec-abi-check &&
cc -std=c11 -Wall -Wextra -pedantic \
  tools/check-pdf-abi.c -o /tmp/skia-pdf-abi-check &&
/tmp/skia-pdf-abi-check &&

bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&

"$RACO" make \
  main.rkt \
  output.rkt \
  bitmap.rkt \
  tools/doctor.rkt \
  run-tests.rkt \
  tests/output-pure-test.rkt \
  tests/output-native-test.rkt \
  examples/vector-output.rkt &&

"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&

mkdir -p output &&
"$RACKET" examples/vector-output.rkt output/vector-output-0.23 &&
python3 tools/inspect-vector-output.py \
  --probe-prefix output/vector-output-0.23 &&

python3 tools/update-source-sums.py
```

The patch does not modify `SOURCE-SHA256SUMS.txt`; the last command regenerates
it from the actual complete checkout. Nothing is automatically committed or
pushed. `git apply --check` must succeed against your working tree; stop rather
than forcing a conflicting patch onto locally changed source.

## Review the actual outputs

Open `output/vector-output-0.23.review.html` in a browser and
`output/vector-output-0.23.pdf` in a PDF viewer.

The three panels use the same page registry for both formats:

| Suffix | What to check |
|---|---|
| `.units.svg` | 210 by 140 mm page, 10 mm margins, 100 mm ruler, vector gradient. Physical SVG root sizes use points, matching PDF. |
| `.text.svg` | Simple, shaped, paragraph, prebuilt-blob, and newly recorded text. SVG should contain outlines; PDF should retain native text where the backend supports it. |
| `.effects.svg` | Padded shadow and radial-gradient groups. Only those groups are embedded images; labels and the dashed path remain vector. |

The matching `.reference.png` files are separate 144-DPI raster renders, **not
PDF/SVG rasterizations**. CSS/zoom scales the browser previews; print the PDF or
SVG at actual size for a physical ruler check. Check thin strokes and text at
several zoom levels, including effects near the content clip.

At 144 DPI the two padded SVG PNGs should be **386 by 284** and **329 by 284**
pixels. The inspector checks PNG chunk integrity and dimensions without relying
on a particular encoder's compressed bytes.

For PDF page sizes, text operators, extraction samples, and font-resource reports,
run the optional pypdf-backed check:

```bash
python3 tools/inspect-vector-output.py \
  --probe-prefix output/vector-output-0.23 --pdf
```

pypdf is a development inspection dependency only, not a Racket package
dependency. A report that a font is not embedded is informational: native PDF
font handling varies. Outlining removes selectable text and cannot preserve
bitmap-only/color glyphs; explicit raster groups are the fallback for those.

The text policy applies while authoring. An already-recorded native-text
picture remains native at replay time; the regression suite explicitly checks
that limitation instead of claiming that export rewrites native recordings.

The full Unicode 15.1 conformance suite is separate and unchanged:

```bash
RACKET="$RACKET" bash tools/run-unicode-conformance.sh
```

The earlier 10274 line-break / 91707 bidi-character results are historical, not
new execution results for this patch. No performance, cross-platform rendering,
PDF/A conformance, or native-heap leak claim is made by this delivery.
