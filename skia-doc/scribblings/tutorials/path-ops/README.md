# Path Ops Tutorial Sources

[path-ops.scrbl](path-ops.scrbl) is the reader-facing tutorial.
Constructs a badge from Boolean combinations of paths and draws the operands.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [badge.rkt](badge.rkt) — Constructs a badge from Boolean combinations of paths and draws the operands.
- [eval.rkt](eval.rkt) — Runs the Path Ops tutorial's executable documentation examples and figure helpers.
- [tests.rkt](tests.rkt) — Checks Path Ops tutorial behavior with focused regression tests.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
