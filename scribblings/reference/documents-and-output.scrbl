#lang scribble/manual

@title[#:tag "skia-reference-documents-output" #:style 'toc]{Documents and Output}

PDF and SVG outputs record drawing into document-oriented targets. Page
construction, links, auditing, and bounded output groups control how those
outputs are assembled and validated. Raster fallback normally executes on the
CPU; an explicit GPU executor can instead render a selected fallback before
reading it back into CPU-owned document content.

@include-section["pdf-documents.scrbl"]
@include-section["svg-documents.scrbl"]
@include-section["output-pages.scrbl"]
@include-section["annotations.scrbl"]
@include-section["output-audit.scrbl"]
@include-section["output-groups.scrbl"]
@include-section["gpu-output.scrbl"]
