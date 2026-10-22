#lang scribble/manual

@title[#:tag "skia-reference-color-paint-effects" #:style 'toc]{Color, Paint, and Effects}

Choose a color for a solid fill, or attach a shader or effect to a paint when
the appearance needs more than a single color. The sections in this chapter
cover different parts of that process:

@itemlist[
 @item{@tech{Color specifications} supply channel values; @tech{color spaces}
       describe how to interpret them. @tech{Floating-point colors} support
       explicit source spaces and values beyond eight-bit channels.}
 @item{A @tech{paint} collects the settings used by a drawing operation, including
       its color, stroke, effects, and @tech{blend mode}.}
 @item{A @tech{shader} supplies colors across the shape, for example from a
       gradient or image.}
 @item{@tech{Path effects} change the geometry being drawn; @tech{mask filters}
       change its coverage.}
 @item{@tech{Color filters} transform individual colors. @tech{Image filters}
       can also use neighboring pixels for effects such as blur and shadows.}
 @item{@tech{Runtime effects} provide custom color calculations for shaders,
       color filters, and @tech{blenders} when the built-in operations are
       insufficient.}]

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
