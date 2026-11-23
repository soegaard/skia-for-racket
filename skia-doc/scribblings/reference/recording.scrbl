#lang scribble/manual

@title[#:tag "skia-reference-recording" #:style 'toc]{Recording}

Use a @tech{picture} to record drawing commands once and replay them at different
positions or scales. Pictures are the usual choice for reusable artwork.
@tech{Recorded drawables} add a choice when drawing into another recording:
store a reference to the drawable or replay its commands into that recording.
Neither representation reruns the Racket function that originally produced the drawing.

@local-table-of-contents[]

@include-section["pictures.scrbl"]
@include-section["drawables.scrbl"]
