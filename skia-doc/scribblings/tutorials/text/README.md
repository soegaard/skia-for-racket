# Text Tutorial Sources

[text.scrbl](text.scrbl) is the reader-facing tutorial.
Builds a type specimen that makes baseline, advance, and font metrics visible.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Text tutorial's executable documentation examples and figure helpers.
- [type-specimen.rkt](type-specimen.rkt) — Builds a type specimen that makes baseline, advance, and font metrics visible.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
