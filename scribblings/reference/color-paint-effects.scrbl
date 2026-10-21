#lang scribble/manual

@title[#:tag "skia-reference-color-paint-effects" #:style 'toc]{Color, Paint, and Effects}

Colors and @tech{color spaces} describe channel values and their interpretation.
Paints combine colors with shaders, @tech{blend modes}, @tech{path effects}, and filters to
determine how drawing is rendered. @tech{Runtime effects} provide programmable
shaders, color filters, and blenders.

@local-table-of-contents[]

@include-section["colors.scrbl"]
@include-section["color-management.scrbl"]
@include-section["float-colors.scrbl"]
@include-section["paints.scrbl"]
@include-section["shaders.scrbl"]
@include-section["path-effects.scrbl"]
@include-section["color-filters.scrbl"]
@include-section["image-filters.scrbl"]
@include-section["runtime-effects.scrbl"]
