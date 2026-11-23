# Pixels Tutorial Sources

[pixels.scrbl](pixels.scrbl) is the reader-facing tutorial.
Builds and processes padded RGBA buffers while preserving row layout and alpha.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Pixels tutorial's executable documentation examples and figure helpers.
- [pixel-lab.rkt](pixel-lab.rkt) — Builds and processes padded RGBA buffers while preserving row layout and alpha.
- [tests.rkt](tests.rkt) — Checks Pixels tutorial behavior with focused regression tests.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
