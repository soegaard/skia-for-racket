# Links and document annotations

Import `skia`, or import `skia/annotations` alongside the drawing API. Annotations
add interaction to an otherwise ordinary drawing. They do not draw a button,
underline, focus border, or any pixels. Draw the visible content with the normal
canvas API, then associate a rectangle with a link.

## A shared drawing callback

```racket
#lang racket/base
(require "main.rkt")

(define page
  (make-output-page
   360 240
   (lambda (canvas)
     (canvas-define-destination! canvas "top" 0 0)
     (with-skia ([paint (make-paint #:color 'blue)]
                 [font (make-font #:size 18)])
       (draw-simple-text canvas "Racket documentation" 10 35 font paint)
       (canvas-annotate-url! canvas 10 15 220 28
                             "https://docs.racket-lang.org/")
       (draw-simple-text canvas "Jump to the note" 10 85 font paint)
       (canvas-link-destination! canvas 10 65 220 28 "note")
       (canvas-define-destination! canvas "note" 10 140)
       (draw-simple-text canvas "This is the destination." 10 160 font paint)))
   #:margins 12 #:background 'white))

(save-output page "links.pdf" 'pdf #:exists 'replace)
(save-output page "links.svg" 'svg #:exists 'replace)
```

The same code can draw a raster reference. Annotation operations on a raster
canvas validate their arguments and then do nothing. A PNG cannot retain links.

## API reference

```racket
(canvas-annotation-backend canvas) ; 'pdf, 'svg, 'raster, or 'recording

(canvas-annotate-url! canvas x y width height uri)
(canvas-define-destination! canvas name x y)
(canvas-link-destination! canvas x y width height name)

(destination-id name) ; deterministic ASCII PDF destination identifier
(svg-destination-id name #:id-prefix [prefix "skia"])
```

All canvas operations require a live canvas on its creating Racket thread.
Drawing/definition operations return `void`. The two ID helpers are pure and
return immutable strings; neither loads the native library.

### URL regions

`canvas-annotate-url!` associates a local-coordinate rectangle with a URI.
It accepts `http`, `https`, `mailto`, and relative URI references. It does not
follow, open, fetch, validate the existence of, or automatically repair a link.
Other schemes, including `javascript`, `data`, and `file`, are rejected.

URIs must be nonempty, already-escaped ASCII. Encode spaces and non-ASCII
characters with `%HH`; malformed percent escapes, controls, backslashes, and
unescaped characters outside the URI character set are rejected. An HTTP(S)
URI must have an authority. An ampersand in a query is passed as an ordinary
ampersand; SVG serialization escapes it as XML, without changing the URI.
Use `canvas-link-destination!` rather than passing a fragment-only `"#name"`.
A URI such as `"other.svg#section"` is an external/relative link and is allowed.

Each input is copied before native recording. Closing a temporary native data
buffer or mutating the original Racket string cannot change a recorded URL.

### Destination definitions and internal links

`canvas-define-destination!` binds a name to a point in the current document.
`canvas-link-destination!` associates a rectangle with that name. Forward
references are allowed: on PDF the definition can be on a later page. All pages
of one PDF share a destination namespace. Each SVG has a separate namespace.

Names are nonempty Unicode strings, compared exactly and case-sensitively.
Controls and non-XML characters are rejected. Names are copied; there is no
implicit Unicode normalization or symbol-to-string conversion. Internally they
become `dest-` followed by the hexadecimal UTF-8 bytes. Thus `"intro"` becomes
`"dest-696e74726f"`, and `"α"` becomes `"dest-ceb1"`. This is a reversible,
collision-free encoding, not a lossy replacement of punctuation.

Duplicate definitions raise immediately, including definitions through different
canvas aliases or on different PDF pages. Missing references raise before native
finalization. A manual caller can define the missing target and retry finishing;
a scoped byte/file export aborts when that exception escapes its callback or
finalization. It never publishes a document with a missing destination. Zero-size
or fully clipped named references are still checked, so a typo does not become
valid just because of the current graphics state.

Definitions ignore clipping. PDF places the destination at the transformed
point. SVG inserts a predefined `view` at that point. Its viewBox keeps the
original viewport extent and pans its top-left to the target; it does not alter
the original drawing or physical page dimensions. The exact navigation UI is
controlled by the viewer.

### Stable SVG fragments and cross-file links

SVG destination IDs are prefixed with the SVG export's `#:id-prefix`. Native
resource IDs retain their existing independent canonicalization.

```racket
(svg-destination-id "intro" #:id-prefix "chapter")
; => "chapter-dest-696e74726f"

(canvas-annotate-url!
 canvas 10 20 120 25
 (string-append "chapter.svg#"
                (svg-destination-id "intro" #:id-prefix "chapter")))
```

Use exactly the prefix selected when exporting the target SVG. The API cannot
resolve names in another file; the caller is responsible for matching filenames
and destination IDs. The probe inspector checks its known sibling files without
performing network requests.

