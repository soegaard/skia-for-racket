#lang scribble/manual

@title[#:tag "skia-reference-gpu-rendering"]{GPU Contexts and Resources}

GPU rendering uses a backend provider to create a context that owns GPU-side
state and resources. This part covers context configuration, GPU surfaces and
images, transfers, synchronization, caches, and diagnostics.

@include-section["gpu-providers.scrbl"]
@include-section["gpu-context-options.scrbl"]
@include-section["gpu-contexts.scrbl"]
@include-section["gpu-opengl-hosts.scrbl"]
@include-section["gpu-surfaces.scrbl"]
@include-section["gpu-images.scrbl"]
@include-section["gpu-transfers.scrbl"]
@include-section["gpu-synchronization.scrbl"]
@include-section["gpu-diagnostics.scrbl"]
