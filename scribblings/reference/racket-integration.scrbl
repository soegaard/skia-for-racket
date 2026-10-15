#lang scribble/manual

@(require (for-label racket/class (prefix-in draw: racket/draw)))

@title[#:tag "skia-reference-racket-integration" #:style 'toc]{Racket Integration}

Skia integrates with Racket picts, Racket Draw values, and Racket's @racket[draw:dc<%>]
drawing-context interface through explicit bridges and drawing-context
implementations.

@local-table-of-contents[]

@include-section["pict-bridge.scrbl"]
@include-section["racket-draw.scrbl"]
@include-section["racket-dc.scrbl"]
@include-section["dc-output.scrbl"]
@include-section["gpu-dc.scrbl"]
