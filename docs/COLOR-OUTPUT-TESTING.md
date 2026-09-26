# Color-output validation — 0.26.0

Apply this patch to `soegaard/skia-for-racket` at
`7372d061ff2e1cf0c85c44a48d8ce5b994538027` (`Add filter graph support`).
The maintainer's preceding run passed 472 source cases, native audits and
doctor. Its full Unicode conformance results are historical, not a new run.

## Apply and validate on the host

From the repository root, with the patch in `downloads`:

```bash
PATCH="downloads/skia-for-racket-0.26.0-color-output-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-color-output.sh
```

The script uses the same chosen Racket for compilation and execution. In
particular, it runs `"$RACKET" -l raco -- make ... tests/*.rkt ...`; it does not
rely on `raco make run-tests.rkt` discovering dynamic native-test modules,
select a second `raco` from PATH, or routinely delete compiled directories.

Expected results:

| Check | Expected |
|---|---:|
| Entire source suite | 541 cases |
| Pure / lifetime / native | 200 / 6 / 335 |
| Pure-only runner | 206 cases |
| New color suites | 34 pure + 35 native |
| Required Skia / HarfBuzz symbols | 298 / 27 |
| New transfer / XYZ / primaries layouts | 28 / 36 / 32 bytes |
| Encoder layouts on 64-bit host | PNG 32 / JPEG 40 / WebP 24 bytes |
| Encoder ICC pointer offsets on 64-bit host | PNG 16 / JPEG 24 / WebP 8 |
| Inspector synthetic self-tests | 14 |

The script runs source checks, inspector self-tests, all five host-C layout
mirrors, both symbol audits, compilation, doctor, the entire test runner,
the combined visual registry, and structural/ICC inspection. Its final step
regenerates `SOURCE-SHA256SUMS.txt` from the complete local checkout. The patch
does not overwrite that manifest using a partial authoring checkout.

The source checker's `racket_execution: NOT RUN` field describes that Python
check alone. The later Racket build, doctor, and suite results in the same
shell run are the live validation evidence.

## Review the actual output

Open `output/color-output-0.26.review.html` and both linked PDFs:

- `color-output-0.26.pdf`: normal metadata mode.
- `color-output-0.26.pdfa.pdf`: Skia's PDF/A metadata/output-intent mode.

Both have three 720 by 500 point pages. The HTML compares actual browser-
rendered SVG on the left with an independently drawn 144-DPI raster reference
on the right. Reference PNGs are not PDF/SVG rasterizations.

| SVG suffix | Check |
|---|---|
| `.gamma.svg` | The raw sRGB ramp differs from the linear-to-sRGB ramp. The converted and converted/encoded/decoded ramps should agree; the midpoint moves from 128 to approximately 188. |
| `.gamuts.svg` | Four rows start with the same RGB numbers interpreted in different source spaces and are then converted to sRGB. Their patches need not match one another. |
| `.encoded.svg` | Six file round-trip thumbnails are normalized to sRGB before document embedding. Compare the P3-source and converted-sRGB rows; JPEG boundaries can differ. |

The SVGs should contain respectively 3, 4 and 6 embedded PNG images. Surrounding
text uses the existing automatic outline policy. The PDF uses native text.

The review page also displays the **actual six encoded image files**:
`.p3.png`, `.p3.jpeg`, `.p3.webp`, `.srgb.png`, `.srgb.jpeg`, `.srgb.webp`.
Each P3 image retains P3 samples and a P3 ICC profile. Each sRGB image contains
converted samples and an sRGB profile. For the chosen in-gamut colors, an
ICC-aware viewer should display each pair similarly. A screenshot alone is not
proof of profile preservation or correct display calibration.

The `.p3.icc` and `.srgb.icc` files record the supplied source profiles. The
native encoder may regenerate a different binary profile with the same color
semantics. The `.trace.json` records native gamut matrices and sampled pixel
values; it is not a display measurement.

## Structural inspection

```bash
python3 tools/inspect-color-output.py \
  --probe-prefix output/color-output-0.26
```

Only the Python standard library is needed for this command. It checks:

* PNG chunk integrity and bounded ICC decompression, JPEG APP2 profile
  reassembly, and WebP RIFF/VP8X/ICCP structure.
* Embedded ICC colorant matrices and sampled transfer curves against the source
  profiles, and the forwarded ICC description, rather than requiring identical bytes.
* SVG physical dimensions, resource references, outlined text, and embedded
  PNG counts/integrity; plus the trace's evidence that conversion changed samples.

It does not decode JPEG/WebP pixel data, render the SVGs, measure display color,
or certify PDF/A compliance. Racket native tests perform actual encoder/codec
round trips and sample checks.

With `pypdf` available in the selected Python environment:

```bash
python3 tools/inspect-color-output.py \
  --probe-prefix output/color-output-0.26 --pdf
```

This also verifies both PDFs' page sizes, the normal file's lack of a requested
output intent, and the PDF/A-mode file's RGB output intent and XMP identification.
The `certified_pdfa: false` result is intentional. An independent conformance
validator is required for an archival PDF/A claim.

## Authoring validation boundary

The implementation was checked against the pinned native headers/source.
Checks performed in the authoring environment are source delimiter/test-suite
structure and export/documentation checks, host-C compilation/execution of the
new layout mirror, Python/shell syntax, synthetic inspector tests, and patch
application/reversal against fetched source contexts. Complete copies of
`main.rkt`, `run-tests.rkt`, and `info.rkt` are verified against their Git blob
hashes. Those checks are not equivalent to a complete-checkout validation.

**Racket compilation, the new native test suites, native color-probe generation,
and visual review of the 0.26 native output have not been run here.**
Synthetic PDF/container fixtures test the inspector, not the Skia backend.
No network installer, native library, or font binary is included in the patch.

No GitHub write or push has been performed.
