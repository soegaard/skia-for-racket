#lang scribble/manual

@title[#:tag "skia-reference-geometry-drawing"]{Geometry and Drawing}

Canvases draw primitive geometry directly and can consume reusable paths,
regions, meshes, image grids, and coordinate transformations. Portable drawing
helpers lower selected operations to more widely supported primitives.

@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["rounded-rectangles.scrbl"]
@include-section["regions.scrbl"]
@include-section["structured-drawing.scrbl"]
@include-section["portable-drawing.scrbl"]
@include-section["matrices.scrbl"]
@include-section["projective-matrices.scrbl"]
