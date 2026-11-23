# Animation Tutorial Sources

[animation.scrbl](animation.scrbl) is the reader-facing tutorial.
Runs an animated window whose scene is shared by raster and GPU renderers.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Animation tutorial's executable documentation examples and figure helpers.
- [orbiting-lights.rkt](orbiting-lights.rkt) — Runs an animated window whose scene is shared by raster and GPU renderers.
- [scene.rkt](scene.rkt) — Draws orbiting lights from explicit time and dimensions, independently of window events.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
