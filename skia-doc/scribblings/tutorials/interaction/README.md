# Interaction Tutorial Sources

[interaction.scrbl](interaction.scrbl) is the reader-facing tutorial.
Connects pointer events to a draggable cubic-curve editor with explicit renderer
choice.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [bezier-editor.rkt](bezier-editor.rkt) — Connects pointer events to a draggable cubic-curve editor with explicit renderer choice.
- [eval.rkt](eval.rkt) — Runs the Interaction tutorial's executable documentation examples and figure helpers.
- [scene.rkt](scene.rkt) — Defines editable control points, hit testing, and the shared curve-editor drawing.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
