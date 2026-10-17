# Navigation Tutorial Sources

[navigation.scrbl](navigation.scrbl) is the reader-facing tutorial.
Models pan, zoom, coordinate conversion, and screen-sized point hit testing as pure
data.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Navigation tutorial's executable documentation examples and figure helpers.
- [model.rkt](model.rkt) — Models pan, zoom, coordinate conversion, and screen-sized point hit testing as pure data.
- [navigate.rkt](navigate.rkt) — Connects keyboard and pointer events to the zoomable tutorial canvas.
- [scene.rkt](scene.rkt) — Draws transformed model geometry while keeping editor controls in screen coordinates.
- [tests.rkt](tests.rkt) — Checks Navigation tutorial behavior with focused regression tests.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
