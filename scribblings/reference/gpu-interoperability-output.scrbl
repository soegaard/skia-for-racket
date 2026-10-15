#lang scribble/manual

@title[#:tag "skia-reference-gpu-interop-output"]{GPU Interoperability and Output}

These interfaces cross native GPU API boundaries or execute GPU-backed raster
output. They expose explicit OpenGL, Metal, and Direct3D integration points
without changing the ownership and context rules of the underlying resources.

@include-section["gpu-gl-interop.scrbl"]
@include-section["gpu-external-resources.scrbl"]
@include-section["gpu-native-handoffs.scrbl"]
@include-section["gpu-output.scrbl"]
