#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

@defmodule[skia]

@para{@bold{About Skia}}

@hyperlink["https://skia.org/"]{Skia} is an open-source 2D graphics library
sponsored and managed by Google. It provides a common graphics API across
software and hardware platforms and is used by projects including Chrome,
Android, and Flutter.

The Skia package for Racket is an independent interface to the upstream Skia
graphics library. It provides CPU raster drawing, paths and geometry, images,
text and shaping, effects, PDF and SVG output, and optional GPU and GUI
integration. The public interface is designed for Racket rather than as a
one-for-one transcription of the native API. In this manual, @italic{Skia}
normally means the Racket package; @italic{upstream Skia} means the graphics
library maintained by the Skia project.

@para{@bold{SkiaSharp and Other Upstream Projects}}

The native interface used by this package is the C ABI maintained and
distributed by @hyperlink["https://github.com/mono/SkiaSharp"]{SkiaSharp}.
SkiaSharp is a cross-platform .NET binding to upstream Skia, but the Racket
package does not use its managed .NET API. It calls the native C ABI exported
by the SkiaSharp native libraries and uses SkiaSharp native-assets packages to
obtain supported native binaries. This project therefore owes a substantial
debt to SkiaSharp for maintaining that native interface and its cross-platform
distribution.

Text shaping uses @hyperlink["https://harfbuzz.github.io/"]{HarfBuzz}, and the
text-layout implementation includes derived Unicode data for bidirectional
text, line breaking, and Arabic joining. The exact upstream sources and pinned
compatibility references are recorded in
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/SOURCES.md"]{Primary sources used}.

@para{@bold{Development and AI Assistance}}

OpenAI Codex has been used extensively in the development of this package,
including implementation, tests, documentation, and technical review. Codex
output is treated as proposed work rather than as an authority: accepted
changes are reviewed against the implementation, the test suites, CI and host
validation, and the pinned upstream interfaces. AI-generated output by itself
is not evidence of API behavior or compatibility.

@para{@bold{License and Third-Party Software}}

The Racket source in this project is released under the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/LICENSE"]{MIT License}.
That license does not relicense upstream Skia, SkiaSharp native packages,
HarfBuzz, Unicode data, or other third-party components. The source
distribution contains no native library or font files; the explicit native
installer downloads pinned SkiaSharp native-assets packages separately. Those
packages include upstream Skia and other third-party components under their
own licenses. See the repository's
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/NOTICE.md"]{third-party notice}
before redistributing a bundle that includes native binaries or derived data.

@para{@bold{Project Status and Documentation}}

The Skia package is experimental. It is an independent project and is not
affiliated with, endorsed by, or an official binding of the upstream Skia,
SkiaSharp, or Racket projects. The reviewed public API distinguishes stable and
experimental interfaces; @secref["skia-notation"] describes the Reference
conventions and stability policy.

This manual specifies the public API, including argument and result contracts,
resource lifetimes, and failure behavior. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples. The @racketmodname[skia] library
provides the core drawing interface; individual parts and chapters identify
additional public import paths.

@para{@bold{Detailed Contents}}

@local-table-of-contents[]

@include-section["foundations.scrbl"]
@include-section["surfaces-and-canvases.scrbl"]
@include-section["color-paint-effects.scrbl"]
@include-section["geometry-and-drawing.scrbl"]
@include-section["image-api.scrbl"]
@include-section["text-and-fonts.scrbl"]
@include-section["recording.scrbl"]
@include-section["documents-and-output.scrbl"]
@include-section["streams-pixels-codecs.scrbl"]
@include-section["gpu-rendering.scrbl"]
@include-section["gpu-interoperability-output.scrbl"]
@include-section["presentation-and-gui.scrbl"]
@include-section["racket-integration.scrbl"]

@index-section[]
