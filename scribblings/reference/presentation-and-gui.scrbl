#lang scribble/manual

@title[#:tag "skia-reference-presentation-gui" #:style 'toc]{Presentation and GUI}

Presentation connects rendered content to Racket GUI windows. Presenter
frames expose short-lived GPU canvases, raw GPU widgets schedule those frames,
drawing-canvas adapters supply Racket drawing contexts, and the unified
render-canvas layer selects a raster or GPU implementation behind one callback
protocol.

@local-table-of-contents[]

@include-section["gpu-presentation.scrbl"]
@include-section["gpu-widgets.scrbl"]
@include-section["gui-canvases.scrbl"]
@include-section["render-canvases.scrbl"]
