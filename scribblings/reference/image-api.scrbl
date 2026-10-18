#lang scribble/manual

@title[#:tag "skia-reference-images" #:style 'toc]{Images and Encoding}

Images are immutable pixel sources for drawing and readback. CPU-compatible
operations inspect, copy, or make their pixels available in CPU memory, while
encoding functions produce PNG, JPEG, or WebP data and files.

@local-table-of-contents[]

@include-section["images.scrbl"]
@include-section["image-operations.scrbl"]
@include-section["encoding.scrbl"]
