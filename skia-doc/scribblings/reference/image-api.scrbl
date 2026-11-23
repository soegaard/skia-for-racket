#lang scribble/manual

@title[#:tag "skia-reference-images" #:style 'toc]{Images and Encoding}

Images provide pixels that you can draw repeatedly without changing the
original image. @secref["skia-images"] covers loading images, constructing them
from raw pixels, drawing them, and inspecting their properties.

Use @secref["skia-image-operations"] when you need to prepare pixels in CPU
memory, copy them into editable storage, or create a filtered image. For PNG,
JPEG, or WebP byte strings and files, see @secref["skia-encoding"].

@local-table-of-contents[]

@include-section["images.scrbl"]
@include-section["image-operations.scrbl"]
@include-section["encoding.scrbl"]
