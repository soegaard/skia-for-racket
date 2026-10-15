#lang scribble/manual

@title[#:tag "skia-reference-images" #:style 'toc]{Images and Encoding}

Images are immutable pixel sources for drawing, readback, and encoding. This
part covers CPU-compatible image construction, image operations, and encoded
image output.

@local-table-of-contents[#:style 'immediate-only]

@include-section["images.scrbl"]
@include-section["image-operations.scrbl"]
@include-section["encoding.scrbl"]
