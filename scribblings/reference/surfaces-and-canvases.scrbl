#lang scribble/manual

@title[#:tag "skia-reference-surfaces-canvases" #:style 'toc]{Drawing Targets and Canvas State}

A surface owns a drawing target, while a canvas carries the state used to draw
into that target. Surface properties describe rendering requests, layers create
intermediate compositing targets, and specialized canvases redirect or analyze
drawing while preserving the canvas interface.

@local-table-of-contents[]

@include-section["surfaces.scrbl"]
@include-section["surface-properties.scrbl"]
@include-section["canvases.scrbl"]
@include-section["layers.scrbl"]
@include-section["specialized-canvases.scrbl"]
