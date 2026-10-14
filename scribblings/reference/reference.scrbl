#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

This manual specifies the Skia API, including argument and result contracts,
resource lifetimes, and failure behavior. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples.

@defmodule[skia]

The @racketmodname[skia] module provides the core drawing interface. Individual
chapters identify additional public import paths. Interfaces not yet covered by
this manual are described in the
@hyperlink["https://github.com/soegaard/skia-for-racket/blob/main/docs/API.md"]{API notes}.

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

@include-section["pictures.scrbl"]
@include-section["pdf-documents.scrbl"]
@include-section["svg-documents.scrbl"]
@include-section["output-pages.scrbl"]
@include-section["annotations.scrbl"]

@include-section["streams.scrbl"]
@include-section["live-streams.scrbl"]
@include-section["pixel-descriptions.scrbl"]
@include-section["codecs.scrbl"]
@include-section["scanline-codecs.scrbl"]
@include-section["incremental-codecs.scrbl"]

@index-section[]
