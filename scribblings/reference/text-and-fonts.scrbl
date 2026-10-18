#lang scribble/manual

@title[#:tag "skia-reference-text-fonts" #:style 'toc]{Text and Fonts}

Font managers and typefaces select glyph designs; fonts add size and rendering
settings. Shaping produces positioned glyph runs, text blobs store reusable
glyph placement, and text layout arranges runs into lines.

@local-table-of-contents[]

@include-section["typefaces.scrbl"]
@include-section["fonts.scrbl"]
@include-section["shaping.scrbl"]
@include-section["text-blobs.scrbl"]
@include-section["text-layout.scrbl"]
