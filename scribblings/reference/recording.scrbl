#lang scribble/manual

@title[#:tag "skia-reference-recording" #:style 'toc]{Recording}

Pictures record canvas commands and retained drawing data. Recorded drawables
capture that content for retained or immediate playback. Neither representation
reruns the Racket function that originally produced the drawing.

@local-table-of-contents[]

@include-section["pictures.scrbl"]
@include-section["drawables.scrbl"]
