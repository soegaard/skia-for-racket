# Changelog

## 0.2.0 — 2026-09-23

Adds the first standalone font and text layer: default, family, and file-backed
`typeface?` resources; configurable `font?` resources; font metrics; UTF-8
simple-text drawing and measurement; character/text-to-glyph mapping; and glyph
or simple-text outline paths. The ABI layer now includes the pinned SkiaSharp
font/typeface/string calls and the 64-byte `SKFontMetrics` layout. The doctor,
tests, example set, API reference, and ABI notes are extended accordingly.

The 0.2.0 source changes were statically checked in the authoring environment,
but its new native font/text paths were not executed there because Racket and
libSkiaSharp were unavailable. See `TESTING.md` for the exact distinction
between the previously live-validated 0.1 baseline and the new 0.2 checks.

## 0.1.0 — 2026-09-23

Initial standalone CPU Skia binding using the SkiaSharp 3.119.1 native C ABI.
Adds resource ownership, drawing primitives, paths, clipping/transforms, image
snapshots and copied pixel input, native PNG output, a bitmap bridge, a native
installer/doctor, documentation, and tests.

The 0.1.0 baseline was subsequently validated on macOS/aarch64 with Racket
9.3.0.2 and the pinned native asset: doctor passed, all 57 source test cases
passed, and the circle, gallery, and bitmap-bridge examples rendered correctly.
