# Portable drawing validation

Run from the repository root after applying the complete 0.35 patch:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACKET="$RACKET" bash tools/validate-portable-drawing.sh
```

The script uses this exact executable for `raco make` (`racket -l raco -- make`), doctor, every RackUnit suite, and the probe. It explicitly compiles all `tests/*.rkt` before the dynamic native-test loads. It runs the eight existing C ABI checks and both symbol audits. The native symbol requirements remain 377 Skia / 27 HarfBuzz; no record layouts change.

The new suites contain 40 pure tests and 34 native tests. The expected complete total is 1,196 tests (531 pure including lifetime, 665 native). The existing 0.34 tests and previous fixes are unchanged.

`CHECK_PDF=auto` is the default: the structural inspector checks the actual PDF when `pypdf` is installed in the selected Python environment, otherwise explicitly reports `PDF structure NOT CHECKED`. Set `CHECK_PDF=1` to require PDF inspection and fail if the dependency is missing. `PYTHON` selects a Python interpreter (default `python3`). For example, after installing pypdf in a virtual environment:

```bash
RACKET="$RACKET" PYTHON="/path/to/venv/bin/python" CHECK_PDF=1 \
  bash tools/validate-portable-drawing.sh
```

The source checksums are regenerated only after every preceding selected check succeeds. Inspection output is first written to a temporary file; a failed inspection never publishes an empty replacement report or gets hidden by `tee`.

## Review files

Open `output/portable-drawing-0.35.review.html` and its linked PDF. The registry generates all three pages in one run:

| Page | Expected structure |
|---|---|
| `markers` | Four native groups; circles/squares, fill/stroke, overlap and gradient. No image resources. The SVG export uses `vector-only`. |
| `grids` | Two native groups. Nine nine-patch image placements and seven default-cell lattice image placements. One fixed-color cell is geometry and the transparent center paints nothing. No whole-panel fallback. |
| `atlas` | One native group. Five image placements reuse three source crops. The crops are 24x24, 20x28, and 20x20 pixels; no panel-sized image is allowed. |

The SVG checker follows `use` references, so repeated image resources count as repeated **placements**, not extra source definitions. The optional PDF checker traverses executed Image/Form XObjects from page content streams. A soft mask is not counted as a second drawn image. It checks each page separately, rather than scanning every image object in the entire PDF.

All pages are 720x500 pt. Independent raster reference images are 1440x1000. The `.reference.png` files come from separate native raster drawings, not rasterizations of the exported documents.

Additional files include `.plans.json`, `.decisions.json`, four export audit reports, source-image PNGs, and `.inspection.json`. Every output group in the probe should choose `native`; image pages must still be marked non-vector-only.

Inspect crop boundaries at several browser zooms, and compare PDF/SVG against the independent raster reference. Separate images can filter differently from a flattened image, especially near fractional edges or after transforms. Structural success alone is not proof of visual equivalence.

## Targeted checks without the complete suite

```bash
"$RACKET" -l raco -- make main.rkt tests/portable-pure-test.rkt tests/portable-native-test.rkt
"$RACKET" -e '(require rackunit/text-ui "tests/portable-pure-test.rkt" "tests/portable-native-test.rkt") (exit (if (zero? (+ (run-tests portable-pure-tests) (run-tests portable-native-tests))) 0 1))'
"$RACKET" examples/portable-drawing.rkt output/portable-drawing-0.35
python3 tools/inspect-portable-drawing.py --self-test
python3 tools/inspect-portable-drawing.py --probe-prefix output/portable-drawing-0.35 --pdf
```

The inspector's synthetic self-tests test only the inspector. They do not substitute for running the Racket/native code or examining actual exported files.
