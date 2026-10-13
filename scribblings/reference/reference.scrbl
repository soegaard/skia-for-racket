#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

This manual specifies Skia's public interfaces. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples.

@defmodule[skia]

This manual documents resource management, surfaces, canvas state, byte and
floating-point colors, color management, paints, shaders, geometric drawing,
paths, affine matrices, images, image encoding,
font managers, typefaces, fonts, shaped text, text blobs, and paragraph layout.
Text blobs include multi-run construction, run inspection, and text on paths.
The effects chapters cover path and mask effects, color and image filters,
runtime SkSL programs, and custom blenders.
Other interfaces are described in the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/API.md"]{existing API notes}.

The module @racketmodname[skia] provides the bindings documented here. Additional
public import paths are identified in the relevant chapters. In particular,
color operations are available from @racketmodname[skia/color], affine matrices
from @racketmodname[skia/matrix], and the indicated paint queries from
@racketmodname[skia/geometry]. Typeface-data operations are also available from
@racketmodname[skia/typefaces], and additional glyph queries from @racketmodname[skia/fonts].
Multi-run blob operations are available from @racketmodname[skia/text-blobs].
The atlas-transform values used for glyph placement are also exported by
@racketmodname[skia/geometry-primitives].

@table-of-contents[]

@include-section["notation.scrbl"]
@include-section["resources.scrbl"]
@include-section["surfaces.scrbl"]
@include-section["canvases.scrbl"]
@include-section["colors.scrbl"]
@include-section["color-management.scrbl"]
@include-section["float-colors.scrbl"]
@include-section["paints.scrbl"]
@include-section["shaders.scrbl"]
@include-section["path-effects.scrbl"]
@include-section["color-filters.scrbl"]
@include-section["image-filters.scrbl"]
@include-section["runtime-effects.scrbl"]
@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["matrices.scrbl"]
@include-section["images.scrbl"]
@include-section["encoding.scrbl"]
@include-section["typefaces.scrbl"]
@include-section["fonts.scrbl"]
@include-section["shaping.scrbl"]
@include-section["text-blobs.scrbl"]
@include-section["text-layout.scrbl"]

@index-section[]
