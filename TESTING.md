# Verification report — 2026-09-23

## Status

**0.1 through 0.5 — LIVE VALIDATED on macOS/aarch64.** The user ran the
completed 0.5 tree with Racket 9.3.0.2 and the pinned SkiaSharp 3.119.1 native
asset. `tools/doctor.rkt` reported ABI milestone 119.0; raster/PNG,
font/simple-text, shader/gradient, codec, and path-effects/measurement smoke
checks passed; all **95** source test cases passed (21 pure, 6 lifetime, 68
native); and the path-effects visual probe rendered correctly. That run also
confirmed the corrected `paint-shader` getter ownership path.

**0.6 filters/effects — NOT YET LIVE RUN IN THE AUTHORING ENVIRONMENT.** This
environment has no Racket executable or libSkiaSharp. The new color, mask, and
image filter resources, paint attachment/getters, filter composition, and
raster probes received source, ABI, ownership, installer, and documentation
checks here. The full 0.6 tree contains **105 source test cases**: 23 pure, 6
lifetime, and 76 native.

## Checks performed for 0.6 source

Run `python3 tools/static-check.py` and the host-C layout command below to
reproduce the non-Racket checks. The checker verifies balanced source strings
and delimiters, test-suite structure/counts, explicit public exports,
documentation coverage, local module paths, installer shell syntax, and the
installer against synthetic offline archives. It does **not** parse/expand
Racket or load Skia.

The host-C mirror independently checks the selected ABI sizes/offsets from
0.1–0.5. Version 0.6 introduces no new by-value C structs; its filter APIs add
pointer/scalar callouts plus temporary 20-float color-matrix storage. The host
checker does not include upstream headers and is not a substitute for Racket FFI
execution.

The new declarations were compared against the pinned SkiaSharp 3.119.1
interface and the corresponding mono/skia C shims for color filters, blur mask
filters, image filters, and paint attachment/getters. The paint getters use
`ref...().release()` and therefore return one owned native reference. Paint
setters and composed filter constructors retain their inputs with native
reference counting. The pinned m119 image-blur documentation explicitly marks
mirror tiling unsupported; the public wrapper rejects that mode for this
constructor instead of promising undefined behavior.

No benchmark, native-heap leak-measurement claim, cross-platform rendering-
equivalence claim, or GPU claim is made by this report.

## Run the 0.6 Racket tests locally

From the extracted root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
bash tools/audit-symbols.sh
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt
```

A successful full run should report **23 pure + 6 lifetime + 76 native = 105
source test cases**. Cases contain multiple assertions, so this is not an
assertion count. The 0.6 doctor retains all earlier smoke checks and additionally
rasterizes a color matrix filter and verifies owned mask/image-filter paint
attachments.

To run only tests that do not need the native library:

```sh
"$RACKET" run-tests.rkt --pure
```

This requests the 29 pure/lifetime cases. It does not run the 76 native cases,
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

The repeated allocation case is not a leak detector. The suite does not yet
measure native heap reclamation directly, expose path-measure matrices or path
iterators, validate 1D/2D stamped path effects, validate every encoded format,
decode animation frames, normalize encoded orientation, exercise ICC/color
space objects, expose advanced filter families/crop rectangles, shape complex
scripts, or test GPU resources.

### Visual smoke checks

```sh
mkdir -p output
"$RACKET" examples/circle.rkt output/circle.png
"$RACKET" examples/gallery.rkt output/gallery.png
"$RACKET" examples/text.rkt output/text.png
"$RACKET" examples/gradients.rkt output/gradients.png
"$RACKET" examples/codecs.rkt output/codecs.png
"$RACKET" examples/path-effects.rkt output/path-effects.png
"$RACKET" examples/filters.rkt output/filters.png
"$RACKET" examples/pictures.rkt output/pictures.png
"$RACKET" examples/svg-paths.rkt output/svg-paths.png
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Choose fresh filenames on reruns. The new `filters.rkt` probe has six panels for
a color matrix, blend color filter, mask blur, image blur, drop shadow, and a
composed image-filter graph. Inspect channel transforms, blur falloff, shadow
offset/source inclusion, clipping, and any unexpected seams or transparency.

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


Expected additional doctor line for 0.7:

```text
Pictures/recording passed; recording, replay, and rasterization verified
```


Expected additional doctor line for 0.8:

```text
Paths/SVG passed; relative commands, SVG conversion, and point queries verified
```


Before native doctor/test runs, `bash tools/audit-symbols.sh` should report zero missing required symbols. This is especially important after adding FFI bindings.
