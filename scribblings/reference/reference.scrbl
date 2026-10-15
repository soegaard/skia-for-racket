#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

This manual specifies the Skia API, including argument and result contracts,
resource lifetimes, and failure behavior. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples.

@defmodule[skia]

The @racketmodname[skia] library provides the core drawing interface. Individual
parts and chapters identify additional public import paths.

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
