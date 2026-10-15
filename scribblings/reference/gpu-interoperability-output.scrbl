#lang scribble/manual

@title[#:tag "skia-reference-gpu-interop-output" #:style 'toc]{Native GPU Interoperability}

Native GPU interoperability crosses the boundary between Skia-owned GPU work
and host-owned OpenGL, Metal, or Direct3D resources. OpenGL handoffs operate
within the active host context. External-texture tokens provide a single-use
safe boundary, while the Metal and Direct3D constructors accept raw native
pointers through explicitly unsafe libraries. None of these interfaces relaxes
the ownership, context, synchronization, or thread rules of the resources
involved.

@local-table-of-contents[]

@include-section["gpu-gl-interop.scrbl"]
@include-section["gpu-external-resources.scrbl"]
@include-section["gpu-native-handoffs.scrbl"]
