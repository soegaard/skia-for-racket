# CPU color-filter validation

Apply the complete 0.36 patch to commit
`71ba041e7f2f0d81e1074c5da923f7ffbb9ce25f` (portable drawing / 0.35), then run:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-color-filters.sh
```

The validator uses that same interpreter for compilation and execution through
`racket -l raco -- make`, and explicitly compiles **all** `tests/*.rkt` before
the dynamically loaded native suites. It runs the new doctor separately after
the existing cumulative doctor. Source sums are regenerated only after the
selected validation succeeds.

Expected totals:

| Check | Expected result |
|---|---:|
| New pure / native tests | 36 / 44 |
| Complete RackUnit suite | 1,276 |
| `run-tests.rkt --pure`, including lifetime | 567 |
| Required Skia / HarfBuzz symbols | 386 / 27 |
| Host-C ABI mirror programs | 9 |
| High-contrast record | 12 bytes; offsets 0, 4, 8 |
| Inspector tests | 23; 3 skip without pypdf |

The ABI mirror can optionally compile against the actual pinned header using
`SKIA_C_TYPES_HEADER`; without it the C program checks a local declaration of
the pinned C record. The Racket doctor additionally checks actual FFI offsets
and submits a high-contrast filter to Skia.

## Combined review registry

Open `output/color-filters-0.36.review.html` and the linked actual PDF. All pages
are 720 x 500 points; independent raster references are 1440 x 1000 pixels.

| Page suffix | Panels | Expected document raster images |
|---|---|---:|
| `.matrices` | Unfiltered control, HSLA hue, desaturation, RGB lighting | 3 |
| `.curves` | Gamma encode, gamma decode, RGB-only table inversion, threshold | 4 |
| `.composition` | Luma/alpha, high contrast, parallel lerp, gamma composition | 4 |

Every effect panel is a 300 x 96 logical output group at scale 2, producing one
**600 x 192** image. The unfiltered control, checkerboards, text, and framing
remain native/vector document content. These small filter panels are deliberate
fallbacks; a whole-page raster replacement is rejected by the inspector.

The references run the same drawing primitives and filters **directly on a
raster canvas**, without output-group capture and without rasterizing an exported
PDF or SVG. The registry also writes four audit reports, a decision tree, and
`.samples.json` with native RGBA results for gamma, hue, tables, luma, and
composition. The inspector checks those sample values independently of labels.

The SVG inspector follows actual `<use>` references, checks PNG CRCs and image
sizes, and checks for missing/duplicate references. PDF inspection follows
executed Image/Form XObjects per page. It counts repeated uses as repeated draws
and records `/SMask` resources separately; masks are not additional fallbacks.

## Optional PDF dependency

`PYTHON` selects the Python environment (default `python3`). `CHECK_PDF=auto`
checks the PDF when `pypdf` is installed, otherwise prints an explicit skip.
`CHECK_PDF=1` requires PDF inspection. For an existing virtual environment:

```bash
RACKET="$RACKET" PYTHON="/path/to/venv/bin/python" CHECK_PDF=1 \
  bash tools/validate-color-filters.sh
```

The already generated files can be checked without recompiling Racket:

```bash
python3 tools/inspect-color-filters.py --self-test &&
python3 tools/inspect-color-filters.py --probe-prefix output/color-filters-0.36 --pdf
```

Review HSL desaturation versus luma, gamma encode versus decode, threshold
banding, and alpha swatches over the checkerboard. The high-contrast inversion
works in linear values, so it is not expected to look like a byte-inversion
table. Inspector success alone does not establish visual or ICC fidelity.
