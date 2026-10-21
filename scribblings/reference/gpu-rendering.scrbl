#lang scribble/manual

@title[#:tag "skia-reference-gpu-rendering" #:style 'toc]{GPU Contexts and Resources}

Backend declarations, providers, and context options describe how @tech{GPU contexts}
are created. A live context establishes the owner-thread execution scope for @tech{GPU
surfaces} and images. Surface properties describe rendering settings supplied
when creating GPU surfaces. Transfer, synchronization, cache, and diagnostic
operations make movement and execution boundaries explicit.

@local-table-of-contents[]

@include-section["gpu-providers.scrbl"]
@include-section["gpu-context-options.scrbl"]
@include-section["gpu-contexts.scrbl"]
@include-section["gpu-opengl-hosts.scrbl"]
@include-section["gpu-surfaces.scrbl"]
@include-section["surface-properties.scrbl"]
@include-section["gpu-images.scrbl"]
@include-section["gpu-transfers.scrbl"]
@include-section["gpu-synchronization.scrbl"]
@include-section["gpu-diagnostics.scrbl"]
