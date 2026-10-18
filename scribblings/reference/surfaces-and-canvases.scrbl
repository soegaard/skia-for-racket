#lang scribble/manual

@title[#:tag "skia-reference-surfaces-canvases" #:style 'toc]{Drawing Targets and Canvas State}

A @tech{surface} stores pixels, and its @tech{canvas} provides operations for
drawing into it. This chapter also covers saving and restoring canvas state,
applying effects to groups of drawing operations, and sending drawing to
specialized targets.

@local-table-of-contents[]

@include-section["surfaces.scrbl"]
@include-section["canvases.scrbl"]
@include-section["layers.scrbl"]
@include-section["specialized-canvases.scrbl"]
