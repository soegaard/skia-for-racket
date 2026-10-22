#lang scribble/manual

@title[#:tag "skia-reference-documents-output" #:style 'toc]{Documents and Output}

Use these interfaces to export drawings as PDF or SVG. Choose according to
whether the drawing is specific to one format or should be reused across formats:

@itemlist[
 @item{@seclink["skia-pdf-documents"]{PDF documents} support multiple pages and
   PDF-specific metadata and encoding settings.}
 @item{@seclink["skia-svg-documents"]{SVG documents} provide one drawing viewport
   and SVG-specific metadata and identifiers.}
 @item{@seclink["skia-output-pages"]{Output pages} reuse a drawing callback with
   the same dimensions, units, and margins for PDF, SVG, or raster images.}]

@seclink["skia-annotations"]{Links and named destinations} add navigation to the
exported document. Optional @tech{output audits} report compatibility concerns
or reject drawing features that do not meet an export policy.
@tech{Bounded output groups} choose between native replay and @tech{raster fallback}
for one part of a drawing. An audit checks the result of that choice; it does
not make the choice itself.

Raster fallback normally uses the CPU. A
@seclink["skia-gpu-output"]{GPU raster executor} can render a selected group on
the GPU and read it back into a CPU-owned image for inclusion in the document.

@local-table-of-contents[]

@include-section["pdf-documents.scrbl"]
@include-section["svg-documents.scrbl"]
@include-section["output-pages.scrbl"]
@include-section["annotations.scrbl"]
@include-section["output-audit.scrbl"]
@include-section["output-groups.scrbl"]
@include-section["gpu-output.scrbl"]
