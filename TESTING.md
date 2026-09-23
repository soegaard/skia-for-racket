# Verification report — 2026-09-23

## Status

There are two distinct validation states in this source tree.

**0.1 baseline — LIVE VALIDATED.** The drawing/image implementation was run by
the user on macOS/aarch64 with Racket 9.3.0.2 and the pinned SkiaSharp 3.119.1
native asset. `tools/doctor.rkt` reported native ABI milestone 119.0, raster
readback and PNG encoding passed, all 57 source test cases passed (13 pure,
6 lifetime, 38 native), and the circle, gallery, and bitmap-bridge examples
rendered correctly.

**0.2 font/text additions — NOT YET LIVE RUN IN THE AUTHORING ENVIRONMENT.**
This environment has no Racket executable or libSkiaSharp, so the new font,
typeface, text, glyph, and font-metrics paths could only receive source, ABI,
layout, installer, and documentation checks here. The full 0.2 suite now has
69 source test cases and should be run locally before 0.2 is considered native
validated.

## Checks performed for 0.2 source

Run `python3 tools/static-check.py` and the host-C layout command shown below to
reproduce the non-Racket checks. The checker verifies balanced source strings
and delimiters, test-suite structure/counts, explicit public exports,
documentation coverage for those exports, local module paths, installer shell
syntax, and the installer against synthetic offline archives. It does **not**
parse/expand Racket or load Skia.

The host-C mirror checks the selected ABI field sizes/offsets independently of
Racket. It does not include upstream Skia headers and does not prove Racket FFI
layout compatibility. In 0.2 it includes the 64-byte font-metrics structure in
addition to the 0.1 image/rectangle/sampling/PNG structures.

The font/text C declarations were compared against the pinned SkiaSharp 3.119.1
generated interface, including simple-text drawing/measurement, typeface and
font constructors/destructors, font getters/setters, metrics, text-to-glyph,
glyph-path/text-path, native string access, enum values, and metrics flags.

No benchmark, leak-free claim, cross-platform rendering-equivalence claim, or
full text-layout claim is made by this report.

## Run the 0.2 Racket tests locally

From the extracted root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt
```

A full run contains **69 source test cases**: 15 pure, 6 lifetime, and 48
native. Cases can contain multiple assertions, so 69 is a source-case count,
not an assertion count. The 0.2 doctor additionally creates a default typeface
and font and checks simple-text measurement after the original raster/PNG smoke
test.

To run only tests that do not need the native library:

```sh
"$RACKET" run-tests.rkt --pure
```

This requests the 21 pure/lifetime cases. It does not run the 48 native cases,
and says so. A default run fails rather than silently skipping native tests
when the library cannot load. Alternatively, after installing the package:

```sh
"$RACO" test tests
```

### Regression coverage

The 0.1 coverage remains: colors and packed-channel ordering; argument and
allocation-limit validation; C struct sizes/offsets as represented by Racket;
explicit double-close and shared lifetime cells; scoped exception cleanup;
cross-thread access rejection; surface initialization; odd-width pixel rows;
straight/premultiplied alpha; geometry and strokes; compositing; paint/path
copies; bounds and fill rules; transform order; clipping; save-stack
restoration; borrowed-canvas reachability; explicit source closure; snapshot
independence; copied image input; image scaling; PNG signature/dimensions,
decoding and same-process repeatability; overwrite refusal; bitmap channel
order; and repeated allocate/render/encode/close.

Version 0.2 adds source/native cases for font/typeface option validation and
metrics layout, default typeface introspection, family/style matching, font
getters/setters, metrics, simple-text measurement/bounds, UTF-8 text-to-glyph
mapping, character-to-glyph mapping, glyph/text outline paths, actual text
rasterization, font retention after closing a caller's typeface wrapper, and
closed font/typeface rejection.

The repeated allocation case is not a leak detector. The suite does not yet
measure native heap reclamation, validate every platform/font backend, shape
complex scripts, or test GPU resources.

### Visual smoke checks

```sh
mkdir -p output
"$RACKET" examples/circle.rkt output/circle.png
"$RACKET" examples/gallery.rkt output/gallery.png
"$RACKET" examples/text.rkt output/text.png
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Choose fresh filenames on reruns. The gallery exercises Bézier/control
geometry, alpha overlap, clipped diagonal lines, an even-odd ring, transformed
shapes, and image sampling. The text example exercises baseline text drawing,
metrics, and an outline path. Inspect text placement/outlines as well as
missing/clipped shapes, channel ordering, and transparent edge artifacts.

## Reproduce non-Racket checks

These tools are optional and are not runtime dependencies of the library.

```sh
python3 tools/static-check.py
cc -std=c11 -Wall -Wextra -Werror tools/struct-layout.c -o /tmp/skia-layout-check
/tmp/skia-layout-check
python3 -m py_compile tools/static-check.py tools/syntax_scan.py
bash -n tools/install-native.sh
```

Successful static checks are not a substitute for the Racket/native run.
