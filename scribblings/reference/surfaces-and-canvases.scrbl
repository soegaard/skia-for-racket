#lang scribble/manual

@title[#:tag "skia-reference-surfaces-canvases" #:style 'toc]{Drawing Targets and Canvas State}

A surface owns a drawing target, while a canvas carries the state used to draw
into a target. This part covers CPU surfaces, surface properties, canvas state,
layers, and specialized canvases.

@local-table-of-contents[#:style 'immediate-only]

@include-section["surfaces.scrbl"]
@include-section["surface-properties.scrbl"]
@include-section["canvases.scrbl"]
@include-section["layers.scrbl"]
@include-section["specialized-canvases.scrbl"]
