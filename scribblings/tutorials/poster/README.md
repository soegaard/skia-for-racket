# Poster Tutorial Sources

[poster.scrbl](poster.scrbl) is the reader-facing tutorial.
Builds a poster from gradients, image shaders, transparency, and blending.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Poster tutorial's executable documentation examples and figure helpers.
- [poster.rkt](poster.rkt) — Builds a poster from gradients, image shaders, transparency, and blending.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
