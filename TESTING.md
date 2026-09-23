# Verification report — 2026-09-23

## Status

**0.1 through 0.4 — LIVE VALIDATED on macOS/aarch64.** The user ran the
completed 0.4 tree with Racket 9.3.0.2 and the pinned SkiaSharp 3.119.1 native
asset. `tools/doctor.rkt` reported ABI milestone 119.0; raster/PNG,
font/simple-text, shader/gradient, and codec smoke checks passed; all **85**
source test cases passed (19 pure, 6 lifetime, 60 native); and the codec visual
probe rendered correctly. That run necessarily exercises the earlier 0.1–0.3
regression cases as well.

**0.5 vector additions — NOT YET LIVE RUN IN THE AUTHORING ENVIRONMENT.** This
environment has no Racket executable or libSkiaSharp. The new path effects,
paint attachment/getters, path measurement, segment/tangent extraction, and
boolean PathOps received source, ABI, ownership, installer, and documentation
checks here. The full 0.5 tree contains **95 source test cases**: 21 pure, 6
lifetime, and 68 native. The 0.5 run is also intended to confirm the corrected
`paint-shader` ownership path after auditing the m119 native C shim.

## Checks performed for 0.5 source

Run `python3 tools/static-check.py` and the host-C layout command below to
reproduce the non-Racket checks. The checker verifies balanced source strings
and delimiters, test-suite structure/counts, explicit public exports,
documentation coverage, local module paths, installer shell syntax, and the
installer against synthetic offline archives. It does **not** parse/expand
Racket or load Skia.

The host-C mirror independently checks the selected ABI sizes/offsets from
0.1–0.4. Version 0.5 introduces no new by-value C structs; it reuses the 8-byte
point layout for path position/tangent output and otherwise adds pointer/scalar
callouts. The host checker does not include upstream headers and is not a
substitute for Racket FFI execution.

The new declarations were compared against the pinned SkiaSharp 3.119.1
interface and the corresponding mono/skia C shim for path-effect constructors
and release, paint path-effect attachment/getters, path-measure construction and
queries, and PathOps. The C shim was also audited directly for ownership. Both
`sk_paint_get_shader` and `sk_paint_get_path_effect` return owned references via
`ref...().release()`. This revealed and fixes a 0.3/0.4 `paint-shader` extra-ref
leak. Raw `SkPathMeasure` retains a path pointer, so the 0.5 public wrapper uses
a private native path clone whose lifetime is tied to the measure.

No benchmark, native-heap leak-measurement claim, cross-platform rendering-
equivalence claim, or GPU claim is made by this report.

## Run the 0.5 Racket tests locally

From the extracted root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt
```

A successful full run should report **21 pure + 6 lifetime + 68 native = 95
source test cases**. Cases contain multiple assertions, so this is not an
assertion count. The 0.5 doctor retains all earlier smoke checks and additionally
constructs a dash effect, measures/samples a path, attaches/gets a path effect,
and verifies a boolean path union.

To run only tests that do not need the native library:

```sh
"$RACKET" run-tests.rkt --pure
```

This requests the 27 pure/lifetime cases. It does not run the 68 native cases,
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
rejection.

The repeated allocation case is not a leak detector. The suite does not yet
measure native heap reclamation directly, expose path-measure matrices or path
iterators, validate 1D/2D stamped path effects, validate every encoded format,
decode animation frames, normalize encoded orientation, exercise ICC/color
space objects, shape complex scripts, or test GPU resources.

### Visual smoke checks

```sh
mkdir -p output
"$RACKET" examples/circle.rkt output/circle.png
"$RACKET" examples/gallery.rkt output/gallery.png
"$RACKET" examples/text.rkt output/text.png
"$RACKET" examples/gradients.rkt output/gradients.png
"$RACKET" examples/codecs.rkt output/codecs.png
"$RACKET" examples/path-effects.rkt output/path-effects.png
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Choose fresh filenames on reruns. The codecs example remains the 0.4 visual
probe. The new path-effects example has six panels for dash, corner, discrete,
trim, measured segment/tangent, and boolean path operations. Inspect effect
continuity, cap/join behavior, the highlighted measured segment and tangent,
and the expected union/intersection/xor regions.

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
