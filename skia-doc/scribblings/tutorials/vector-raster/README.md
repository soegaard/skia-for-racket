# Vector Raster Tutorial Sources

[vector-raster.scrbl](vector-raster.scrbl) is the reader-facing tutorial.
Supports the corresponding tutorial's complete drawing program.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Vector Raster tutorial's executable documentation examples and figure helpers.
- [vector-raster.rkt](vector-raster.rkt) — Supports the corresponding tutorial's complete drawing program.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
