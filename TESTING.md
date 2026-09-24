# Testing

## Status

**0.1 through 0.12 — LIVE VALIDATED on macOS/aarch64.** The latest live run
used Racket 9.3.0.2 with pinned SkiaSharp 3.119.1 and HarfBuzzSharp 8.3.1.2.
Both symbol audits reported zero missing bindings, every doctor probe passed,
all **150** source test cases passed (36 pure, 6 lifetime, 108 native), and the
mixed-text visual probe rendered correctly. The live audits reported 221 Skia
bindings and 27 HarfBuzz bindings, with zero missing symbols.

**0.13 Unicode line breaking — NOT YET LIVE RUN IN THE AUTHORING
ENVIRONMENT.** The Unicode 15.1 UAX #14 resolver, grapheme-preserving tailoring,
shared paragraph/mixed-layout wrapper, tests, doctor probe, and visual example
received source review here. The 0.13 tree contains **159 source test cases**:
42 pure, 6 lifetime, and 111 native. It adds no native symbols or ABI structs.

## Checks performed for 0.13 source

Run `python3 tools/static-check.py` and the host-C layout command below to
reproduce the non-Racket checks. The checker verifies balanced source strings
and delimiters, test-suite structure/counts, explicit public exports,
documentation coverage, local module paths, installer shell syntax, and the
installer against synthetic offline archives. It does **not** parse/expand
Racket or load Skia.

The host-C mirror independently checks the selected ABI sizes/offsets from
0.1–0.5. Version 0.9 added the four-pointer `sk_textblob_builder_runbuffer_t` mirror.
Version 0.10 additionally mirrors HarfBuzz `hb_glyph_info_t` (20 bytes),
`hb_glyph_position_t` (20 bytes), and `hb_feature_t` (16 bytes). The host
checker asserts those layouts as well as the existing image, sampling, codec,
and font-metrics layouts. The host
checker does not include upstream headers and is not a substitute for Racket FFI
execution.

The new declarations were compared against SkiaSharp v3.119.1, HarfBuzzSharp
8.3.1.2 generated bindings, the corresponding mono/skia C shims, and the
SkiaSharp.HarfBuzz `SKShaper` implementation. Font-manager matches return owned typeface references. Text-blob run
buffers are temporary native storage owned by the builder until
`sk_textblob_builder_make` seals the immutable blob. The native symbol audit is
part of the required live validation sequence for every added FFI binding.

No benchmark, native-heap leak-measurement claim, cross-platform rendering-
equivalence claim, or GPU claim is made by this report.

## Run the 0.13 Racket tests locally

