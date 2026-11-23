#lang scribble/manual

@title[#:tag "skia-reference-foundations" #:style 'toc]{Foundations}

This chapter explains conventions and rules used throughout the Reference:
which numeric limits apply, how antialiasing affects pixel coverage, and how to
manage native resources.

The later sections describe native-library checks, shared caches, and memory
reports. Consult these when diagnosing installation problems or investigating
memory use.

@local-table-of-contents[]

@include-section["notation.scrbl"]
@include-section["resources.scrbl"]
@include-section["native-libraries.scrbl"]
@include-section["graphics.scrbl"]
