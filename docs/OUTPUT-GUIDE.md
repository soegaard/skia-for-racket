# Shared PDF/SVG output — 0.23.0

An output page is an immutable description of a drawing, its size, units,
margins, optional background, and content clipping. It owns no native resource.
Exporting the same page to PDF and SVG runs the same drawing procedure through
the existing `canvas?` API. The low-level PDF and SVG lifecycle APIs remain
available and keep their earlier behavior.

## Author a page once

```racket
#lang racket/base
(require skia)

(define page
  (make-output-page
   210 148.5
   (lambda (canvas)
     (with-skia ([paint (make-paint #:color 'blue)]
                 [font (make-font #:size 6
                                   #:linear-metrics? #t
                                   #:subpixel? #t
                                   #:hinting 'none)])
       (draw-circle canvas 30 30 15 paint)
       (draw-simple-text canvas "The same drawing" 5 65 font paint)))
   #:unit 'mm
   #:margins 10
   #:background 'white))

(save-output page "example.pdf" 'pdf #:exists 'replace)
(save-output page "example.svg" 'svg #:exists 'replace)
```

The procedure receives one canvas. Its coordinates and lengths are in the
chosen unit, with `(0,0)` at the top-left of the content area, after margins.
Positive y points down. Font sizes and stroke widths also use these drawing
units. For small physical units, linear font metrics and subpixel positioning
avoid deliberately pixel-rounded advances being magnified by the unit transform.
The exporter does not mutate a caller's fonts or paints.

The callback runs once per page *per export*. The exporter does not cache it,
record it automatically, or promise determinism for a stateful callback. A page
that closes over a native resource can only be drawn while that resource is
live and usable in the current Racket thread. A page whose callback creates its
own resources is convenient to reuse.

## Units and physical size

`#:unit` accepts `'pt`, `'in`, `'mm`, `'cm`, and `'px`. Conversions use exact
factors: 72 points per inch, 360/127 points per millimetre, and 3/4 point per CSS
pixel. `unit->points` preserves exact arithmetic for exact arguments. Page
sizes must fall between 0.001 and 14400 points after conversion; creating a
vector page does not allocate an equivalent RGBA bitmap.

PDF pages use point-sized media boxes. The shared SVG exporter uses the same
point-valued viewBox and writes explicit `pt` suffixes on its root width and
height. This gives the two formats the same **nominal physical size**. It fixes
the ambiguity of treating one bare SVG user unit as one PDF point. Browser CSS,
zoom, responsive layout, and print scaling can still resize either preview.

The existing `call-with-svg-*` and `make-svg-document` functions retain their
original user-unit sizing. Physical point sizing is a feature of `output->bytes`
and `save-output`, not a retroactive change to the low-level SVG interface.

`output-page-size-in-points` returns two values. `output-page-content-size`
returns the available width and height in the page's original unit.

## Margins, clipping, and backgrounds

`#:margins` is a nonnegative scalar or `(list left top right bottom)`. The order
is not CSS's top/right/bottom/left order. Margins use the same unit as the page
and must leave a positive content area.

Content is clipped to that area by default. `#:clip? #f` permits deliberate
painting into the margins. The output document/raster's outer bounds still
apply. `#:background #f` means not to paint a background; a color paints a
full-page rectangle before the content clip, using ordinary source-over drawing.
A PDF viewer's white page is not itself an explicitly painted white background.

`draw-output-page` can draw a page onto an existing raster, PDF, SVG, or recording
canvas. It interprets one current destination unit as one point before applying
the page's unit conversion. It restores canvas state and dynamic output settings
on normal return, exceptions, and continuation escapes. It does not reset a
caller's existing transform or clip.

## One or several pages

```racket
(define pdf-bytes (output->bytes (list cover body appendix) 'pdf))
(define svg-bytes (output->bytes cover 'svg))
(define svg-text (bytes->string/utf-8 svg-bytes))
```

PDF accepts a single page or a nonempty list of pages, including mixed sizes and
units. SVG accepts exactly one page (or a one-element list); a larger list raises
before the first drawing callback. Pages are never silently omitted.

Common metadata is `#:title` and `#:description`. Description becomes the PDF
subject or SVG `<desc>`. `#:id-prefix` is SVG-only; `#:encoding-quality` is
PDF-only (0–100 for its lossy quality policy, 101 for lossless). Supplying either
to the wrong format raises rather than being ignored. `#f` selects the format's
default. Use the low-level document APIs for additional PDF metadata or manual
page lifecycle control.

`save-output` requires an explicit `'pdf` or `'svg`; it does not guess from the
filename. It resolves the destination before running user code and publishes
only completed output through the existing same-directory temporary-file/rename
helpers. Drawing/finalization errors preserve an existing destination. `'error`
checks again when publishing, so a callback-created or racing destination is
not overwritten. `'replace` intentionally permits replacement.

## Text output policy

The shared exporters accept `#:text-mode 'auto`, `'native`, or `'outline`.
Auto chooses native text for PDF and outlines for SVG. Explicit choices override
that default. This affects drawing representation, not text shaping or layout.

The scoped `current-text-output-mode` parameter accepts `'native` or `'outline`
and initially holds `'native`. `draw-simple-text`, `draw-shaped-run`,
`draw-shaped-text`, `draw-text-layout`, `draw-mixed-text-layout`, and
`draw-text-blob` honor it. Low-level exporters do not select an automatic mode;
under default parameters their output stays unchanged.

