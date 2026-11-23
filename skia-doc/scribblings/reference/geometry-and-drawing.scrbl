#lang scribble/manual

@title[#:tag "skia-reference-geometry-drawing" #:style 'toc]{Geometry and Drawing}

A @tech{canvas} can draw common shapes directly or draw geometry that you build
and reuse. Choose the interface according to the shape and how you will use it:

@itemlist[
 @item{Use @seclink["skia-drawing"]{drawing primitives} for rectangles, circles,
       lines, and other common shapes.}
 @item{Use @seclink["skia-paths"]{paths} for custom outlines, curves, and holes,
       or to reuse the same geometry for filling, stroking, and clipping.}
 @item{Use @seclink["skia-rounded-rectangles"]{rounded-rectangle values} when
       corners need different radii or the same rounded boundary will be reused.}
 @item{Use @seclink["skia-regions"]{integer regions} to combine pixel-aligned
       areas, test containment, or define a device-pixel clip.}
 @item{Use @seclink["skia-structured-drawing"]{meshes and patches} for geometry
       with interpolated colors or texture coordinates, image grids for resizable
       borders, and atlases for sprites taken from one image.}
 @item{Use @seclink["skia-matrices"]{affine matrices} to combine and reuse
       translations, rotations, scales, and shears. Use
       @seclink["skia-projective-matrices"]{projective matrices} for perspective.}]

For document output, @tech{portable drawing} helpers provide alternatives to
selected native batch operations by drawing simpler shapes and image rectangles.

@local-table-of-contents[]

@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["rounded-rectangles.scrbl"]
@include-section["regions.scrbl"]
@include-section["structured-drawing.scrbl"]
@include-section["portable-drawing.scrbl"]
@include-section["matrices.scrbl"]
@include-section["projective-matrices.scrbl"]
