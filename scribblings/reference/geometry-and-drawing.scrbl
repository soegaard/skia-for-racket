#lang scribble/manual

@title[#:tag "skia-reference-geometry-drawing" #:style 'toc]{Geometry and Drawing}

Canvases draw primitive geometry directly and can consume reusable paths,
@tech[#:key "integer region"]{regions}, meshes, @tech[#:key "cubic patch"]{cubic patches},
image grids, and coordinate transformations.
Portable drawing helpers express selected operations using more widely supported
drawing primitives.

@local-table-of-contents[]

@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["rounded-rectangles.scrbl"]
@include-section["regions.scrbl"]
@include-section["structured-drawing.scrbl"]
@include-section["portable-drawing.scrbl"]
@include-section["matrices.scrbl"]
@include-section["projective-matrices.scrbl"]
