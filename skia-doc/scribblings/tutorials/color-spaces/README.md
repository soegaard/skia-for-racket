# Color Spaces Tutorial Sources

[color-spaces.scrbl](color-spaces.scrbl) is the reader-facing tutorial.
Builds paired images that distinguish color-space tagging from sample conversion.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [color-study.rkt](color-study.rkt) — Builds paired images that distinguish color-space tagging from sample conversion.
- [eval.rkt](eval.rkt) — Runs the Color Spaces tutorial's executable documentation examples and figure helpers.
- [tests.rkt](tests.rkt) — Checks Color Spaces tutorial behavior with focused regression tests.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
