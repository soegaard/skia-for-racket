# SVG document output

This layer writes standalone SVG documents through Skia's native SVG canvas.
It is an output backend, not an SVG parser, editor, or renderer. It is separate
from the existing SVG *path-data* conversion functions.

The implementation is pinned to SkiaSharp 3.119.1 / native milestone 119.
PDF output and its page lifecycle are unchanged.

## Start with a drawing procedure

```racket
#lang racket/base
(require "main.rkt")

(define (draw c)
  (with-skia ([p (make-paint #:color 'blue)])
    (draw-circle c 100 90 45 p)))

(call-with-svg-file "example.svg" 300 180 draw
                    #:title "A blue circle"
                    #:description "A circle drawn with the ordinary canvas API."
                    #:exists 'replace)

(define svg-bytes  (call-with-svg-bytes  300 180 draw))
(define svg-string (call-with-svg-string 300 180 draw))
```

All three helpers pass a normal `canvas?` to the procedure, not a document.
Unlike a PDF, an SVG has one viewport and no begin/end-page operations. A
`svg-document?` is a `skia-resource?`, but is intentionally not a PDF
`document?`. The resource wrappers share the normal cleanup/thread rules.

The procedure runs exactly once. Its return values are ignored. The helper
finishes the SVG only after the procedure returns normally, copies the result,
and releases the native resources. A saved canvas becomes invalid when the
helper exits, including on exceptions, arbitrary raised values, breaks, and
continuation escapes.

## Viewport, coordinates, and metadata

Width and height are finite reals from 0.001 through 32768, measured in SVG
user units. Fractional sizes are accepted. The initial origin is at the top
left; positive x is right and positive y is down, just like a raster canvas.
The result has explicit `width`, `height`, and `viewBox="0 0 width height"`.
This stage does not expose a separately positioned/scaled viewBox or CSS units.

The pinned native implementation rounds its device size to integral units and
does not emit a viewBox. After native finalization, the Racket layer replaces
the root opening with the requested fractional viewport and explicit viewBox.
Drawing elements are not flattened into an image in this process.

Every constructor/helper accepts:

```racket
#:title       [title ""]
#:description [description ""]
#:id-prefix   [id-prefix "skia"]
```

Title and description become direct `<title>` and `<desc>` children. They must
contain valid XML 1.0 characters and are escaped as UTF-8 metadata. Empty values
omit the corresponding element. This metadata does not make outlined glyphs
into selectable text or provide a structured accessibility tree.

## Resource IDs and repeatability

The native SVG backend uses process-global generation numbers for clip IDs.
The wrapper renumbers native IDs in definition order and updates their URL and
fragment references. This allows the same font-free clipped drawing to produce
identical output in repeated calls within a process.

`#:id-prefix` takes 1–64 ASCII characters: start with a letter or underscore,
then use letters, digits, underscores, dots, or hyphens. For example:

```racket
(call-with-svg-file "diagram.svg" 300 180 draw
                    #:id-prefix "chapter-2-diagram-1"
                    #:exists 'replace)
```

The generated IDs will begin `chapter-2-diagram-1-`. Choose distinct prefixes
when putting multiple SVG roots inline in the same HTML document. Separate
files loaded through `<img>` have separate resource scopes.

Canonicalization is narrowly applied to attributes in Skia-generated XML. It
is not an arbitrary SVG sanitizer and does not rewrite text labels that merely
mention `url(#some-id)`. Fonts, font discovery, image encoders, native versions,
and rendering platforms can still affect output. No cross-platform byte or
pixel identity is promised.

## Native text versus glyph outlines

The pinned C shim exposes `sk_svgcanvas_create_with_stream(bounds, stream)`.
It does **not** expose the C++ flags for text-to-path conversion, compact XML,
or relative path encoding. There is no fabricated flag argument in this API.

Ordinary text and text-blob drawing go through the native backend. They can
produce `<text>` elements with positions and a font-family name. The SVG does
not embed the font binary. The viewer must have a suitable font; fallback may
change appearance. Native glyph-to-Unicode conversion cannot faithfully
represent every shaped glyph, ligature, alternate, or complex-script run and
may omit glyphs that it cannot map. Native text output is not a lossless
serialization of the original text or the HarfBuzz glyph run.

Use explicit paths when preserving monochrome glyph geometry matters more
than selection/search or editing as text:

```racket
(with-skia ([f (make-font #:size 28)]
            [p (make-paint #:color 'black)]
            [outline (simple-text-path f "A simple label" 30 50)])
  (draw-path canvas outline p))
```

For shaped text, the new `shaped-run->path` uses the same shaper's snapshotted
font and the run's explicit glyph positions, including its shaping offsets:

```racket
(with-skia ([f (make-font #:size 28)]
            [sh (make-shaper f)]
            [p (make-paint #:color 'black)])
  (define run (shape-text sh "office affinity AV" #:language "en"))
  (with-skia ([outline (shaped-run->path sh run)])
    (with-canvas-state canvas
      (canvas-translate! canvas 30 90)
      (draw-path canvas outline p))))
```

Supply the shaper used for that run. The returned path is independent of the
shaper and remains usable after the shaper is closed. An empty run produces an
empty path. Like `simple-text-path`, it only represents available outlines:
empty/bitmap-only glyphs without outlines are omitted, so it is not a way to
preserve color emoji. Render such text into an explicit rasterized group.

Both path helpers work with raster and PDF canvases too. Outlining loses text
selection/search, increases geometry, and is not a substitute for font embedding.
Recorded pictures replay their original commands: a picture containing native
text is not magically converted to outlines. Record the outline paths when
that is the intended output.

## Explicit rasterized groups

