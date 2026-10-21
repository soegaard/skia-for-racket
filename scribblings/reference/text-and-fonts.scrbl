#lang scribble/manual

@title[#:tag "skia-reference-text-fonts" #:style 'toc]{Text and Fonts}

@tech{Font managers} and typefaces select glyph designs; fonts add size and rendering
settings. @tech{Shaping} produces positioned glyph runs, @tech{text blobs} store reusable
glyph placement, and @tech{text layout} arranges runs into lines.

@local-table-of-contents[]

@include-section["typefaces.scrbl"]
@include-section["fonts.scrbl"]
@include-section["shaping.scrbl"]
@include-section["text-blobs.scrbl"]
@include-section["text-layout.scrbl"]
