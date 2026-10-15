#lang scribble/manual

@title[#:tag "skia-reference-streams-pixels-codecs" #:style 'toc]{Streams, Pixels, and Codecs}

Streams move encoded bytes, while pixel descriptions and raster buffers expose
decoded image storage. Codec interfaces inspect and decode encoded image data,
including scanline and incremental decoding.

@include-section["streams.scrbl"]
@include-section["live-streams.scrbl"]
@include-section["pixel-descriptions.scrbl"]
@include-section["raster-buffers.scrbl"]
@include-section["codecs.scrbl"]
@include-section["scanline-codecs.scrbl"]
@include-section["incremental-codecs.scrbl"]
