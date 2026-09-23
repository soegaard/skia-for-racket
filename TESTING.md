# Verification report — 2026-09-23

## Status

**0.1 baseline — LIVE VALIDATED.** The drawing/image implementation was run by
the user on macOS/aarch64 with Racket 9.3.0.2 and the pinned SkiaSharp 3.119.1
native asset. `tools/doctor.rkt` reported native ABI milestone 119.0, raster
readback and PNG encoding passed, all 57 source test cases passed (13 pure,
6 lifetime, 38 native), and the original examples rendered correctly.

**0.2 font/text layer — VISUAL SMOKE TEST CONFIRMED.** The user subsequently
rendered `examples/text.rkt` successfully on the same project setup. A complete
69-case 0.2 test transcript was not supplied in this update, so this report does
not retroactively claim full-suite validation for every 0.2 font path.

**0.3 shaders/gradients — NOT YET LIVE RUN IN THE AUTHORING ENVIRONMENT.**
This environment has no Racket executable or libSkiaSharp. The shader/gradient
changes received source, ABI, layout, ownership, installer, and documentation
checks here, but the new native calls still require the local doctor, test
suite, and visual example. The full 0.3 suite contains 77 source test cases.

## Checks performed for 0.3 source

Run `python3 tools/static-check.py` and the host-C layout command shown below to
reproduce the non-Racket checks. The checker verifies balanced source strings
and delimiters, test-suite structure/counts, explicit public exports,
documentation coverage for those exports, local module paths, installer shell
syntax, and the installer against synthetic offline archives. It does **not**
parse/expand Racket or load Skia.

The host-C mirror checks the selected ABI field sizes/offsets independently of
Racket. It does not include upstream Skia headers and does not prove Racket FFI
layout compatibility. Version 0.3 adds the 8-byte point structure to the existing
image/rectangle/sampling/PNG/font-metrics layout mirrors.

The existing font/text declarations remain covered. The new shader declarations
were compared against the pinned SkiaSharp 3.119.1 wrapper/interface for shader
reference counting, color/linear/radial/sweep/two-point-conical creation,
paint attachment/querying, image-to-shader conversion, blend shaders, tile-mode
values, point layout, and sampling arguments.

No benchmark, leak-free claim, cross-platform rendering-equivalence claim, or
full text-layout claim is made by this report.

## Run the 0.3 Racket tests locally

From the extracted root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt
```

A full run contains **77 source test cases**: 17 pure, 6 lifetime, and 54
native. Cases can contain multiple assertions, so 77 is a source-case count,
not an assertion count. The doctor now checks raster/PNG, font/simple-text, and
a linear-gradient shader smoke test.

To run only tests that do not need the native library:

```sh
"$RACKET" run-tests.rkt --pure
```

This requests the 23 pure/lifetime cases. It does not run the 54 native cases,
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

Version 0.2 added source/native cases for the font/typeface and simple-text
layer. Version 0.3 adds point-layout and gradient-option validation; shader
reference ownership through paints; color, linear, radial, sweep, conical,
image, and blend shader rasterization; tile repetition; and closed-shader
rejection.

The repeated allocation case is not a leak detector. The suite does not yet
measure native heap reclamation, validate every platform/font backend, shape
complex scripts, or test GPU resources.

### Visual smoke checks

```sh
mkdir -p output
"$RACKET" examples/circle.rkt output/circle.png
"$RACKET" examples/gallery.rkt output/gallery.png
"$RACKET" examples/text.rkt output/text.png
"$RACKET" examples/gradients.rkt output/gradients.png
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Choose fresh filenames on reruns. The gallery exercises Bézier/control
geometry, alpha overlap, clipped diagonal lines, an even-odd ring, transformed
shapes, and image sampling. The text example exercises baseline text drawing, metrics, and an outline path.
The gradients example exercises all new shader families, tiling, and shader
blending.
Inspect stop transitions, tile seams, clipping, text placement/outlines, channel
ordering, and transparent edge artifacts.

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
