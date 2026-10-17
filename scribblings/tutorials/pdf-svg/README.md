# PDF SVG Tutorial Sources

[pdf-svg.scrbl](pdf-svg.scrbl) is the reader-facing tutorial.
Draws a printable geometric construction in millimeter-based page coordinates.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the PDF SVG tutorial's executable documentation examples and figure helpers.
- [geometry-diagram.rkt](geometry-diagram.rkt) — Draws a printable geometric construction in millimeter-based page coordinates.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