Skia's SVG backend is narrower than its PDF backend. **Do not assume that an
unsupported operation is automatically rasterized.** Some native operations
can be omitted or serialized with different semantics.

`draw-rasterized` provides an explicit alternative. It draws a bounded group on
a transparent raster surface, then draws a snapshot into the destination. SVG
serializes that snapshot as an embedded image while surrounding content stays
vector:

```racket
(draw-rasterized
 canvas 40 100 240 160
 (lambda (local-canvas)
   (with-skia ([shadow (make-drop-shadow-image-filter 6 6 4 4
                                                     (rgba 0 0 0 100))]
               [p (make-paint #:color 'blue #:image-filter shadow)])
     (draw-rounded-rect local-canvas 25 25 150 80 12 12 p)))
 #:scale 2)
```

The callback sees a local `(0,0)` origin and logical bounds `width × height`.
`#:scale` is pixels per logical unit, from 1/1024 through 1024. Pixel dimensions
are `ceiling(width*scale)` and `ceiling(height*scale)` and must pass the normal
raster dimension/byte limits. Each axis's initial scale accounts for that
rounding, so its logical extent maps exactly to the destination extent.

Include padding for shadows, blur, and strokes: content outside the group's
bounds is clipped. The group starts transparent and does not capture the
existing destination backdrop. A blend that depends on outside content is not
equivalent to rasterizing in isolation; put the required backdrop inside the
group as well. Rasterizing is explicit, local, and independent of the output
backend, not a hidden whole-document screenshot fallback.

## Backend coverage and limits

| Drawing category | SVG behavior / guidance |
| --- | --- |
| Paths, shapes, strokes, affine transforms | Native SVG elements/paths/transforms. |
| Linear gradients | Native linear-gradient paint servers. This is not a guarantee for all gradient tile modes. |
| Intersect clipping | Native clip paths, covered by structural and repeatability probes. |
| Images | Embedded image data; image rectangles use PNG encoding in the pinned backend. |
| Pictures | Commands replay into SVG; simple recorded vector geometry remains vector. |
| Dashes/path effects on paths | Can be expanded to filled/stroked path geometry; not necessarily `stroke-dasharray`. |
| Native text | Font-dependent `<text>` with the glyph-mapping limitations described above. |
| Explicit glyph paths | Geometry without font dependency for the outlined glyphs; no text semantics. |
| Radial/sweep/conical or composed shaders | Not generally supported by the pinned native SVG serializer. Use explicit rasterization. |
| General color/mask/image filters | Not a universally supported SVG filter graph. Use explicit rasterization. |
| Difference clipping, general paint blend modes, some opacity combinations | Do not assume raster-equivalent SVG behavior. Include the necessary content/backdrop in a rasterized group. |
| GPU, animation markup, SVG input, arbitrary DOM editing | Not provided by this layer. |

This wrapper does not attempt exhaustive unsupported-operation detection. The
first SVG stage prioritizes a safe document lifecycle, actual native SVG
output, an explicit compatibility boundary, and useful escape hatches. Future
vector-output refinement can provide stronger operation-specific policy.

## Low-level lifecycle

```racket
(with-skia ([d (make-svg-document 300 180 #:title "Incremental SVG")])
  (define c (svg-document-canvas d))
  (draw c)
  (svg-document-finish! d)
  (save-svg d "example.svg" #:exists 'replace)
  (define independent-bytes (svg-document->bytes d)))
```

The states are `open`, `finished`, `aborted`, and `closed`.
`svg-document-finish!` is idempotent while the document remains live. It deletes
the native SVG canvas **before** detaching the stream; flushing alone does not
complete the XML. Every canvas alias becomes invalid after finishing. The
finished document remains live for repeated byte/string reads and saves until
explicit/scoped close.

`svg-document->bytes` returns an independent mutable byte string.
`svg-document->string` returns its UTF-8 decoding. Both require a successful
finish and a live document. Copies can outlive it; the cached finalized data is
released when the document closes. `svg-document-abort!` closes and discards
the result, including a previously finalized result, and can be called again.

Finishing from inside `with-canvas-state` is rejected so scope cleanup cannot
restore a deleted native canvas. Closing/aborting the owner inside such a
scope is safe. SVG native operations retain the package's creator-thread rule.
No native-to-Racket callbacks, user native pointers, or retained Racket pixel
buffers are introduced.

The file helpers fix the absolute destination before the drawing callback,
finish all SVG data first, write a temporary file in the destination directory,
and rename only after successful output. `#:exists 'error` is checked again
at publication, so a file created meanwhile is not overwritten. Drawing or
finalization errors do not replace an existing destination. Parent directories
must already exist.

## Memory limits and validation

`current-skia-byte-limit` guards escaped metadata, copied native XML,
postprocessed XML, copied readback, and requested rasterized-group buffers.
A vector viewport is not charged `width*height*4` merely for existing. The
limit is not a total-process or native-heap cap: Skia can allocate internal
storage and accumulate a stream before finalization checks its output size.

Run the command sequence in [SVG testing](SVG-TESTING.md). The example produces
three SVGs, three separately drawn raster references, and a browser review
page. The standard-library Python inspector parses the actual output, checks
viewport sizes/IDs/references, decodes embedded image headers, and checks the
expected vector/text/image categories. It does not render SVG or certify
visual equivalence.

## Pinned implementation references

- [C SVG canvas shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_svg.cpp)
- [C canvas destructor](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_canvas.cpp)
- [C++ SVG canvas lifetime and flags](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/svg/SkSVGCanvas.h)
- [Native viewport construction](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/svg/SkSVGCanvas.cpp)
- [Element, shader, clipping, image, and glyph serialization](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/svg/SkSVGDevice.cpp)
