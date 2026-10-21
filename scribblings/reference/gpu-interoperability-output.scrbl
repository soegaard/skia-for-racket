#lang scribble/manual

@title[#:tag "skia-reference-gpu-interop-output" #:style 'toc]{Native GPU Interoperability}

This chapter covers advanced integration with an application that already uses
OpenGL, Metal, or Direct3D. It describes how Skia can work with that
application's native GPU commands or resources.

Most programs do not need this chapter. To draw only with Skia, start with
@seclink["skia-reference-gpu-rendering"]{GPU Contexts and Resources}. For a
Racket GUI window, continue with
@seclink["skia-reference-presentation-gui"]{Presentation and GUI}. Read this
chapter only when another library or engine already owns GPU commands, a
context, or a texture that you need to exchange with Skia.

@local-table-of-contents[]

@include-section["gpu-gl-interop.scrbl"]
@include-section["gpu-external-resources.scrbl"]
@include-section["gpu-native-handoffs.scrbl"]
