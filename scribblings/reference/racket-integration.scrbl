#lang scribble/manual

@(require (for-label racket/class (prefix-in draw: racket/draw)))

@title[#:tag "skia-reference-racket-integration" #:style 'toc]{Racket Integration}

Racket integration is explicit. Value bridges copy Skia content into picts or
copy selected values between Skia and Racket Draw. Drawing-context adapters
implement Racket's @racket[draw:dc<%>] interface over CPU, document, and GPU
targets. These libraries complement the native Skia canvas API rather than
replacing it.

@local-table-of-contents[]

@include-section["pict-bridge.scrbl"]
@include-section["racket-draw.scrbl"]
@include-section["racket-dc.scrbl"]
@include-section["dc-output.scrbl"]
@include-section["gpu-dc.scrbl"]
