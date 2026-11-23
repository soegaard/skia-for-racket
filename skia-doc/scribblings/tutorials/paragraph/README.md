# Paragraph Tutorial Sources

[paragraph.scrbl](paragraph.scrbl) is the reader-facing tutorial.
Lays out a multilingual article card using paragraph shaping and layout.
This folder keeps the explanation, executable example, and generated-figure
helpers together. The [tutorial catalog](../support/catalog.json) records the
complete source set and commands for installed-package copying.


## Files

- [article-card.rkt](article-card.rkt) — Lays out a multilingual article card using paragraph shaping and layout.
- [eval.rkt](eval.rkt) — Runs the Paragraph tutorial's executable documentation examples and figure helpers.

## Using This Source

Read the manual for the intended execution command and supported renderer.
The complete program may write output files or open a window; evaluator modules
are documentation-build helpers, not alternate application entry points.
Tests named `native-test.rkt` or tests requiring `skia` need the native library;
pure model tests do not initialize the GPU.
