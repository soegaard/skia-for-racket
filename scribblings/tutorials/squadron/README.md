# Squadron Tutorial Sources

[squadron.scrbl](squadron.scrbl) is the reader-facing tutorial.
Draws original ship, enemy, projectile, and explosion artwork into an atlas.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [atlas.rkt](atlas.rkt) — Draws original ship, enemy, projectile, and explosion artwork into an atlas.
- [eval.rkt](eval.rkt) — Runs the Squadron tutorial's executable documentation examples and figure helpers.
- [model-test.rkt](model-test.rkt) — Checks Squadron tutorial behavior with focused regression tests.
- [model.rkt](model.rkt) — Implements deterministic fixed-step movement, collisions, scoring, and game-state changes.
- [native-test.rkt](native-test.rkt) — Checks Squadron tutorial behavior with native rendering tests.
- [scene.rkt](scene.rkt) — Converts game state into atlas placements and draws the playfield and status display.
- [squadron.rkt](squadron.rkt) — Starts Star Squadron through the shared sprite window host.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
