#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/geometry))

@title[#:tag "skia-reference"]{The Skia Reference}

This manual specifies the Skia API, including argument and result contracts,
resource lifetimes, and failure behavior. The
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/index.scrbl")]{Skia tutorials}
introduce drawing through complete examples.

@defmodule[skia]

The @racketmodname[skia] module provides the core drawing interface. Individual
chapters identify additional public import paths.

@table-of-contents[]

@include-section["notation.scrbl"]
@include-section["resources.scrbl"]
@include-section["surfaces.scrbl"]
@include-section["surface-properties.scrbl"]
@include-section["canvases.scrbl"]
@include-section["layers.scrbl"]
@include-section["specialized-canvases.scrbl"]
@include-section["colors.scrbl"]
@include-section["color-management.scrbl"]
@include-section["float-colors.scrbl"]
@include-section["paints.scrbl"]
@include-section["shaders.scrbl"]
@include-section["path-effects.scrbl"]
@include-section["color-filters.scrbl"]
@include-section["image-filters.scrbl"]
@include-section["runtime-effects.scrbl"]
@include-section["drawing.scrbl"]
@include-section["paths.scrbl"]
@include-section["rounded-rectangles.scrbl"]
@include-section["regions.scrbl"]
@include-section["structured-drawing.scrbl"]
@include-section["portable-drawing.scrbl"]
@include-section["matrices.scrbl"]
@include-section["projective-matrices.scrbl"]
@include-section["images.scrbl"]
@include-section["image-operations.scrbl"]
@include-section["encoding.scrbl"]
@include-section["typefaces.scrbl"]
@include-section["fonts.scrbl"]
@include-section["shaping.scrbl"]
@include-section["text-blobs.scrbl"]
@include-section["text-layout.scrbl"]

@include-section["pictures.scrbl"]
@include-section["drawables.scrbl"]
@include-section["pdf-documents.scrbl"]
@include-section["svg-documents.scrbl"]
@include-section["output-pages.scrbl"]
@include-section["annotations.scrbl"]
@include-section["output-audit.scrbl"]
@include-section["output-groups.scrbl"]

@include-section["streams.scrbl"]
@include-section["live-streams.scrbl"]
@include-section["pixel-descriptions.scrbl"]
@include-section["raster-buffers.scrbl"]
@include-section["codecs.scrbl"]
@include-section["scanline-codecs.scrbl"]
@include-section["incremental-codecs.scrbl"]
@include-section["graphics.scrbl"]
@include-section["native-libraries.scrbl"]


@include-section["gpu-providers.scrbl"]
@include-section["gpu-context-options.scrbl"]
@include-section["gpu-contexts.scrbl"]
@include-section["gpu-opengl-hosts.scrbl"]

@include-section["gpu-surfaces.scrbl"]
@include-section["gpu-images.scrbl"]
@include-section["gpu-transfers.scrbl"]
@include-section["gpu-synchronization.scrbl"]
@include-section["gpu-diagnostics.scrbl"]
@include-section["gpu-gl-interop.scrbl"]
@include-section["gpu-external-resources.scrbl"]
@include-section["gpu-native-handoffs.scrbl"]
@include-section["gpu-output.scrbl"]

@include-section["gpu-presentation.scrbl"]
@include-section["gpu-widgets.scrbl"]
@include-section["gui-canvases.scrbl"]
@include-section["render-canvases.scrbl"]

@include-section["racket-dc.scrbl"]
@include-section["dc-output.scrbl"]
@include-section["gpu-dc.scrbl"]

@index-section[]
