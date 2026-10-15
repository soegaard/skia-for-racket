#lang scribble/manual

@title[#:tag "skia-reference-presentation-gui" #:style 'toc]{Presentation and GUI}

Presentation APIs connect rendered content to Racket GUI windows. They provide
GPU presenters and widgets together with persistent raster canvases and a
renderer-selecting canvas interface.

@include-section["gpu-presentation.scrbl"]
@include-section["gpu-widgets.scrbl"]
@include-section["gui-canvases.scrbl"]
@include-section["render-canvases.scrbl"]
