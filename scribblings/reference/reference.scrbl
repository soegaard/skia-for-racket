#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

This manual specifies Skia's public interfaces. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples.

@defmodule[skia]

This manual documents resource management, surfaces, canvas state, colors, paints,
shaders, geometric drawing, paths, affine matrices, images, and image encoding.
Other interfaces are described in the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/API.md"]{existing API notes}.

The module @racketmodname[skia] provides the bindings documented here. Additional
public import paths are identified in the relevant chapters. In particular,
color operations are available from @racketmodname[skia/color], affine matrices
from @racketmodname[skia/matrix], and the indicated paint queries from
@racketmodname[skia/geometry].

@table-of-contents[]

@include-section["notation.scrbl"]
@include-section["resources.scrbl"]
@include-section["surfaces.scrbl"]
@include-section["canvases.scrbl"]
@include-section["colors.scrbl"]
@include-section["paints.scrbl"]
@include-section["shaders.scrbl"]
@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["matrices.scrbl"]
@include-section["images.scrbl"]
@include-section["encoding.scrbl"]

@index-section[]
