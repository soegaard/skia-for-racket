# Images Tutorial Sources

[images.scrbl](images.scrbl) is the reader-facing tutorial.
Decodes local fixtures and arranges fitted, cropped, and resampled images.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [contact-sheet.rkt](contact-sheet.rkt) — Decodes local fixtures and arranges fitted, cropped, and resampled images.
- [eval.rkt](eval.rkt) — Runs the Images tutorial's executable documentation examples and figure helpers.
- [fixtures/](fixtures/README.md) — Local encoded image inputs for the example.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
