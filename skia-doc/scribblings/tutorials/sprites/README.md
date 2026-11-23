# Sprites Tutorial Sources

[sprites.scrbl](sprites.scrbl) is the reader-facing tutorial.
Draws the original ball artwork into a padded CPU sprite atlas.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [atlas.rkt](atlas.rkt) — Draws the original ball artwork into a padded CPU sprite atlas.
- [balls.rkt](balls.rkt) — Starts the bouncing-ball tutorial through the shared sprite window host.
- [eval.rkt](eval.rkt) — Runs the Sprites tutorial's executable documentation examples and figure helpers.
- [initial-bounds-test.rkt](initial-bounds-test.rkt) — Checks Sprites tutorial behavior with focused regression tests.
- [model-test.rkt](model-test.rkt) — Checks Sprites tutorial behavior with focused regression tests.
- [model.rkt](model.rkt) — Simulates reproducible bouncing balls without drawing or GPU resources.
- [native-test.rkt](native-test.rkt) — Checks Sprites tutorial behavior with native rendering tests.
- [scene.rkt](scene.rkt) — Converts ball state into atlas transforms and draws the batched sprites.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
