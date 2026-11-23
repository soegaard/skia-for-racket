# Tutorial Sources

[index.scrbl](index.scrbl) assembles the tutorial catalog, subject categories,
suggested reading routes, and instructions for running complete examples.
Categories answer what a reader wants to learn; reading routes are separate,
possibly overlapping sequences. Their metadata lives in
[support/catalog.json](support/catalog.json).

Each subject folder contains its manual, the complete drawing program or shared
scene/model, and evaluator helpers for executable documentation. Programs that
open windows or write images should be run deliberately using their manual's
instructions, not loaded as a bulk smoke test.

The [Quick introduction](../quick/README.md) lives beside this directory.
[Shared support](support/README.md) supplies catalog lookup, source copying,
figure presentation, and reusable sprite-tutorial helpers.

## Checks and Developer Entry Points

- [reader-test.rkt](reader-test.rkt) checks source copying and reader navigation.
- [registration-test.rkt](registration-test.rkt) checks manual registration
  against catalog identities.
- The `check-3*.py`, [check-16-20.py](check-16-20.py), and
  [check-21-22.py](check-21-22.py) scripts validate source/manual conventions
  and selected tutorial groups; matching `test-check-*.py` files test the checkers.
- [pages-index.html](pages-index.html) is an HTML publication index associated
  with the tutorials; it is not the authoritative subject/route catalog.

See [Tutorial Guidelines](../../docs/TUTORIAL-GUIDELINES.md) for editorial and
figure-generation expectations.

## Subject Folders
- [Animation](animation/README.md) — Runs an animated window whose scene is shared by raster and GPU renderers.
- [Clock](clock/README.md) — Draws a clock by composing local coordinate systems and canvas transforms.
- [Color Spaces](color-spaces/README.md) — Builds paired images that distinguish color-space tagging from sample conversion.
- [Effects](effects/README.md) — Draws a card with shadows, blurred accents, and composed visual effects.
- [GPU](gpu/README.md) — Renders the shared tutorial scene to a Metal surface and saves the readback.
- [Images](images/README.md) — Decodes local fixtures and arranges fitted, cropped, and resampled images.
- [Interaction](interaction/README.md) — Connects pointer events to a draggable cubic-curve editor with explicit renderer choice.
- [Logo](logo/README.md) — Builds a logo from path commands and saves raster and vector versions.
- [Navigation](navigation/README.md) — Models pan, zoom, coordinate conversion, and screen-sized point hit testing as pure data.
- [Paragraph](paragraph/README.md) — Lays out a multilingual article card using paragraph shaping and layout.
- [Path Ops](path-ops/README.md) — Constructs a badge from Boolean combinations of paths and draws the operands.
- [PDF SVG](pdf-svg/README.md) — Draws a printable geometric construction in millimeter-based page coordinates.
- [Pictures](pictures/README.md) — Records an emblem once and replays it at different positions, scales, and rotations.
- [Pixels](pixels/README.md) — Builds and processes padded RGBA buffers while preserving row layout and alpha.
- [Poster](poster/README.md) — Builds a poster from gradients, image shaders, transparency, and blending.
- [Shaders](shaders/README.md) — Runs the wave shader in an interactive window with animated uniforms and controls.
- [Shaping](shaping/README.md) — Builds a multilingual specimen using suitable fonts and shaped runs.
- [Sprites](sprites/README.md) — Draws the original ball artwork into a padded CPU sprite atlas.
- [Squadron](squadron/README.md) — Draws original ship, enemy, projectile, and explosion artwork into an atlas.
- [Text](text/README.md) — Builds a type specimen that makes baseline, advance, and font metrics visible.
- [Vector Raster](vector-raster/README.md) — Supports the corresponding tutorial's complete drawing program.
