#lang scribble/manual

@title[#:tag "skia-reference-streams-pixels-codecs" #:style 'toc]{Streams, Pixels, and Codecs}

@tech{Native streams} are Skia-owned byte sources and sinks; buffered and live adapters
connect them to Racket ports with different I/O and lifetime guarantees. @tech{Pixel
descriptions} specify raster storage layouts, while @tech{raster buffers} own mutable
CPU pixels. @tech{Codec} interfaces inspect and decode encoded image data either as complete
frames, by scanline, or incrementally.

@local-table-of-contents[]

@include-section["streams.scrbl"]
@include-section["live-streams.scrbl"]
@include-section["pixel-descriptions.scrbl"]
@include-section["raster-buffers.scrbl"]
@include-section["codecs.scrbl"]
@include-section["scanline-codecs.scrbl"]
@include-section["incremental-codecs.scrbl"]