From the extracted root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
bash tools/install-harfbuzz.sh &&
bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt
```

A successful full run should report **42 pure + 6 lifetime + 111 native = 159
source test cases**. Cases contain multiple assertions, so this is not an
assertion count. The 0.13 doctor retains every earlier smoke check and additionally
verifies UAX #14 hyphen/CJK wrapping and rasterization.

To run only tests that do not need the native library:

```sh
"$RACKET" run-tests.rkt --pure
```

This requests the 48 pure/lifetime cases. It does not run the 111 native cases,
and says so. A default run fails rather than silently skipping native tests
when the library cannot load. Alternatively, after installing the package:

```sh
"$RACO" test tests
```

### Regression coverage

The 0.1–0.3 coverage remains: colors and packed-channel ordering; argument and
allocation-limit validation; C struct sizes/offsets as represented by Racket;
explicit/scoped ownership; cross-thread rejection; surfaces, geometry, paths,
transforms and clipping; alpha/compositing; images and snapshots; PNG output;
bitmap bridging; fonts/simple text/glyph paths; and color/gradient/image/blend
shaders including shader refcount behavior.

Version 0.4 coverage remains for codec/encoder layouts, PNG/JPEG/WebP
encode/probe/decode, file-backed I/O, image subsets, and source-rectangle
drawing. Version 0.5 adds pure validation for dash/corner/discrete/trim effects
and path-measure construction. Native cases cover dash rasterization and paint
ownership, the additional effect constructors/composition, trim rendering,
path-measure length/position/tangent/segment behavior, private snapshot safety
across source mutation/closure, contour traversal and path replacement, all
five boolean PathOps, simplify/winding conversion, and use-after-close
rejection. Version 0.6 adds validation and native cases for color-matrix,
blend, and composed color filters; mask blur styles/attachment; image blur;
drop-shadow and shadow-only filters; color-filter image nodes; composed image
filter graphs; paint ownership/getters/detachment; and use-after-close rejection.
Versions 0.7–0.8 cover picture recording/replay/rasterization and expanded
path/SVG geometry. Version 0.9 adds font-manager enumeration/matching/fallback,
BCP-47 language hints, positioned text-blob construction, bounds/IDs, blob
replay, font-lifetime independence, and closed-resource rejection. Version
0.10 adds HarfBuzz loading/version checks, font-stream snapshotting, Latin and
RTL shaping, OpenType feature parsing, UTF-8 cluster extraction, positioned
run drawing, shaped-run to TextBlob conversion, and closed-shaper rejection.
Version 0.11 covers paragraph wrapping/alignment; 0.12 covers mixed bidi/script
runs and font fallback; 0.13 covers Unicode 15.1 UAX #14 opportunities,
grapheme-preserving breaks, hard separators, unspaced CJK, and punctuation.

The repeated allocation case is not a leak detector. The suite does not yet
measure native heap reclamation directly, expose path-measure matrices or path
iterators, validate 1D/2D stamped path effects, validate every encoded format,
decode animation frames, normalize encoded orientation, exercise ICC/color
space objects, expose advanced filter families/crop rectangles, perform
Southeast Asian dictionary segmentation, language-specific hyphenation,
justification, or test GPU resources.

### Visual smoke checks

```sh
mkdir -p output
"$RACKET" examples/circle.rkt output/circle.png
"$RACKET" examples/gallery.rkt output/gallery.png
"$RACKET" examples/text.rkt output/text.png
"$RACKET" examples/text-blobs.rkt output/text-blobs.png
"$RACKET" examples/shaping.rkt output/shaping.png
"$RACKET" examples/layout.rkt output/layout.png
"$RACKET" examples/mixed-text.rkt output/mixed-text.png
"$RACKET" examples/line-breaking.rkt output/line-breaking.png
"$RACKET" examples/gradients.rkt output/gradients.png
"$RACKET" examples/codecs.rkt output/codecs.png
"$RACKET" examples/path-effects.rkt output/path-effects.png
"$RACKET" examples/filters.rkt output/filters.png
"$RACKET" examples/pictures.rkt output/pictures.png
"$RACKET" examples/svg-paths.rkt output/svg-paths.png
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Choose fresh filenames on reruns. `text-blobs.rkt` covers the 0.9
FontManager/TextBlob layer. `shaping.rkt` covers Latin/RTL shaping and OpenType
features; `mixed-text.rkt` covers bidi/script/fallback runs; and
`line-breaking.rkt` covers CJK, punctuation, numeric context, grapheme clusters,
hard separators, and no-break spaces.

## Reproduce non-Racket checks

These tools are optional and are not runtime dependencies of the library.

```sh
python3 tools/static-check.py
cc -std=c11 -Wall -Wextra -Werror tools/struct-layout.c -o /tmp/skia-layout-check
/tmp/skia-layout-check
python3 -m py_compile tools/static-check.py tools/syntax_scan.py
bash -n tools/install-native.sh
bash -n tools/install-harfbuzz.sh
bash -n tools/audit-symbols.sh
bash -n tools/audit-harfbuzz-symbols.sh
```

Successful static checks are not a substitute for the Racket/native run.


Expected additional doctor line for 0.7:

```text
Pictures/recording passed; recording, replay, and rasterization verified
```


Expected additional doctor line for 0.8:

```text
Paths/SVG passed; relative commands, SVG conversion, and point queries verified
```


Before native doctor/test runs, `bash tools/audit-symbols.sh` should report zero missing required symbols. This is especially important after adding FFI bindings.


Expected additional doctor line for 0.9:

```text
Font manager/text blobs passed; fallback, positioned runs, and replay verified
```

For 0.9 the symbol audit should see 215 `define-native` symbols and report zero missing bindings before the doctor starts.


Expected additional doctor line for 0.10:

```text
HarfBuzz shaping passed; glyph extraction, positioning, and drawing verified
```

Before the doctor, `bash tools/audit-harfbuzz-symbols.sh` must report zero
missing `define-hb-native` symbols.


Expected additional doctor line for 0.11:

```text
Paragraph layout passed; wrapping, alignment, metrics, and drawing verified
```


Expected additional doctor line for 0.12:

```text
Mixed text layout passed; bidi runs, script segmentation, fallback, and drawing verified
```

The HarfBuzz symbol audit should now report **27** required bindings and zero
missing symbols. The Skia audit remains at **221**.

Expected additional doctor line for 0.13:

```text
Unicode line breaking passed; UAX #14 opportunities and CJK wrapping verified
```

Version 0.13 adds no native bindings, so the expected symbol counts remain
**27 HarfBuzz** and **221 Skia**, both with zero missing symbols.
