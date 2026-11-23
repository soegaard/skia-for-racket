# Shaders Tutorial Sources

[shaders.scrbl](shaders.scrbl) is the reader-facing tutorial.
Runs the wave shader in an interactive window with animated uniforms and controls.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [eval.rkt](eval.rkt) — Runs the Shaders tutorial's executable documentation examples and figure helpers.
- [tests.rkt](tests.rkt) — Checks Shaders tutorial behavior with focused regression tests.
- [waves-window.rkt](waves-window.rkt) — Runs the wave shader in an interactive window with animated uniforms and controls.
- [waves.rkt](waves.rkt) — Defines runtime shader sources and shared drawing functions for animated waves.
- [wave-frame.png](wave-frame.png) — Committed wave-shader frame used as an example asset.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
