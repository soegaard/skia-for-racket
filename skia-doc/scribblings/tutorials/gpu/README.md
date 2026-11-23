# GPU Tutorial Sources

[gpu.scrbl](gpu.scrbl) is the reader-facing tutorial.
Renders the shared tutorial scene to a Metal surface and saves the readback.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the GPU tutorial's executable documentation examples and figure helpers.
- [gpu-offscreen.rkt](gpu-offscreen.rkt) — Renders the shared tutorial scene to a Metal surface and saves the readback.
- [linux-opengl.rkt](linux-opengl.rkt) — Creates an explicit Racket OpenGL context to render the shared GPU tutorial scene.
- [render-scene.rkt](render-scene.rkt) — Selects a requested raster or GPU renderer for the shared tutorial scene.
- [scene.rkt](scene.rkt) — Defines the single drawing used to compare raster and GPU results.
- [figures/](figures/README.md) — Committed GPU comparison images and their provenance.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