## Coordinates and clipping

Rectangles use `(x y width height)`, with nonnegative extents. Points and
rectangles use the current canvas coordinate system, including translation,
scaling, rotation, and shared-page units/margins. For a millimetre-authored
`output-page`, annotation coordinates are millimetres too. Calls do not change
the canvas matrix, clipping state, save count, paint, or existing artwork.

URL/internal-link rectangles are transformed and clipped by the native backend.
Their final hit regions are **axis-aligned rectangles**, not precise path hit
areas. A rotated rectangle can therefore make parts of its bounding box clickable
outside the visible rotated shape. Complex clipping is also reduced to a bounding
rectangle: PDF uses the bounds of its path intersection; SVG uses conservative
clip bounds. Do not rely on exact holes, path-shaped regions, or QuadPoints.
Zero-area URL regions and native fully clipped link regions are omitted.

SVG links are serialized as a final root overlay. Skia computes their root/device
coordinates, but its native SVG annotation writer may leave the link inside a
previously synchronized graphics clip group. Finalization moves only these
native annotation elements to the root, avoiding stale or double-applied clipping.
It preserves drawing content and already-escaped URIs, adds `href` alongside
`xlink:href`, and resolves internal placeholder targets to predefined views.
It is deliberately a postprocessor for this pinned backend's own XML, not an
arbitrary SVG parser, importer, or sanitizer. Overlapping links are not resolved
against visible-object occlusion; avoid ambiguous overlapping hot regions.

## Picture recording and rasterized groups

| Canvas/output | URL rectangles | Named destinations and internal links |
|---|---|---|
| Live PDF page | Native annotations | Document-wide, including forward references |
| Live SVG | Native rectangles, normalized at finish | Single-document predefined views |
| Raster surface | Validated no-op | Validated no-op |
| Picture recorder | Recorded native command | Rejected; add to the live document after replay |

Recorded URLs retain their own native data reference. Replaying the picture onto
PDF or SVG applies the replay's transform. This does not mean that interaction
survives rasterization: a picture rendered into an image, an image-filter source,
or a `draw-rasterized` group has pixels, not document links.

Add named annotations after `draw-picture`, on the receiving document canvas.
This avoids ambiguous destination names when the same picture is replayed twice,
and avoids claiming that the pinned SVG backend records named definitions.
Likewise, place a link for a rasterized panel on the **outer** canvas after drawing
the panel, not inside the raster callback.

## Interactive review

Open `output/document-links-0.27.review.html`. The actual SVG is embedded with
`object`; the raster reference uses `img`. An SVG loaded as an ordinary image is
not an interactive document. Each section also links to the standalone SVG.

The probe contains three pages: ordinary/cross-file links; transformed, clipped,
and recorded URLs; then named destinations and URI escaping. The PDF has forward
links across pages. SVG cross-page navigation instead uses sibling SVG files,
while same-file links use predefined views. The runner also creates a static HTML
companion, so local link testing needs no external website. External documentation
links are activated only when the viewer's user clicks them.

The PNG references are separately drawn raster images, not PDF/SVG renderings.
They can establish appearance, but never link functionality. Review actual output
in a browser/PDF viewer as well as running structural inspection.

## Boundaries

This API adds link annotations and named point destinations. It does not add PDF
text comments, sticky notes, forms, outlines/bookmarks, attachments, arbitrary
JavaScript actions, accessibility tagging, or browser-style DOM event handlers.
It does not certify PDF/A or accessibility compliance. The existing `#:pdfa?`
metadata/output-intent mode remains available, with its previous limitations.
No new native structures are introduced; three annotation entry points reuse
owned `SkData` and the existing rectangle/point types. The 0.26 ICC/PNG workaround
and pixel-conversion behavior are unchanged.

## Pinned implementation sources

The audit uses Skia commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`, matching
SkiaSharp 3.119.1. These explain upstream semantics; they are not evidence of a
local native run of the new wrapper.

- [SkAnnotation.h](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/core/SkAnnotation.h)
  defines local-coordinate annotations and escaped ASCII URLs.
- [SkPDFDevice::drawAnnotation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/pdf/SkPDFDevice.cpp)
  transforms/clips links and registers named points.
- [SkSVGDevice::drawAnnotation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/svg/SkSVGDevice.cpp)
  emits URL/link rectangles but no named-definition element.
- [SkPDFDocument link serialization](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/pdf/SkPDFDocument.cpp)
  emits a catalog destination dictionary and name-object link targets. The PDF
  inspector normalizes those names as well as string-based name-tree targets.
- [SkRecorder::onDrawAnnotation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/core/SkRecorder.cpp)
  records the rectangle/key and retains the data reference.
- [SVG 2 linking](https://www.w3.org/TR/SVG2/linking.html) defines `a`, `href`, and
  predefined `view` fragments; [processing modes](https://www.w3.org/TR/SVG/conform.html)
  distinguish interactive documents from images.
