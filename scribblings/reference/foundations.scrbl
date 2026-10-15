#lang scribble/manual

@title[#:tag "skia-reference-foundations" #:style 'toc]{Foundations}

Skia combines ordinary Racket values with native resources whose validity can
depend on ownership, lifetime, thread, and native-library availability. Numeric
conventions, cleanup rules, capability checks, and process-global cache behavior
establish assumptions used throughout the API.

@local-table-of-contents[]

@include-section["notation.scrbl"]
@include-section["resources.scrbl"]
@include-section["native-libraries.scrbl"]
@include-section["graphics.scrbl"]
