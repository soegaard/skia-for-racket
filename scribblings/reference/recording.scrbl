#lang scribble/manual

@title[#:tag "skia-reference-recording" #:style 'toc]{Recording}

Pictures record drawing commands and the data needed to replay them. Recorded
drawables can be referenced by another recording or replay their commands
immediately into a canvas. Neither representation reruns the Racket function
that originally produced the drawing.

@local-table-of-contents[]

@include-section["pictures.scrbl"]
@include-section["drawables.scrbl"]