Outlines retain available glyph geometry and positions without requiring the
viewer's copy of the font. They are not selectable/searchable text and do not
preserve logical text, accessibility, or editing semantics. Raster hinting can
also make outline and native text look slightly different at small display
sizes. Native PDF text uses the backend's font handling; it is not a guarantee
that every shaped glyph has ideal text extraction. Native SVG text still has
viewer-font and reverse glyph-to-Unicode limitations.

### Prebuilt text blobs

`text-blob->path` returns an independently owned path at the blob's baseline-local
positions. Text blobs now retain a private snapshot of font properties and copied
glyph/position lists. Mutating or closing the source font or input vectors does
not change later outline conversion. Closing the blob releases its native blob
and its private font; a returned path remains usable. The snapshot adds a small
native font object plus glyph/position metadata, without copying font files.

Both `text-blob->path` and `shaped-run->path` omit glyphs with no monochrome
outline, including some bitmap/color glyphs. An explicit rasterized group is the
alternative when those glyphs must retain their rendered appearance.

### Pictures freeze earlier drawing decisions

A pre-recorded `picture?` contains native commands. A later text policy cannot
rewrite that recording. To make a portable outlined recording, author it inside
an outline scope or construct it inside an auto-outlined SVG page callback:

```racket
(define picture
  (parameterize ([current-text-output-mode 'outline])
    (call-with-picture width height draw)))
```

Replaying such a picture stays outlined even in a later native-text PDF export.
Replaying an earlier native-text picture stays native, including in an otherwise
outlined SVG export. The inspector's example records its picture during page
authoring, so each backend gets the intended policy.

## Raster fallback: density, padding, and color tags

```racket
(draw-rasterized canvas x y width height draw
                 #:scale scale
                 #:padding '(left top right bottom)
                 #:color-space color-space)
```

Scale is pixels per local drawing unit. Without `#:scale`, the function reads
`current-raster-output-scale`, initially 1. The shared page helpers set it from
`#:raster-dpi` and the page's unit: `dpi * points-per-unit / 72`. Export DPI also
sets PDF's native fallback DPI. It does not rasterize the whole page, change
vector precision, or affect text layout. Scale remains in the range 1/1024–1024;
incompatible unit/DPI combinations are rejected before drawing. A callback's
additional scale/rotation is not automatically analyzed to choose a new density.

Padding defaults to zero and is a nonnegative scalar or four-sided list in the
same left/top/right/bottom order as margins. For content `(x,y,width,height)`,
the embedded image covers `(x-left,y-top,width+left+right,height+top+bottom)`.
The callback still sees its original local origin and content dimensions. Thus
adding shadow/blur room does not shrink or move the content. Pixel sizes are the
ceilings of the expanded dimensions times scale, with each initial axis scale
adjusted for that integer rounding. Normal pixel-size and byte limits apply.

Padding does not override the destination's clip or the page's content clip.
Include the necessary backdrop inside a group for destination-dependent
blending: the existing destination is not captured. Raster callbacks temporarily
use native text rendering, even under an outer outline policy, so bitmap/color
glyphs can be drawn as pixels. An explicit inner parameterization can override it.

`#:color-space` tags the temporary rendering surface and its snapshot through
the existing owned color-space API. It is optional and defaults to `#f`. This is
not a new promise of end-to-end ICC equivalence between PDF and SVG. Arbitrary
encoded-output ICC injection and custom RGB color spaces remain separate work.

Unsupported native SVG operations still do not receive universal automatic
fallback. This stage does not silently rasterize difficult shaders, change
blend modes, or repair every backend limitation. Use explicit groups and review
the actual output. See the SVG coverage table in `SVG-OUTPUT.md`.

## Raster references and validation

`output-page->image` returns a detached image from the same page callback. Its
DPI defaults to 96; text mode defaults to native; an optional color space tags
the temporary surface. Pixel dimensions are rounded up independently while the
logical page size is preserved. This is a separate raster rendering, not a
rendering of an exported PDF or SVG.

`examples/vector-output.rkt` is the single visual-probe runner. It writes one
three-page PDF, three corresponding SVGs, three 144-DPI raster references, and
a browser comparison page. `tools/inspect-vector-output.py` checks actual SVG
physical sizes, outlines, resource references, PNG chunk CRCs, and the two
expected fallback sizes. `--pdf` adds parser-based page/text/font checks with
pypdf. Font embedding is reported, not universally required. Open the actual
PDF and SVG files as well; structural checks do not establish visual fidelity.

The implementation and host validation commands are described in
`OUTPUT-TESTING.md`. No new native symbols or C struct layouts are introduced.

## Reference basis

Physical conversions follow the [CSS absolute-length definitions](https://www.w3.org/TR/css-values-4/#absolute-lengths).
The native behavior remains pinned to SkiaSharp 3.119.1 and its Skia source commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`; see the existing
[`SOURCES.md`](SOURCES.md) for the C ABI references. In particular, the shared
layer does not add flags absent from the pinned SVG C shim or change Skia's
PDF/SVG font and unsupported-operation behavior. Those are separate from the
Racket-side unit, lifetime, text-policy, and padding choices described here.
