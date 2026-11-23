# Effects Tutorial Sources

[effects.scrbl](effects.scrbl) is the reader-facing tutorial.
Draws a card with shadows, blurred accents, and composed visual effects.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [card-with-shadows.rkt](card-with-shadows.rkt) — Draws a card with shadows, blurred accents, and composed visual effects.
- [eval.rkt](eval.rkt) — Runs the Effects tutorial's executable documentation examples and figure helpers.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
