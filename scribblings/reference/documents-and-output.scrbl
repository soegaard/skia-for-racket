#lang scribble/manual

@(require (for-label racket/base skia))

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

For an output page, also choose where the encoded document should go.
@racket[output->bytes] returns a complete byte string; @racket[save-output]
writes a complete file. The live writers, @racket[output->port] and
@racket[output-write-stream!], send bytes to an existing port or
@tech{native stream}. They are not interchangeable destinations with identical
features:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Feature} @bold{Bytes or file} @bold{Port} @bold{Native stream})
  (list "Formats" "PDF, SVG" "PDF, SVG" "PDF, SVG")
  (list "PDF pages" "One or more" "1–1024" "1–1024")
  (list "SVG pages" "One" "One" "One")
  (list "Metadata and ID options" "Available" "Available" "Available")
  (list "Named destinations" "Supported" "Not supported" "Not supported")
  (list "Partial output on failure" "No" "Possible" "Possible"))]

All four interfaces accept title and description options, an SVG ID prefix,
and PDF encoding-quality and PDF/A settings. The live writers additionally
accept an audit policy and capture the drawing once before preflight. All routes remain subject to their
resource, dimension, and byte limits; the page counts above are not memory
guarantees.

The ordinary @racket[output->bytes] and @racket[save-output] functions do not
add an audit. Their @racket[output->bytes/audit] and @racket[save-output/audit]
counterparts return reports and default to the @racket['error] audit policy.
Live document writers also default to @racket['error], but return a byte count,
not an audit report. An audit checks compatibility; it does not automatically
add raster fallback.

Each live document writer records the drawing callbacks once into pictures,
checks them before writing, and then replays them. The intermediate picture
canvas cannot define @tech{named destinations} or links to them. Use the
byte-string or file route, or the direct PDF/SVG document interfaces, when
those annotations are needed.

Drawing or preflight failure in a live writer occurs before any destination
bytes are written. A later failure can leave a partial document. In contrast,
byte-string export returns only completed output, and @racket[save-output]
writes a temporary file before renaming it, leaving an existing destination
unchanged on failure. A native-stream writer appends rather than replaces;
after a failure that makes the stream unusable, close it instead of retrying.
See @secref["skia-live-streams"] and @secref["skia-native-publication"] for
port cleanup and native-stream restrictions.

@local-table-of-contents[]

@include-section["pdf-documents.scrbl"]
@include-section["svg-documents.scrbl"]
@include-section["output-pages.scrbl"]
@include-section["annotations.scrbl"]
@include-section["output-audit.scrbl"]
@include-section["output-groups.scrbl"]
@include-section["gpu-output.scrbl"]
