# API reference — version 0.24.0

Import `(require skia)`, or `"main.rkt"` from the extracted root. The bitmap
bridge is a separate `(require skia/bitmap)` module. Signatures below use
square brackets for optional positional arguments and show keyword defaults.
No pointer or unsafe FFI declarations are exported by the public collection.

## Affine matrices and path inspection

```racket
(matrix? value)
(make-matrix [xx 1] [yx 0] [xy 0] [yy 1] [x0 0] [y0 0])
matrix-identity
(matrix-xx matrix) (matrix-yx matrix) (matrix-xy matrix)
(matrix-yy matrix) (matrix-x0 matrix) (matrix-y0 matrix)
(matrix->vector matrix)             ; immutable #(xx yx xy yy x0 y0)
(vector->matrix vector)             ; copied/validated six coefficients
(matrix-translate x y)
(matrix-scale x [y x])
(matrix-skew x y)                    ; shear factors
(matrix-rotate radians)
(matrix-rotate-degrees degrees)
(matrix-compose matrix ...)          ; A*B applies B first, then A
(matrix-invert matrix)               ; matrix or #f
(matrix-map-point matrix x y)        ; two values, includes translation
(matrix-map-vector matrix x y)       ; two values, ignores translation
(matrix-map-rect matrix x y width height) ; x y width height of axis-aligned bounds

(canvas-transform canvas)
(canvas-set-transform! canvas matrix)
(canvas-concat! canvas matrix)       ; current <- current * matrix
(path-transform path matrix)        ; independent owned path
(path-transform! path matrix)
(shader-with-local-matrix shader matrix) ; independent owned shader reference

(path-segment? value)
(path-segment-verb segment)          ; move line quad conic cubic close
(path-segment-points segment)        ; immutable list of (list x y)
(path-segment-conic-weight segment)  ; #f except for conic
(path-segment-closing-line? segment) ; normal iterator's synthetic line
(path-segments path #:mode [mode 'normal] #:force-closed? [force-closed? #f])
(in-path-segments path #:mode [mode 'normal] #:force-closed? [force-closed? #f])
(path->commands path)               ; raw absolute make-path commands
(path-contour? value)
(path-contour-segments contour)
(path-contour-closed? contour)
(path-contours path #:mode [mode 'normal] #:force-closed? [force-closed? #f])
(path-measure-matrix measure distance #:mode [mode 'position+tangent])
```

Matrices are immutable affine 2D values, not native resources. Coefficients
are finite C-float-representable reals, rounded at construction. Vector order
represents rows `(xx xy x0)`, `(yx yy y0)`, `(0 0 1)`. Composition and point
mapping reject unrepresentable results. Inversion returns `#f` for singular
or unrepresentable inverses; near-singular matrices remain precision-sensitive.
Positive rotation maps x toward y (clockwise in the default y-down canvas).
Negative/zero scale is allowed. Rectangular extents must be nonnegative.

Canvas queries return a detached matrix; setters do not reset clips. Use concat
rather than set to preserve an output-page's unit/margin transform. These calls
retain normal canvas lifetime, save/restore, and creator-thread rules. The
public abstraction deliberately does not expose 3D/projective matrices.

Snapshots copy points before releasing the scoped native iterator. Sequences
are eagerly captured when constructed and may be iterated repeatedly after
source mutation or closure. Normal mode can synthesize closing lines; raw
mode returns stored verbs and rejects `#:force-closed? #t`. Conic weights are
read only for conics; close has no points. Point counts are 1/2/3/3/4/0 for
move/line/quad/conic/cubic/close. Lines and curves include their start point.
Contours group these snapshots and identify a final close. Raw move-only
contours are preserved. The logical snapshot budget is 16 bytes per segment
plus 8 bytes per point, bounded by `current-skia-byte-limit`, not total heap use.

Reconstruction commands do not contain the fill rule: pass `path-fill-rule`
separately to `make-path`. Path transforms preserve it. Transforming only a
path does not scale its later stroke width or transform its paint. A canvas
transform applies to the entire drawing operation.

Measurement modes are `position`, `tangent`, and `position+tangent`. Distance
is finite and nonnegative; values past the current contour's length clamp to
its endpoint. Empty/zero-length contours return `#f`. The combined frame maps
local origin to the point and local x-axis to the tangent. It does not advance
the measure's current contour.

Shader-local matrices change sampling coordinates, retain the source natively,
and leave drawing geometry unchanged. Native SVG cannot reliably represent
these transforms: use an explicit bounded `draw-rasterized` group for them.
See [the guide](PATH-MATRIX.md) and [ABI audit](PATH-MATRIX-ABI.md).

## Shared PDF/SVG page output

These helpers are available from `skia` and `skia/output`. They own no new
native backend; they use the PDF and SVG interfaces below. See the
[shared-output guide](OUTPUT-GUIDE.md) for complete examples and limitations.

```racket
(unit->points value [unit 'pt])
(output-page? value)
(make-output-page width height draw
                  #:unit [unit 'pt]
                  #:margins [margins 0]
                  #:background [background #f]
                  #:clip? [clip? #t])
(output-page-width page)                 ; original drawing units
(output-page-height page)
(output-page-unit page)
(output-page-margins page)               ; (list left top right bottom)
(output-page-background page)            ; #f or immutable rgba value
(output-page-clip? page)
(output-page-size-in-points page)        ; two values
(output-page-content-size page)          ; two values, original unit

(output->bytes page-or-pages format
               #:title [title ""] #:description [description ""]
               #:text-mode [text-mode 'auto] #:raster-dpi [raster-dpi 144]
               #:id-prefix [id-prefix #f] #:encoding-quality [quality #f])
(save-output page-or-pages path format
             #:exists [exists 'error]
             #:title [title ""] #:description [description ""]
             #:text-mode [text-mode 'auto] #:raster-dpi [raster-dpi 144]
             #:id-prefix [id-prefix #f] #:encoding-quality [quality #f])

(draw-output-page canvas page
                  #:text-mode [text-mode 'native] #:raster-dpi [raster-dpi 144])
(output-page->image page #:dpi [dpi 96] #:text-mode [text-mode 'native]
                        #:color-space [color-space #f])
```

An output page is an immutable, non-native value with a one-canvas drawing
callback. The callback must require no keywords; its return values are ignored.
It runs once per page per export, not once for the entire lifetime of the page.
Captured resources must remain live and obey the usual creator-thread rule.

Units are `'pt`, `'in`, `'mm`, `'cm`, or `'px` (CSS pixels). `unit->points` permits
signed finite lengths and preserves exact arithmetic when possible. Page width
and height must convert to 0.001–14400 points. Margins are a nonnegative scalar
or a four-element list in **left/top/right/bottom** order, in drawing units, and
must leave positive content width and height. The callback origin is moved to
the inner top-left corner. Content is clipped there unless `#:clip? #f`.
A background color paints the full page before that content clip; `#f` paints
nothing. Canvas state and output parameters are restored on every scoped exit.

Format is explicitly `'pdf` or `'svg`. PDF permits one page or a nonempty list;
SVG requires one page or a singleton list. Multiple SVG pages raise before any
callback. PDF dimensions are points; the shared SVG output has the same
point-valued viewBox and root width/height with `pt` units. CSS/zoom/print scaling
can still resize the result. The low-level SVG functions retain user-unit sizing.

Description maps to PDF subject / SVG `<desc>`. ID prefix is SVG-only and follows
the existing SVG prefix contract. Encoding quality is PDF-only, 0–101, with 101
meaning lossless. `#f` uses the format default. Options supplied to the wrong
format raise; they are not silently ignored. File publication uses the existing
completed-output temporary-file/rename helpers, with an absolute path resolved
before drawing. Use low-level APIs for additional format-specific metadata.

Text mode is `'auto`, `'native`, or `'outline`; auto chooses native for PDF and
outline for SVG. Raster DPI is a finite real in 1–9600. It controls PDF fallback
DPI and default explicit-group scale, not vector resolution. The derived scale
`dpi * points-per-unit / 72` must lie within 1/1024–1024 for every page. All pages
and options are checked before drawing the first page. Additional transforms
inside a callback do not automatically alter raster density.

`draw-output-page` assumes one current destination unit corresponds to one point,
before the page's unit conversion. It preserves the existing transform/clip.
`output-page->image` returns an independently owned snapshot with pixel sizes
`ceiling(point-size * dpi / 72)`, subject to raster dimension/byte limits. It is
a separate raster rendering of the callback, not a PDF/SVG rasterization.

### Scoped text policy and detached blob outlines

```racket
(current-text-output-mode)                 ; initial value: 'native
(current-text-output-mode 'outline)        ; accepts 'native or 'outline only
(current-raster-output-scale)              ; initial value: 1
(current-raster-output-scale scale)        ; finite 1/1024–1024
(text-blob->path text-blob)                 ; independent owned path
```

Use `parameterize` for scoped choices. Simple text, shaped runs, both paragraph
APIs, and prebuilt text blobs honor the text parameter at drawing time. The
low-level PDF/SVG helpers leave it alone. A pre-recorded picture cannot be
rewritten: its text representation was fixed when its commands were recorded.

`text-blob->path` uses private snapshotted font properties and copied glyph
positions retained at blob construction. It is independent of later source-font
mutation/closure or input-vector mutation. The result is baseline-local and
outlives the blob. Blob close releases its private font as well as its native
blob; each has independent GC fallback and remains thread-confined.

Outlines are geometry, not searchable/editable text. Glyphs without monochrome
outlines, including some bitmap/color glyphs, are omitted. Use an explicit raster
group to preserve their rendered pixels. Native text may have backend-specific
font/extraction behavior; this layer does not promise universal font embedding,
semantic text round trips, or exact small-size hinting equivalence.

## SVG documents

```racket
(svg-document? value)
(make-svg-document width height
                   #:title [title ""]
                   #:description [description ""]
                   #:id-prefix [id-prefix "skia"])
(svg-document-width svg)
(svg-document-height svg)
(svg-document-state svg)             ; open, finished, aborted, closed
(svg-document-canvas svg)            ; borrowed canvas, only while open
(svg-document-finish! svg)
(svg-document-abort! svg)
(svg-document->bytes svg)            ; independent mutable bytes, after finish
(svg-document->string svg)           ; UTF-8 string, after finish
(save-svg svg path #:exists [exists 'error])

(call-with-svg-bytes width height draw
                     #:title [title ""]
                     #:description [description ""]
                     #:id-prefix [id-prefix "skia"])
(call-with-svg-string width height draw
                      #:title [title ""]
                      #:description [description ""]
                      #:id-prefix [id-prefix "skia"])
(call-with-svg-file path width height draw
                    #:exists [exists 'error]
                    #:title [title ""]
                    #:description [description ""]
                    #:id-prefix [id-prefix "skia"])
```

SVG is a single-viewport output backend, not an SVG reader or a PDF page.
Its owned document is a `skia-resource?`, but not a PDF `document?`. It works
with `with-skia`, `skia-close!`, and the existing canvas drawing functions.
Width and height are finite reals from 0.001 through 32768 SVG user units;
queries return inexact values. The result has explicit width/height and
`viewBox="0 0 width height"`. No separately positioned viewBox is exposed.

The `draw` procedure receives one **canvas**, runs once, and may return any
number of values, which are ignored. Convenience helpers finish after a normal
return, copy the result, and release all native resources on any exit. Saved
canvas aliases become invalid. In the explicit API, finish is idempotent while
the wrapper is live and makes every borrowed canvas invalid, but the finished
document remains live for repeated reads/saves. Reads before finish or after
close raise. Abort discards even a previously finished result and is idempotent.
Finish inside a protected `with-canvas-state` scope raises; closing/aborting
inside such a scope is safe. Native operations retain the creator-thread rule.

Title/description are XML 1.0-compatible strings, escaped as UTF-8 `<title>` and
`<desc>` content; empty strings omit the elements. The ID prefix is 1–64 ASCII
characters, starting with a letter/underscore and then letters/digits/`_`/`.`/`-`.
Native resource IDs and attribute references are renumbered in definition order.
Use distinct prefixes for roots inserted inline in the same HTML document.
This improves repeatability of native clip IDs; it does not promise identical
font-dependent or cross-platform output.

File helpers require an existing parent directory and accept `'error` or
`'replace`. They complete the XML before writing a same-directory temporary
file and publishing it; drawing/finalization failures preserve an existing
file. The absolute destination is fixed before the callback. Byte limits apply
to metadata, native XML copies, postprocessed output, and readback, not to the
native stream's total allocation before finish. A vector viewport does not
allocate or charge a width-by-height RGBA buffer just for existing.

**Native SVG coverage is narrower than raster/PDF coverage.** The pinned C shim
has no exposed text-to-path/compact-XML flags. Native text may emit `<text>`
with font-family names but no font binaries, and its reverse glyph-to-Unicode
mapping can omit shaped glyphs or lose their semantics. General shader/filter/
blend/difference-clip operations are not guaranteed, and there is no blanket
automatic raster fallback. See the [SVG coverage table](SVG-OUTPUT.md#backend-coverage-and-limits).

### Explicit outline and raster helpers

```racket
(shaped-run->path shaper run) ; independent owned path, baseline-local positions
(draw-rasterized canvas x y width height draw
                 #:scale [scale (current-raster-output-scale)]
                 #:padding [padding 0] #:color-space [color-space #f])
```

`shaped-run->path` uses the supplied live shaper's snapshotted font and the
run's glyph IDs/positions. Supply the same shaper used for the run. The path
outlives the shaper; an empty run gives an empty path. Missing outlines,
including bitmap-only glyphs, are omitted, as with `simple-text-path`; color
emoji are not preserved by outlining. The result is geometry, not selectable
text. Use `simple-text-path` for unshaped labels and draw either with `draw-path`.
These helpers work on raster and PDF backends too.

`draw-rasterized` draws once into a transparent local raster canvas and embeds
its snapshot. The callback keeps local content bounds `(0,0)..(width,height)`.
Padding is a nonnegative scalar or `(list left top right bottom)` in those units;
it expands the image to `(x-left,y-top,width+left+right,height+top+bottom)` without
shrinking or moving the content. Scale is pixels per unit, a finite real from
1/1024 through 1024, defaulting to the scoped parameter (initially 1). Pixel sizes
are ceilings of the padded dimensions times scale and obey normal raster/byte
limits. Independent axis scaling accounts for integer rounding. The temporary
canvas is invalid after return. The optional color space tags the temporary
surface/snapshot; it does not introduce end-to-end ICC guarantees.

Raster callbacks temporarily use native text rendering even in an outer outline
scope, so bitmap/color glyphs can remain pixels. Destination-dependent blending
requires the backdrop inside the group; the existing destination is not captured.
Padding does not bypass the destination or page-content clip. Surrounding SVG
geometry remains vector; no blanket automatic fallback is introduced.

See [the SVG guide](SVG-OUTPUT.md) for complete examples and limitations.

## PDF documents

```racket
(document? value)
(make-pdf-document #:title [title ""] #:author [author ""]
                   #:subject [subject ""] #:keywords [keywords ""]
                   #:creator [creator "skia-for-racket"]
                   #:producer [producer "Skia/PDF m119; skia-for-racket"]
                   #:creation-date [creation-date #f]
                   #:modified-date [modified-date #f]
                   #:raster-dpi [raster-dpi 144]
                   #:encoding-quality [encoding-quality 101])
(document-state document)              ; open, page, finished, aborted, closed
(document-page-count document)         ; completed pages
(document-begin-page! document width height) ; borrowed canvas?
(document-end-page! document)
(document-finish! document)
(document-abort! document)
(document->pdf-bytes document)          ; independent copy; requires finish
(save-pdf document path #:exists [exists 'error]) ; requires finish
(call-with-document-page document width height procedure)
(with-document-page (canvas document width height) body ...)
(call-with-pdf-bytes procedure <same metadata/encoding keywords as make-pdf-document>)
(call-with-pdf-file path procedure #:exists [exists 'error]
                    <same metadata/encoding keywords as make-pdf-document>)
```

A document is an owned `skia-resource?` supported by `with-skia`; page canvases
are borrowed and must not be closed individually. Each page canvas expires
permanently when its page ends or its document is released. All existing draw,
clip, state, transform, text, image, and picture operations accept these canvases.
Native PDF representation/fallback may differ from raster rendering.

Page dimensions are finite reals in [0.001,14400], in points (72 per inch).
Coordinates remain top-left/y-down. Begin requires an open document between
pages; end requires an active page. Finish requires at least one completed page
and no active page, and is idempotent until release. State/page-count queries
are Racket-only and remain available after release. Other document operations
that access native state are thread-confined. Abort releases and discards output;
generic close aborts unfinished work and never writes a file implicitly.

The page procedure receives a canvas; the PDF helper procedure receives a
document. Page scopes preserve return values and end on success, but abort the
document on exceptions, breaks, or continuation escapes. Manual end is prohibited
inside a protected page or canvas-state scope. The byte/file helpers finish and
release their documents automatically; their procedure's values are ignored.
File helpers return void and publish through a same-directory temporary file
only after drawing and finalization succeed. Existing-file policy is error or
replace. No streaming port/native callback API is introduced.

Metadata strings must be NUL-free; dates are `#f` or valid Racket `date?` values
with year 1–9999, seconds 0–59, and integral-minute UTC offsets within +/-23:59.
Subseconds are not represented. DPI is finite in [1,9600] and affects fallback
rasterization, not page size. Encoding quality is an exact integer in [0,101];
101 requests lossless output, while 0–100 allows JPEG for opaque images.
PDF/A is not enabled. Metadata bytes, finalized output, and each copy are checked
against `current-skia-byte-limit`, not Skia's total intermediate memory.

See [PDF output](PDF-OUTPUT.md) for lifecycle details, limitations, and sources,
and [PDF tests](PDF-TESTING.md) for native and visual verification.

## Animated codecs and encoded orientation

```racket
(codec? value)
(codec-from-bytes encoded-bytes)        ; owned codec; input is copied
(codec-from-file path)                 ; owned codec; file is read into a snapshot
(codec-info codec)                     ; immutable encoded-image-info
(codec-frame-count codec)              ; decodable frames, including 1 for still images
(codec-repetition-count codec)         ; -1 infinite; 0 once; n additional repetitions
(codec-frame-info codec frame-index)   ; immutable metadata, or #f for a still image
(codec-color-space codec)              ; separately owned color-space or #f

(codec->image codec
              #:frame-index [frame-index 0]
              #:normalize-origin? [normalize-origin? #t]
              #:color-space [color-space #f])
(image-frame-from-bytes encoded-bytes [frame-index 0]
                        #:normalize-origin? [normalize-origin? #t]
                        #:color-space [color-space #f])
(image-frame-from-file path [frame-index 0]
                       #:normalize-origin? [normalize-origin? #t]
                       #:color-space [color-space #f])

(encoded-image-info-display-width info)
(encoded-image-info-display-height info)

(codec-frame-info? value)
(codec-frame-info-index info)
(codec-frame-info-required-frame info)
(codec-frame-info-duration info)
(codec-frame-info-fully-received? info)
(codec-frame-info-alpha-type info)
(codec-frame-info-has-alpha-within-bounds? info)
(codec-frame-info-disposal-method info)
(codec-frame-info-blend info)
(codec-frame-info-rect info)
```

A codec is an owned, creator-thread-confined native resource. Use `with-skia`
or close it with `skia-close!`. It owns a copy of the encoded input, so later
mutation of a caller's byte string, or modification/deletion of a source file,
does not change that codec. The file constructor bounds its snapshot read even
when a file grows between the initial size check and the read. Empty,
unrecognized, unsupported, or over-limit input raises an exception.

`codec-info` uses the existing `encoded-image-info` record. Its width and height
are the **encoded** dimensions; the two display-dimension accessors account
for orientation. Its `encoded-image-info-frame-count` preserves the native
animation-table count, which is commonly **0 for still images**. In contrast,
`codec-frame-count` is the number of selectable frames and is **1 for still
images**. Frame indexes are zero-based exact integers; out-of-range indexes
raise contract errors. For a still image with an empty animation table,
`(codec-frame-info codec 0)` returns `#f` rather than invented animation data.

Animation metadata is copied into immutable Racket values and remains valid
after the codec is closed. `required-frame` is a preceding frame index or `#f`
when no prior frame is required. `duration` is the encoded duration in
**milliseconds**, without a playback minimum or browser-style delay clamping.
`fully-received?` reports native frame completeness. `alpha-type` uses the
ordinary image alpha-type symbols. `has-alpha-within-bounds?` describes the
encoded frame rectangle, not necessarily the fully composited canvas.
`disposal-method` is `'keep`, `'restore-background`, or `'restore-previous`;
`blend` is `'src` or `'src-over`. `rect` is an immutable
`#(x y width height)` in **encoded coordinates**, including when decoded output
is orientation-normalized. Metadata does not imply successful pixel decoding.

The repetition count is not a total-play count: `-1` means indefinitely,
`0` means play once, and a positive integer means that many repetitions after
the first play. For example, `2` means three complete plays. Playback scheduling
and disposal are different concepts: the caller schedules durations, while
Skia handles the frame dependencies, blending, and disposal during decoding.

`codec->image` eagerly decodes a **fully composited, full-canvas** frame, not an
isolated subframe rectangle. Each call starts with fresh zeroed pixels and
passes `fPriorFrame = -1`, asking Skia to reconstruct all required frames.
Calls in reverse or arbitrary order do not depend on an earlier call's pixel
buffer. This deliberately favors correctness and independent results over a
sequential playback cache: dependencies may be decoded repeatedly. The codec
itself is mutable native state and must not be shared across Racket threads.
The returned image owns an independent raster copy and remains usable after
closing the codec. Its `image-original-encoded-bytes` result is `#f`.

Normalization is enabled by default in the **new** frame-decoding functions.
All eight encoded origins are handled, including mirrors and transposes;
origins 5 through 8 swap the dimensions. Normalization permutes packed pixels
without interpolation or channel arithmetic. With `#:normalize-origin? #f`,
the output remains in encoded coordinates. The existing `image-from-bytes`
and `image-from-file` functions retain their previous behavior. Re-encoding a
normalized raster does not retain an EXIF instruction that would rotate it a
second time.

A `#:color-space` argument converts the decoded pixels to that color space.
The default `#f` preserves the source color-space tag when one is available;
it does not remove that tag or request an arbitrary reinterpretation. Decoding
uses premultiplied RGBA8888 internally. `codec-color-space` returns a separately
owned reference that the caller must close; it can outlive the codec. Returned
images likewise retain their color-space tag independently of caller wrappers.

Every native decode result other than success raises an exception, including
`incomplete-input`; no partially decoded raster is silently returned. Encoded
snapshot sizes and requested raster sizes respect `current-skia-byte-limit`.
This remains a **per-buffer limit**, not a total native-heap or aggregate-memory
limit: normalization can allocate another raster-sized buffer, and the returned
image is a native copy. Animation encoding, incremental/streaming decode,
subsampling, and a sequential-frame cache are not provided by this API.

For executable examples and regression coverage, see
[`CODEC-TESTING.md`](CODEC-TESTING.md) and `examples/advanced-codecs.rkt`.

## Conventions

Coordinates accept finite real numbers within the checked C-float range.
Lengths, radii, stroke widths, and rectangle extents must be nonnegative.
Native geometry uses single-precision floats, not arbitrary-precision Racket
numbers. Surface/image dimensions must be exact integers from 1 to 32768 and
must respect the byte limit. Zero-area drawing rectangles are allowed.

The initial coordinate system has x right, y down, origin at the top left.
Rectangles always use `(x y width height)`. Mutating/drawing operations return
void unless another return value is described. Predicates accept any value.
Native resources are thread-confined; see the ownership section.

## Colors

```racket
(rgba red green blue alpha) ; transparent immutable structure, four bytes
(rgb red green blue)       ; equivalent to (rgba red green blue 255)
(rgba? value)
(rgba-red c) (rgba-green c) (rgba-blue c) (rgba-alpha c)
(color? value)
(color->rgba value)
(color->argb value)         ; unsigned integer #xAARRGGBB
```

Every channel, including alpha, is an exact byte. Accepted color inputs:

| Input | Interpretation |
|---|---|
| `rgba` value | Straight RGBA, not premultiplied |
| `"#RRGGBB"` | Opaque hex color |
| `"#RRGGBBAA"` | Hex color with alpha last |
| Integer from 0 to #xffffffff | Packed #xAARRGGBB, alpha first |
| Named symbol | One of the names below |

Names: `transparent`, `black`, `white`, `red`, `green`, `blue`, `yellow`,
`cyan`, `magenta`, `gray`, `grey`, `orange`, `purple`. `green` is #008000;
`gray`/`grey` is #808080. Hex digits are case-insensitive. Named strings,
three-digit hex, normalized float channels, and CSS color expressions are not
accepted. `color?` validates without loading the native library.

## Native library diagnostics

```racket
native-package-version       ; "3.119.1"
(skia-check!)                ; load, check milestone, resolve required symbols
(skia-available?)            ; #t if skia-check! succeeds; #f on load failure
(skia-native-version)        ; string "119.<native increment>"
(skia-native-library-path)   ; selected filename or system loader name
```

Native loading is lazy. `skia-check!` raises an exception with loader details;
`skia-available?` suppresses that exception. Failure is cached in the process's
loading promise. Start a new process after fixing a load error. The version
string is the native Skia milestone/increment, not the NuGet package version.
Do not interpret the milestone probe as full binary compatibility validation.

## Ownership and limits

```racket
(skia-resource? value)  ; surface, paint, shader, path-effect, color/mask/image filters,
                        ; color-space, path, path-measure, image, font-manager, typeface,
                        ; font, text-blob; not borrowed canvas
(skia-closed? resource-or-canvas)
(skia-close! resource)
(call-with-skia-resource resource procedure-of-one-argument)
(with-skia ([name expression] ...) body ...)
current-skia-byte-limit ; parameter, default (* 256 1024 1024)
```

Each owned wrapper has one lifetime cell. Closing invalidates aliases before
calling its native destructor. Explicit closure is idempotent. A live canvas
keeps its owning surface reachable, but cannot prevent explicit surface
closure; subsequent canvas operations then raise instead of using freed memory.
Passing a canvas to `skia-close!` is an error.

`with-skia` is sequential: later bindings may use earlier bindings. Cleanup
occurs in reverse order after normal return, an exception, or a later
constructor failure. Body return values are preserved. It uses continuation
barriers, so re-entering an expired resource scope is unsupported. The
procedure form has the same semantics and receives its resource as an argument.
Do not escape by terminating the entire process and expect dynamic cleanup.

GC finalization is a fallback; neither immediate reclamation nor custodian
resource management is provided. Every native resource may only be used or
explicitly closed on its creating Racket thread. Type predicates, immutable
metadata accessors, and `skia-closed?` do not access native memory.

The byte limit guards requested surface/pixel sizes, encoded input, and copied
encoded output, not total memory consumption or codec/encoder internal
allocations. Set it with `parameterize` before allocating or reading larger
images. Metadata probing itself does not allocate a decoded pixel buffer.

## Surfaces and PNG

```racket
(surface? value)
(make-surface width height #:background [color 'transparent]
              #:color-space [color-space-or-false #f])
(surface-width surface)
(surface-height surface)
(surface-canvas surface) ; borrowed canvas, shares the surface's graphics state
(surface-pixel surface x y) ; one rgba value, exact pixel indices
(surface->rgba-bytes surface #:premultiplied? [flag #f]
                       #:color-space [color-space-or-false #f])
(surface->png-bytes surface #:compression [level 6])
(save-png surface path #:exists [mode 'error] #:compression [level 6])
```

A new surface is initialized to its background color; it never exposes
uninitialized pixels. Internal storage is CPU RGBA8888 with premultiplied
alpha. `#:color-space #f` retains the original untagged behavior; supplying a
`color-space?` associates that native color space with the raster. Pixel
readback copies data into ordinary Racket byte strings; default output is
straight RGBA. With `#:color-space`, readback converts into the requested
destination space. Rows are contiguous with stride `4*width`.

PNG is encoded by Skia's native PNG encoder, not `racket/draw`. Compression is
an exact integer from 0 through 9. All PNG scanline filters are enabled. PNG
byte output contains the full image. `save-png` accepts only `'error` (default,
refuse existing files) or `'replace` (explicitly overwrite). Encoding finishes
before opening the output file; filesystem write failures are still possible,
and file writes are not transactional. Parent directories are not created.
The two pixel-output flags must be booleans.

## Paints

```racket
(paint? value)
(make-paint #:color [color 'black]
            #:style [style 'fill]
            #:stroke-width [width 1]
            #:antialias? [flag #t]
            #:cap [cap 'butt]
            #:join [join 'miter]
            #:miter-limit [limit 4]
            #:blend-mode [mode 'src-over]
            #:shader [shader-or-false #f]
            #:path-effect [path-effect-or-false #f]
            #:color-filter [color-filter-or-false #f]
            #:mask-filter [mask-filter-or-false #f]
            #:image-filter [image-filter-or-false #f])
(paint-copy paint)
(paint-color paint) ; rgba value
(paint-shader paint) ; newly owned shader or #f
(paint-path-effect paint) ; newly owned path effect or #f
(paint-color-filter paint) ; newly owned color filter or #f
(paint-mask-filter paint) ; newly owned mask filter or #f
(paint-image-filter paint) ; newly owned image filter or #f
(paint-set-color! paint color)
(paint-set-style! paint style)
(paint-set-stroke-width! paint width)
(paint-set-antialias! paint boolean)
(paint-set-cap! paint cap)
(paint-set-join! paint join)
(paint-set-miter-limit! paint limit)
(paint-set-blend-mode! paint mode)
(paint-set-shader! paint shader-or-false)
(paint-set-path-effect! paint path-effect-or-false)
(paint-set-color-filter! paint color-filter-or-false)
(paint-set-mask-filter! paint mask-filter-or-false)
(paint-set-image-filter! paint image-filter-or-false)
```

Styles: `'fill`, `'stroke`, `'stroke-and-fill`. Caps: `'butt`, `'round`,
`'square`. Joins: `'miter`, `'round`, `'bevel`. Width 0 requests Skia's hairline
stroke semantics, not an invisible stroke. The default is fill; request stroke
explicitly when drawing open curves. `draw-line` uses line-stroke semantics.
Paints are mutable; `paint-copy` creates an independently owned copy.
A paint may hold a shader, path effect, color filter, mask filter, and image
filter simultaneously. The native paint retains its own references, so wrappers
supplied to `make-paint` or any corresponding setter may be closed immediately
after the call. All five setters accept `#f` to remove the corresponding object.
The five getter functions return `#f` or a **newly owned** wrapper; closing that
wrapper does not change the paint. In the pinned m119 C shim these getters use
`ref...().release()`, so the returned pointer already owns one native reference
and the Racket wrapper does not add another ref.

Blend modes:

```racket
'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in 'src-out 'dst-out
'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten
'color-dodge 'color-burn 'hard-light 'soft-light 'difference 'exclusion
'multiply 'hue 'saturation 'color 'luminosity
```

The wrapper maps these names to the pinned native enumeration. It does not
implement separate blend math in Racket. Alpha is supplied through the paint
color; there is no separate normalized-alpha API.

## Shaders and gradients

```racket
(shader? value)
(make-color-shader color)
(make-linear-gradient-shader x0 y0 x1 y1 colors
                             #:positions [positions #f]
                             #:tile-mode [mode 'clamp])
(make-radial-gradient-shader center-x center-y radius colors
                             #:positions [positions #f]
                             #:tile-mode [mode 'clamp])
(make-sweep-gradient-shader center-x center-y colors
                            #:positions [positions #f]
                            #:tile-mode [mode 'clamp]
                            #:start-angle [degrees 0]
                            #:end-angle [degrees 360])
(make-two-point-conical-gradient-shader
 x0 y0 radius0 x1 y1 radius1 colors
 #:positions [positions #f]
 #:tile-mode [mode 'clamp])
(make-image-shader image
                   #:tile-x [mode 'clamp]
                   #:tile-y [mode 'clamp]
                   #:sampling [sampling 'nearest])
(make-blend-shader blend-mode destination-shader source-shader)
```

A shader is an owned, reference-counted Skia resource. Close it explicitly or
manage it with `with-skia`. Native paints, image shaders, and blend shaders
retain the native references they need; there is no requirement to keep the
Racket wrappers for their inputs alive after construction.

`colors` is a list or vector containing at least two values accepted by
`color?`. `positions` is `#f` for evenly distributed stops, or a list/vector of
the same length as `colors`. Positions must be finite numbers in the closed
interval 0 through 1 and must be nondecreasing. Stop arrays are temporary:
the native call consumes them synchronously and the resulting shader does not
retain pointers into Racket-managed storage.

Gradient and image tile modes are:

```racket
'clamp 'repeat 'mirror 'decal
```

`'clamp` extends the edge color, `'repeat` repeats the shader domain, `'mirror`
alternates reflected copies, and `'decal` is transparent outside the domain.
Linear-gradient endpoints must be distinct. A radial radius must be positive.
The two circles of a conical gradient must differ and their radii are
nonnegative. Sweep angles are degrees and require start < end; 0 through 360
is the default full sweep.

Image shaders use the immutable contents of an `image?` and support the same
`'nearest` and `'linear` sampling choices as image drawing. The image can be
closed after successful shader construction because the shader owns the native
reference it needs.

`make-blend-shader` combines two shader outputs using any blend mode listed in
the Paints section. Its argument order follows Skia: first destination, then
source. For example, `(make-blend-shader 'multiply a b)` evaluates `a` as the
destination and `b` as the source before applying multiply.

`shader-with-local-matrix` creates a shader with an affine local transform.
Canvas transforms still affect the complete drawing operation. The pinned SVG
serializer does not reliably serialize shader-local transforms; use a bounded
`draw-rasterized` group for these shaders when exporting SVG.

## Path effects

```racket
(path-effect? value)
(make-dash-path-effect intervals [phase 0])
(make-corner-path-effect radius)
(make-discrete-path-effect segment-length deviation [seed 0])
(make-trim-path-effect start stop #:mode [mode 'normal])
(make-compose-path-effect outer inner)
(make-sum-path-effect first second)
```

A path effect is an owned, reference-counted Skia resource. It is normally used
with a stroke paint through `#:path-effect` or `paint-set-path-effect!`.
`make-dash-path-effect` accepts a list or vector with an even number of
nonnegative lengths, at least two entries, and not all zero. Zero entries are
allowed; for example, round caps plus `(0 gap)` can produce dots. `phase` is a
finite scalar.

`make-corner-path-effect` requires a positive radius. The discrete effect
requires a segment length greater than 1/4096, nonnegative deviation, and an
optional 32-bit unsigned seed; a fixed seed makes Skia's perturbation deterministic for
the same path. Trim positions are normalized contour fractions satisfying
`0 <= start < stop <= 1`; mode is `'normal` or `'inverted`. The full normal
span `(0,1)` is rejected because upstream represents it as no path effect (a
no-op) rather than an allocated effect.

Compose applies `inner` and then `outer`, following Skia's composition model.
Sum evaluates both effects and combines their resulting geometry. Both
constructors retain the native references they need, so the input wrappers may
be closed after successful construction.

## Color, mask, and image filters

```racket
(color-filter? value)
(make-color-matrix-filter matrix)
(make-blend-color-filter color blend-mode)
(make-compose-color-filter outer inner)

(mask-filter? value)
(make-blur-mask-filter sigma
                       #:style [style 'normal]
                       #:respect-ctm? [flag #t])

(image-filter? value)
(make-blur-image-filter sigma-x sigma-y
                        #:tile-mode [mode 'decal]
                        #:input [image-filter-or-false #f])
(make-drop-shadow-image-filter dx dy sigma-x sigma-y color
                               #:input [image-filter-or-false #f])
(make-drop-shadow-only-image-filter dx dy sigma-x sigma-y color
                                    #:input [image-filter-or-false #f])
(make-color-filter-image-filter color-filter
                                #:input [image-filter-or-false #f])
(make-compose-image-filter outer inner)
```

All three filter families are owned, reference-counted Skia resources. Paints
and composed filter graphs retain the native references they need, so input
wrappers may be closed after successful attachment or construction. The paint
getters return independent owned references.

A color matrix is a list or vector of exactly 20 finite scalars in Skia's
row-major 4×5 order. Conceptually it transforms `(R,G,B,A,1)` into new RGBA
channels. `make-blend-color-filter` accepts the paint blend-mode names from the
Paints section. `'dst` is rejected because upstream represents that exact no-op
as a null filter rather than an allocated object. Compose evaluates `inner`
first and then `outer`.

`make-blur-mask-filter` applies a Gaussian mask blur. `sigma` must be positive.
Styles are `'normal`, `'solid`, `'outer`, and `'inner`. With
`#:respect-ctm? #t` (the default), Skia scales the blur sigma with the current
canvas transform; `#f` requests a device-independent sigma.

Image-filter inputs form a native DAG. Supplying `#f` for `#:input` means “use
the dynamically rendered source”. Blur sigmas are nonnegative and at least one
must be positive. Its tile mode is one of `'clamp`, `'repeat`, or `'decal`;
the pinned m119 Skia documentation explicitly says mirror tiling is unsupported
for blur image filters, so this wrapper rejects `'mirror` for that constructor.

A drop-shadow filter includes the original input plus the shadow;
`make-drop-shadow-only-image-filter` emits only the shadow. Shadow offsets are
finite scalars and sigmas are nonnegative. `make-color-filter-image-filter`
turns a color filter into an image-filter node. `make-compose-image-filter`
computes `outer(inner(source))`.

This first filter layer does not yet expose crop rectangles, arithmetic/merge,
morphology, displacement, matrix convolution/transform, lighting, table filters,
or runtime-effect filters.

## Canvas state and transforms

```racket
(canvas? value)
(canvas-clear! canvas color)
(canvas-save! canvas)          ; previous save count
(canvas-save-count canvas)     ; current count, initially 1
(canvas-restore! canvas)
(canvas-restore-to-count! canvas count)
(call-with-canvas-state canvas thunk)
(with-canvas-state canvas body ...)
(canvas-translate! canvas dx dy)
(canvas-scale! canvas sx [sy sx])
(canvas-rotate! canvas degrees)
(canvas-rotate-radians! canvas radians)
(canvas-skew! canvas kx ky)
(canvas-reset-transform! canvas)
```

Transforms concatenate onto the current matrix. Scaling can be negative or
zero. `canvas-skew!` takes shear factors, not angles. Reset changes the matrix,
not clipping or previously drawn pixels. Clear replaces pixels within the
current clip with the specified color and ignores the current transform.
To clear the entire surface, do so before introducing clipping or restore the
unclipped base state first.

Save/restore retains the matrix and clip, not paints and not pixel history.
Restoring the base state itself is an error. `restore-to-count!` accepts only
an existing positive count at or above the active scope's protected floor.
A scoped state reserves its save frame, restores its entry count on exit, and
removes extra saves made in the body. Manual restore cannot pop that reserved
frame, including through another canvas alias. Closing the surface in the body
is allowed; state cleanup then avoids accessing the invalidated pointer.

## Clipping

```racket
(canvas-clip-rect! canvas x y width height
                   #:operation [operation 'intersect]
                   #:antialias? [flag #f])
(canvas-clip-path! canvas path
                   #:operation [operation 'intersect]
                   #:antialias? [flag #f])
```

Operation is `'intersect` or `'difference`. The shape is interpreted using the
current transform. Clipping changes future drawing; it does not retroactively
edit pixels. Use a state scope to make a temporary clip. Path clipping uses the
path's fill rule, not a paint's stroke settings.

## Drawing geometry

```racket
(draw-paint canvas paint)
(draw-line canvas x0 y0 x1 y1 paint)
(draw-rect canvas x y width height paint)
(draw-rounded-rect canvas x y width height radius-x radius-y paint)
(draw-circle canvas center-x center-y radius paint)
(draw-oval canvas x y width height paint)
(draw-path canvas path paint)
(draw-polygon canvas points paint #:closed? [flag #t])
```

`draw-paint` covers the current clip. Other operations apply the canvas
transform and clipping. `points` is a nonempty list of two-element lists,
for example `'((10 10) (90 20) (40 80))`. The polygon helper constructs and
closes a temporary path automatically. Pass `#:closed? #f` for an open polyline;
use a stroke paint to avoid implicit filled-contour closure by the rasterizer.
Rectangles with excessively large corner radii use Skia's radius fitting.

## Paths

```racket
(skia-path? value)
(make-path [commands '()] #:fill-rule [rule 'winding])
(path-copy path)
(path-move-to! path x y)
(path-line-to! path x y)
(path-quad-to! path control-x control-y x y)
(path-cubic-to! path c1x c1y c2x c2y x y)
(path-close! path)
(path-reset! path)
(path-add-rect! path x y width height #:direction [direction 'cw])
(path-add-oval! path x y width height #:direction [direction 'cw])
(path-add-circle! path x y radius #:direction [direction 'cw])
(path-bounds path)        ; FOUR VALUES: x, y, width, height
(path-tight-bounds path)  ; FOUR VALUES: x, y, width, height
(path-contains? path x y)
(path-fill-rule path)
(path-set-fill-rule! path rule)
(path-op path-a path-b operation)
(path-union path-a path-b)
(path-intersect path-a path-b)
(path-difference path-a path-b)
(path-xor path-a path-b)
(path-reverse-difference path-a path-b)
(path-simplify path)
(path-as-winding path)
```

The predicate is deliberately `skia-path?`, leaving Racket's filesystem
`path?` unshadowed. Paths are mutable and own their native object. `path-copy`
creates an independent copy. The command grammar is:

```racket
(move x y)
(line x y)
(quad control-x control-y x y)
(cubic c1x c1y c2x c2y x y)
(close)
```

Supply commands as Racket lists, normally quoted or quasiquoted. The native
path is cleaned up if a command is invalid. Fill rules are `'winding` or
`'even-odd`; directions are `'cw` or `'ccw` in the default y-down coordinates.
`path-reset!` clears geometry **and resets the fill rule to winding**.

Bounds are in path coordinates, independent of canvas transforms and paint
stroke widths. Ordinary bounds include Bézier control points; tight bounds
consider curve extrema. Neither reports the extent of a rendered stroke.
Containment tests the filled path interior, not stroke-distance hit testing.
For a list of bounds, use `(call-with-values (lambda () (path-bounds p)) list)`.

Boolean operations return newly owned paths and raise if Skia reports an
operation failure. `path-op` accepts `'difference`, `'intersect`, `'union`,
`'xor`, or `'reverse-difference`; the named helpers select those operations.
`path-simplify` resolves self-intersections/overlaps according to Skia PathOps.
`path-as-winding` returns equivalent filled geometry expressed with winding
fill where the native conversion succeeds.

## Path measurement

```racket
(path-measure? value)
(make-path-measure path
                   #:force-closed? [flag #f]
                   #:res-scale [scale 1])
(path-measure-set-path! measure path-or-false
                        #:force-closed? [flag #f])
(path-measure-length measure)
(path-measure-closed? measure)
(path-measure-position+tangent measure distance)
  ; FOUR VALUES: x, y, tangent-x, tangent-y
  ; all four are #f when the current contour has no measurable point
(path-measure-segment measure start stop
                      #:start-with-move-to? [flag #t])
  ; -> newly owned skia-path? or #f if native extraction fails
(path-measure-next-contour! measure) ; -> boolean
```

Measurements are contour-based. `path-measure-length`, `path-measure-closed?`,
position/tangent queries, and segment extraction operate on the current contour;
`path-measure-next-contour!` advances and returns `#t` while another contour
exists. Distances are checked against the current contour: they must be
nonnegative and at most its measured length. Segment extraction additionally
requires `start < stop`.

The public wrapper has **snapshot semantics**. Raw `SkPathMeasure` stores a
pointer to path data rather than owning a ref-counted path. To prevent use after
free through explicit Racket closure or later mutation, `make-path-measure`
clones the source path into private native storage. `path-measure-set-path!`
replaces that private snapshot atomically; passing `#f` clears the measure.
Closing or mutating the original path therefore does not affect an existing
measure. The private snapshot is destroyed immediately after the native
measure, including GC fallback cleanup.

`#:force-closed? #t` asks Skia to measure each open contour as though a closing
segment were present. `#:res-scale` is a positive finite scalar controlling
Skia's curve-measurement resolution; 1 is the native default.

## Images and codecs

### Image resources and raw pixels

```racket
(image? value)
(image-width image)
(image-height image)
(image-color-type image)
(image-alpha-type image)
(image-color-space image)
(surface-snapshot surface)
(rgba-bytes->image width height pixels #:premultiplied? [flag #f]
                   #:color-space [color-space-or-false #f])
(image->rgba-bytes image #:premultiplied? [flag #f]
                   #:color-space [color-space-or-false #f])
```

Images expose immutable pixel content but are owned resources that must be
closed. A snapshot remains valid after its source surface changes or closes.
RGBA input is copied, not borrowed, and must contain exactly `4*width*height`
bytes in top-to-bottom row order. In premultiplied input every RGB channel must
be at most alpha; invalid input is rejected. Output is copied as for surfaces.

`image-color-type` and `image-alpha-type` report Skia's native image metadata
as symbols. Alpha types are `'unknown`, `'opaque`, `'premul`, or `'unpremul`.
Color types currently mirror the pinned m119 enumeration, including
`'rgba-8888`, `'bgra-8888`, `'gray-8`, `'rgba-f16`, `'rgba-f32`, and the other
formats documented by Skia. These report the image's representation; use
`image->rgba-bytes` when a normalized RGBA8888 copy is wanted.

### Decode encoded images

```racket
(image-from-bytes encoded-bytes)
(image-from-file path)
(image-original-encoded-bytes image) ; -> bytes? or #f
```

`image-from-bytes` copies a nonempty encoded byte string into native immutable
`SkData` and asks Skia to create a deferred image. `image-from-file` reads
through Skia's native data API after checking that the path names a nonempty
regular file. The resulting image owns all native state it needs; no pointer to
Racket-managed byte storage is retained.

The encoded input length is limited by `current-skia-byte-limit`. Decoded image
dimensions must also satisfy the normal surface/image dimension and RGBA byte
limits before a wrapper is returned. Codec availability is determined by the
pinned native SkiaSharp build; PNG, JPEG, and WebP are exercised by this
version's native regression tests.

`image-original-encoded-bytes` asks Skia whether the image still retains its
original encoded representation. It returns a fresh Racket byte string when
one exists and `#f` otherwise. In particular, an image decoded by
`image-from-bytes` normally retains the supplied encoded data, while raster
images, snapshots, and transformed/subset images need not have such data.

### Probe encoded image metadata

```racket
(encoded-image-info? value)
(encoded-image-info-from-bytes encoded-bytes)
(encoded-image-info-from-file path)
(encoded-image-info-width info)
(encoded-image-info-height info)
(encoded-image-info-format info)
(encoded-image-info-color-type info)
(encoded-image-info-alpha-type info)
(encoded-image-info-origin info)
(encoded-image-info-frame-count info)
```

The probe constructors use Skia's codec header/metadata interface rather than
materializing an `image?`. The returned `encoded-image-info` is an immutable
Racket value and owns no native resource. Known format symbols in the pinned
ABI are:

```racket
'bmp 'gif 'ico 'jpeg 'png 'wbmp 'webp 'pkm 'ktx
'astc 'dng 'heif 'avif 'jpeg-xl
```

Encoded origins are `'top-left`, `'top-right`, `'bottom-right`, `'bottom-left`,
`'left-top`, `'right-top`, `'right-bottom`, or `'left-bottom`. This API reports
the encoded orientation; it does not itself normalize or rotate pixels.

A subtle m119 ABI detail: `encoded-image-info-frame-count` reflects the size of
Skia's frame-info vector. A non-animated codec can therefore report **0**, not
1. Treat a positive value as available animation frame information rather than
assuming that every still image has a one-frame count.

### Encode images

```racket
(image->png-bytes image #:compression [level 6])
(image->jpeg-bytes image
                   #:quality [quality 90]
                   #:downsample [mode 'yuv-420]
                   #:alpha [mode 'ignore])
(image->webp-bytes image
                   #:quality [quality 90]
                   #:lossless? [flag #f])

(image->encoded-bytes image format
                      #:quality [quality 90]
                      #:png-compression [level 6]
                      #:jpeg-downsample [mode 'yuv-420]
                      #:jpeg-alpha [mode 'ignore]
                      #:webp-lossless? [flag #f])

(save-image image path format
            #:exists [mode 'error]
            #:quality [quality 90]
            #:png-compression [level 6]
            #:jpeg-downsample [mode 'yuv-420]
            #:jpeg-alpha [mode 'ignore]
            #:webp-lossless? [flag #f])
```

The supported output format symbols are `'png`, `'jpeg`, and `'webp`. Encoding
first obtains a CPU raster representation and passes its borrowed pixmap to the
corresponding native Skia encoder. The resulting native data is copied into a
fresh Racket byte string before temporary streams/pixmaps are released.

PNG compression is an exact integer 0 through 9 and uses all PNG filters. JPEG
quality is an exact integer 0 through 100. JPEG downsampling is `'yuv-420`,
`'yuv-422`, or `'yuv-444`; alpha handling is `'ignore` or `'blend-on-black`.
WebP quality is any finite real from 0 through 100 and `#:lossless? #t` selects
Skia's lossless WebP encoder mode. Options irrelevant to the selected generic
format are ignored.

`save-image` encodes completely before opening the destination, so an encoder
failure cannot truncate an existing file. `#:exists` is `'error` or `'replace`,
with the same behavior as `save-png`. Output filename extensions are not used
to select a codec; the explicit `format` argument controls encoding.

### Subsets and drawing

```racket
(image-subset image x y width height)

(draw-image canvas image x y
            #:sampling [mode 'nearest]
            #:paint [paint-or-false #f])
(draw-image-rect canvas image x y width height
                 #:sampling [mode 'linear]
                 #:paint [paint-or-false #f])
(draw-image-subrect canvas image
                    source-x source-y source-width source-height
                    destination-x destination-y destination-width destination-height
                    #:sampling [mode 'linear]
                    #:paint [paint-or-false #f])
```

`image-subset` requires an exact-integer source rectangle with positive width
and height fully inside the image. It returns a new owned immutable image.

Sampling is `'nearest` or `'linear`. `draw-image` places the image at its
natural size before the canvas transform. `draw-image-rect` maps the **entire
source image** to the destination rectangle. `draw-image-subrect` instead maps
the supplied source rectangle to the supplied destination rectangle without
allocating an intermediate subset image. Source coordinates/extents for the
drawing operation are finite nonnegative reals and must remain inside the
image. The optional paint is passed to Skia for image compositing; `#f` requests
native defaults.

## Font managers, typefaces, fonts, text blobs, and simple text


### Font managers and fallback

```racket
(font-manager? value)
(make-font-manager)
(default-font-manager)
(font-manager-family-count manager)
(font-manager-family-name manager index)
(font-manager-families manager)
(font-manager-match-family manager family
                           #:weight [weight 'normal]
                           #:width [width 'normal]
                           #:slant [slant 'upright])
(font-manager-match-character manager character
                              #:family [family #f]
                              #:weight [weight 'normal]
                              #:width [width 'normal]
                              #:slant [slant 'upright]
                              #:languages [languages '()])
```

A font manager is an owned native `SkFontMgr` reference. `make-font-manager`
asks Skia to create a default platform font manager; `default-font-manager`
returns an independently owned reference to Skia's shared default manager.
Both wrappers are closed with the normal `skia-close!`/`with-skia` machinery.

Family indices range from zero through one less than
`font-manager-family-count`. `font-manager-family-name` raises on an invalid
index; `font-manager-families` returns all names as newly copied Racket
strings.

`font-manager-match-family` asks the manager for the closest face matching the
requested family/style and returns a newly owned `typeface?` or `#f`.
`font-manager-match-character` additionally asks for a face containing one
Unicode scalar. `family` may be `#f` to allow fallback across all families.
`languages` is an ordered list of NUL-free BCP-47 language-tag strings passed
to Skia as fallback hints. The binding does not parse or rewrite those tags.
The returned typeface, when non-false, owns its native reference independently
of the manager.

On platforms/native packages without a usable system font manager, enumeration
can be empty and matching can return `#f`; this is a platform capability, not a
shaping fallback performed in Racket.

### Typefaces

```racket
(typeface? value)
(make-typeface)
(typeface-from-family family
                      #:weight [weight 'normal]
                      #:width [width 'normal]
                      #:slant [slant 'upright])
(typeface-from-file path #:index [index 0])
(typeface-family-name typeface)
(typeface-weight typeface)
(typeface-width typeface)
(typeface-slant typeface)
```

A typeface is an owned native resource. `make-typeface` returns the platform
Skia default typeface. `typeface-from-family` asks Skia/platform font services
for a family and style. The returned face can be a platform-selected match, so
inspect `typeface-family-name`, `typeface-weight`, `typeface-width`, and
`typeface-slant` when the exact matched face matters.

`weight` accepts an exact integer from 0 through 1000 or one of:

```racket
'invisible 'thin 'extra-light 'light 'normal 'medium
'semi-bold 'bold 'extra-bold 'black 'extra-black
```

The named values map to 0, 100, 200, ..., 1000 respectively. `width` accepts
an exact integer from 1 through 9 or:

```racket
'ultra-condensed 'extra-condensed 'condensed 'semi-condensed 'normal
'semi-expanded 'expanded 'extra-expanded 'ultra-expanded
```

`slant` is `'upright`, `'italic`, or `'oblique`. `typeface-weight` and
`typeface-width` return the numeric native values; `typeface-slant` returns a
symbol.

`typeface-from-file` opens a local font file. `index` is an exact nonnegative
integer and selects a face in a collection where the native codec supports it.
The file must already exist. The wrapper passes an absolute NUL-terminated path
to the pinned native API and does not retain Racket path storage afterward.

### Fonts

```racket
(font? value)
(make-font [typeface #f]
           #:size [size 12]
           #:scale-x [scale-x 1]
           #:skew-x [skew-x 0]
           #:edging [edging 'antialias]
           #:hinting [hinting 'normal]
           #:subpixel? [flag #f]
           #:linear-metrics? [flag #f]
           #:embolden? [flag #f])

(font-size font)
(font-set-size! font size)
(font-scale-x font)
(font-set-scale-x! font scale-x)
(font-skew-x font)
(font-set-skew-x! font skew-x)
(font-edging font)
(font-set-edging! font edging)
(font-hinting font)
(font-set-hinting! font hinting)
(font-subpixel? font)
(font-set-subpixel! font boolean)
(font-linear-metrics? font)
(font-set-linear-metrics! font boolean)
(font-embolden? font)
(font-set-embolden! font boolean)
```

A font is an owned native `SkFont` wrapper. If no typeface is supplied,
`make-font` creates and retains a private default typeface for the lifetime of
the font wrapper. If the caller supplies a typeface, closing the font never
closes that wrapper. The native font retains what it needs from the face, so a
caller-supplied typeface wrapper may be closed after successful font creation.

`size` and `scale-x` must be positive finite scalars; `skew-x` is any checked
finite scalar. `edging` is `'alias`, `'antialias`, or `'subpixel-antialias`.
`hinting` is `'none`, `'slight`, `'normal`, or `'full`. The three boolean
options expose Skia's corresponding low-level font flags; they do not add a
layout or shaping engine.

### Metrics

```racket
(font-get-metrics font) ; -> font-metrics?
(font-metrics? value)
(font-metrics-top metrics)
(font-metrics-ascent metrics)
(font-metrics-descent metrics)
(font-metrics-bottom metrics)
(font-metrics-leading metrics)
(font-metrics-average-character-width metrics)
(font-metrics-max-character-width metrics)
(font-metrics-x-min metrics)
(font-metrics-x-max metrics)
(font-metrics-x-height metrics)
(font-metrics-cap-height metrics)
(font-metrics-underline-thickness metrics)
(font-metrics-underline-position metrics)
(font-metrics-strikeout-thickness metrics)
(font-metrics-strikeout-position metrics)
(font-metrics-spacing metrics)
```

`font-metrics` is an immutable Racket value copied from native metrics. In the
usual y-down canvas convention ascent/top are normally negative and
descent/bottom positive relative to the baseline. `spacing` is the value
returned by the native metrics call. Underline and strikeout positions or
thicknesses are `#f` when the native validity flags say that field is not
available; the remaining fields are numbers.

### Simple text, glyph IDs, and outlines

```racket
(draw-simple-text canvas text x y font paint)
(measure-simple-text font text #:paint [paint-or-false #f])
(simple-text-bounds font text #:paint [paint-or-false #f])
(font-text->glyphs font text) ; -> vector of exact glyph IDs
(font-char->glyph font char-or-unicode-scalar)
(font-glyph-path font glyph-id) ; -> skia-path? or #f
(simple-text-path font text [x 0] [y 0]) ; -> skia-path?
```

These functions intentionally say **simple text**. `text` must be a Racket
string and is encoded as UTF-8. The layer maps/draws the run through Skia's
low-level font API; it does **not** perform HarfBuzz-style shaping, bidi
reordering, line breaking, paragraph layout, or multi-font fallback. It is
appropriate for simple runs whose appearance does not require contextual
shaping. Complex scripts and full typography need a later shaping/layout API.

`draw-simple-text` places the run at `(x,y)`, where `y` is the text baseline,
and applies the current canvas transform and clip. The paint controls color,
style, stroke, antialiasing, and compositing exactly as for geometry.

`measure-simple-text` returns the native advance width. `simple-text-bounds`
returns four values `(x y width height)` for the measured run relative to its
origin. Supplying a paint allows native measurement to account for relevant
paint geometry such as stroking. A false paint requests native defaults.

`font-text->glyphs` returns a newly allocated Racket vector; no native buffer is
retained. `font-char->glyph` accepts either a Racket character or an exact
Unicode scalar value. Glyph ID 0 can represent a missing glyph. A typeface can
lack an outline for a glyph; in that case `font-glyph-path` returns `#f`.
`simple-text-path` returns a newly owned path containing the outlines Skia
produces for the simple text run at the supplied baseline origin.


### Positioned text blobs

```racket
(text-blob? value)
(make-positioned-text-blob font glyphs positions)
(text-blob-bounds blob) ; -> x y width height
(text-blob-unique-id blob)
(draw-text-blob canvas blob x y paint)
```

`make-positioned-text-blob` builds one immutable native `SkTextBlob` run.
`glyphs` is a list or vector of exact glyph IDs from 0 through 65535.
`positions` is a same-length list/vector whose elements are `(list x y)` or
`#(x y)` finite coordinates. At least one glyph is required. The positions are
absolute positions inside the blob run; `(draw-text-blob ... x y ...)` adds the
requested drawing origin when replaying the blob.

The constructor allocates a temporary native `SkTextBlobBuilder`, requests a
positioned run buffer, writes glyph IDs and `SkPoint` values into that native
buffer synchronously, then seals it into an immutable blob. No pointer into a
Racket list/vector is retained. Native blob data contains the font state it
needs, so the source `font?` and its typeface wrapper may be closed after blob
construction.

`text-blob-bounds` returns native blob bounds relative to its run origin.
`text-blob-unique-id` is Skia's unsigned blob identifier. `draw-text-blob` uses
an ordinary paint and current canvas state. This API deliberately accepts
already-selected glyphs and positions; it does not map Unicode to multiple
font runs, perform bidi, or shape complex scripts.

## Racket bitmap bridge

Separate module `(require skia/bitmap)`:

```racket
(surface->bitmap surface) ; bitmap% with alpha and backing scale 1
(image->bitmap image)     ; bitmap% with alpha and backing scale 1
```

Both perform pixel copies and return an independent bitmap. Premultiplied
RGBA is reordered to premultiplied ARGB before `set-argb-pixels`. They load
`racket/draw`; importing the main drawing module alone does not. This bridge
does not provide a Skia `dc%`, zero-copy sharing, or vector interchange.


## Pictures and recording

```racket
(picture? value)
(picture-width picture)
(picture-height picture)

(picture-recorder? value)
(picture-recorder-recording? recorder)
(make-picture-recorder)
(call-with-picture width height procedure-of-one-argument)
(picture-recorder-begin-recording! recorder x y width height)
(picture-recorder-finish-recording! recorder)

(draw-picture canvas picture
              #:x [x 0]
              #:y [y 0]
              #:width [width #f]
              #:height [height #f])

(picture->image picture width height
                #:background [color 'transparent])
```

A `picture?` is an immutable recording of drawing commands. A picture records
canvas operations against a cull rectangle, keeps no borrowed canvas alive once
recording has finished, and may be replayed on any later canvas.

`call-with-picture` records into a fresh picture recorder whose logical size is
`width` by `height`; the procedure receives a borrowed recording canvas.
`make-picture-recorder` exposes the lower-level begin/finish cycle when callers
need to interleave recording with other logic. Attempting to begin while the
recorder is already active, or attempting to finish while it is inactive, is an
error. A recording canvas becomes invalid immediately after
`picture-recorder-finish-recording!`.

`draw-picture` replays the immutable recording. With only `#:x` and `#:y`, it
translates the replay origin. Supplying both `#:width` and `#:height` scales the
picture from its recorded size to the requested destination size. Both scaling
keywords must be supplied together.

`picture->image` rasterizes a picture onto a temporary CPU surface and returns a
new immutable `image?`. The requested width and height are exact positive
integers and may differ from the picture's recorded size.


## Expanded path and SVG geometry

```racket
(path-rmove-to! path dx dy)
(path-rline-to! path dx dy)
(path-rquad-to! path dcx dcy dx dy)
(path-conic-to! path cx cy x y weight)
(path-rconic-to! path dcx dcy dx dy weight)
(path-rcubic-to! path dcx1 dcy1 dcx2 dcy2 dx dy)

(path-add-rounded-rect! path x y width height rx ry
                        #:direction [direction 'cw])
(path-add-path! destination source
                #:dx [dx 0]
                #:dy [dy 0]
                #:mode [mode 'append])
(path-add-reversed-path! destination source)

(path-point-count path)
(path-point-ref path index) ; -> x y
(path-points path)          ; -> list of (list x y)
(path-last-point path)      ; -> x y
(path-convex? path)

(svg-path->path string #:fill-rule [fill-rule 'winding])
(path->svg-path path)
```

Relative commands behave like their Skia counterparts: offsets are interpreted
from the current point. `path-add-path!` replays one path into another with an
optional translation and either `'append` or `'extend` mode.

`svg-path->path` parses SVG *path data* only, not a full SVG document. The
accepted grammar is the usual `M/L/H/V/C/S/Q/T/A/Z` path-data language as
implemented by Skia. `path->svg-path` serializes the current path back to a
path-data string.


## HarfBuzz shaping

```racket
harfbuzz-package-version
(harfbuzz-check!)
(harfbuzz-available?)
(harfbuzz-native-version)
(harfbuzz-native-library-path)

(shaper? value)
(make-shaper font)

(shaped-run? value)
(shaped-run-glyphs run)
(shaped-run-clusters run)
(shaped-run-positions run)
(shaped-run-advance-x run)
(shaped-run-advance-y run)
(shaped-run-glyph-count run)

(shape-text shaper text
            #:direction [direction 'auto]
            #:script [script #f]
            #:language [language #f]
            #:features [features '()])

(shaped-run->text-blob shaper run)
(draw-shaped-run canvas shaper run x y paint)
(draw-shaped-text canvas shaper text x y paint
                  #:direction [direction 'auto]
                  #:script [script #f]
                  #:language [language #f]
                  #:features [features '()])
```

`make-shaper` snapshots the supplied `font?`: its typeface is copied into a
HarfBuzz face/font and an independent Skia font wrapper is retained for later
TextBlob creation. Closing or mutating the original font after successful
construction does not alter the shaper.

`shape-text` adds UTF-8 input to a HarfBuzz buffer, guesses segment properties,
then applies explicit overrides. Directions are `'auto`, `'ltr`, `'rtl`, `'ttb`,
and `'btt`. `script` is `#f`, a symbol such as `'arab`, or a string. `language`
is a BCP-47-ish HarfBuzz language string such as `"en"` or `"ar"`. Features
are HarfBuzz feature strings such as `"liga=0"`, `"kern=1"`, or
`"ss01=1"`.

Clusters are byte offsets into the UTF-8 input, matching HarfBuzz's semantics.
Positions are relative glyph origins in Skia user-space units. HarfBuzz x/y
offsets and advances are converted using the snapshotted font's size and
horizontal scale, following SkiaSharp.HarfBuzz's m119 shaping convention.

`shaped-run->text-blob` creates a normal owned `text-blob?`; empty shaped runs
have no native blob and therefore raise in this conversion. `draw-shaped-run`
and `draw-shaped-text` treat an empty run as a no-op.

This API shapes a single font run. It does not perform paragraph-level bidi,
script/fallback segmentation, line breaking, wrapping, or justification.


## Paragraph text layout

```racket
(text-layout? value)
(text-layout-lines layout)
(text-layout-width layout)
(text-layout-height layout)
(text-layout-line-height layout)
(text-layout-line-count layout)

(text-layout-line? value)
(text-layout-line-text line)
(text-layout-line-run line)
(text-layout-line-origin-x line)
(text-layout-line-baseline line)
(text-layout-line-width line)
(text-layout-line-direction line)

(layout-break-opportunity? value)
(make-layout-break-opportunity index [insert ""])
(layout-break-opportunity-index opportunity)
(layout-break-opportunity-insert opportunity)

(layout-text shaper text
             #:width [width #f]
             #:align [align 'start]
             #:direction [direction 'auto]
             #:script [script #f]
             #:language [language #f]
             #:features [features '()]
             #:break-provider [break-provider #f]
             #:line-height [line-height #f])

(draw-text-layout canvas layout x y paint)
```

`layout-text` creates a pure Racket layout containing one `shaped-run?` per
line. `x` and `y` in `draw-text-layout` are the top-left of the layout box; the
line baselines stored in the layout are relative to that top edge. The default
line height comes from the shaper font's native metrics; an explicit positive
`#:line-height` overrides the baseline spacing.

`#:width #f` disables wrapping. A positive width enables greedy line fitting at
Unicode 15.1 UAX #14 revision 51 break opportunities. BK/CR/LF/NL hard line
separators are preserved as explicit layout lines, including blank and trailing
lines. Ordinary break whitespace is not retained at a wrapped line edge. A span
with no legal opportunity is not emergency-split; when it exceeds the requested
width, `text-layout-width` expands to report the true occupied width.

The resolver uses the UAX #14 tailoring that prevents breaks inside Racket's
default grapheme clusters. SA (complex-context Southeast Asian) characters use
UAX #14's default AL/CM fallback in the core resolver. A non-`#f`
`#:break-provider` supplements those Unicode opportunities. The provider is
called as `(break-provider paragraph language)` for each hard-break-delimited
paragraph and must return a list of interior string indices or
`layout-break-opportunity?` values. Indices are Racket string indices, not UTF-8
byte offsets, and must be default-grapheme boundaries.

`make-layout-break-opportunity` attaches optional display-only text to a
boundary. The insertion is included in `text-layout-line-text` only when that
break is selected; the following line resumes at the unchanged logical string
index. This makes dictionary segmentation and language-specific hyphenation
pluggable without changing the UAX #14 resolver itself. Providers are not called
when `#:width` is `#f` because no wrapping decision is needed.

Alignment is one of `'start`, `'center`, `'end`, `'left`, `'right`, `'justify`,
or `'justify-all`. `start` and `end` are direction-sensitive. `'justify` expands
U+0020 inter-word spaces on wrapped non-final lines to fill `#:width` and leaves
the final line of each hard-break-delimited paragraph at logical start.
`'justify-all` applies the same expansion to final and single lines. Both
justification modes require a positive `#:width`; a line without an ordinary
space remains start-aligned at its natural width.

Justification is script-aware in version 0.18. Ordinary U+0020 spaces remain
stretchable for every script. Han, Hiragana, Katakana, and Hangul additionally
stretch between adjacent CJK grapheme clusters. Arabic text uses Unicode 15.1
Joining_Type-compatible boundaries and reshapes display-only U+0640 TATWEEL
insertions with HarfBuzz. The logical `text-layout-line-text` value is not
modified by those display insertions, and shaped-run cluster offsets are mapped
back to the logical line's UTF-8 byte coordinates. NBSP/NNBSP and punctuation are not general
stretch points. Paragraph layout currently accepts only `'auto`, `'ltr`, and
`'rtl`; vertical HarfBuzz directions remain available to `shape-text` but not
to this horizontal layout layer.

The layout keeps its originating shaper wrapper reachable because its glyph IDs
are meaningful only for that font. If the shaper is explicitly closed, later
`draw-text-layout` calls fail with the normal closed-resource error.

This API is deliberately narrower than `layout-mixed-text`: it does not perform
UAX #9 mixed-direction bidi resolution or script/font run segmentation. A line
is shaped as one HarfBuzz run. With `#:direction 'auto`, HarfBuzz guesses the
shaping direction; start/end alignment infers RTL from descending cluster
offsets and otherwise defaults to LTR. Use an explicit direction when an
ambiguous one-glyph line must align directionally.


## Mixed-script and bidirectional text layout

```racket
(mixed-text-layout? value)
(mixed-text-layout-lines layout)
(mixed-text-layout-width layout)
(mixed-text-layout-height layout)
(mixed-text-layout-line-height layout)
(mixed-text-layout-line-count layout)

(mixed-text-line? value)
(mixed-text-line-text line)
(mixed-text-line-runs line)
(mixed-text-line-origin-x line)
(mixed-text-line-baseline line)
(mixed-text-line-width line)
(mixed-text-line-direction line)

(mixed-text-run? value)
(mixed-text-run-text run)
(mixed-text-run-shaped-run run)
(mixed-text-run-origin-x run)
(mixed-text-run-width run)
(mixed-text-run-direction run)
(mixed-text-run-level run)
(mixed-text-run-script run)
(mixed-text-run-family run)

(layout-mixed-text shaper font-manager text
                   #:width [width #f]
                   #:align [align 'start]
                   #:direction [direction 'auto]
                   #:language [language #f]
                   #:features [features '()]
                   #:break-provider [break-provider #f]
                   #:line-height [line-height #f])

(draw-mixed-text-layout canvas layout x y paint)
```

`layout-mixed-text` extends the single-run paragraph layer to visual lines made
from multiple shaped runs. Paragraph direction is `'ltr`, `'rtl`, or `'auto`.
For automatic direction the first ordinary strong character selects the
paragraph base direction. Resolved bidi levels determine run direction and
visual run ordering; HarfBuzz shapes each run with its resolved horizontal
direction and Unicode script.

Run segmentation preserves Racket Unicode grapheme clusters. A grapheme whose
visible scalars are unavailable in the base shaper's font asks the supplied
`font-manager?` for a character fallback. Fallback is therefore chosen at a
grapheme boundary instead of splitting a base character from its combining
marks. `mixed-text-run-family` reports the selected fallback family string;
`#f` means the run uses the base shaper. Script is a lower-case ISO 15924-style
symbol such as `'latn`, `'arab`, or `'hebr`, or `#f` for Common/Inherited data.

The returned layout is a pure Racket value. It does **not** own hidden fallback
font resources: fallback shapers are temporary during layout and are recreated
for drawing from the recorded family/style description. The caller-owned base
shaper and font manager are retained by reference and must remain open while
`draw-mixed-text-layout` is used.

The bidi resolver implements paragraph direction, explicit directional status
stack processing, isolating run sequences, weak/neutral/bracket resolution,
implicit levels, and L1/L2 behavior. `LRE`, `RLE`, `LRO`, `RLO`, `PDF`, `LRI`,
`RLI`, `FSI`, and `PDI` therefore affect the resolved runs. Formatting controls
are removed before shaping and never become glyphs. `FSI` chooses its isolate
direction from the first strong character while ignoring nested isolate
contents.

When `#:width` wraps a paragraph, explicit scopes are resolved on the complete
logical paragraph first. After UAX #14 selects logical line ends, line-specific
L1 trailing resets are applied and the paragraph levels are sliced for each
visual line. This permits embeddings, overrides, and isolates to span wrapped
lines correctly rather than restarting at every substring.

With `#:width`, mixed layout uses the same Unicode 15.1 UAX #14 line-breaking
engine as `layout-text`; break selection occurs on logical paragraph text before
final per-line bidi shaping/reordering. Default grapheme clusters are kept
intact. A `#:break-provider` contributes the same supplemental boundaries as in
`layout-text`. Selected display-only suffixes do not alter paragraph indices or
UAX #9 resolution; a suffix is shaped with the resolved level immediately
preceding its break. `'justify` and `'justify-all` distribute slack over
script-appropriate opportunities after bidi/script/fallback segmentation:
U+0020 word spaces, adjacent CJK grapheme/run boundaries, and Arabic cursive
connections selected from Unicode 15.1 Joining_Type data. Arabic display runs

## Color spaces and ICC profiles

```racket
(color-space? value)
(make-srgb-color-space)
(make-linear-srgb-color-space)
(color-space-from-icc-bytes bytes)
(color-space->icc-bytes color-space)
(color-space-srgb? color-space)
(color-space-linear-gamma? color-space)
(color-space-gamma-close-to-srgb? color-space)
(color-space=? left right)
(color-space->linear-gamma color-space)
(color-space->srgb-gamma color-space)
(surface-color-space surface)
(image-color-space image)
```

Color spaces are owned resources and follow the same close/thread rules as
other native wrappers. The sRGB constructors safely acquire a reference to
Skia's process-lifetime singleton before exposing an owned Racket wrapper.
`surface-color-space` and `image-color-space` return a new owned reference or
`#f` when the object is untagged.

`color-space-from-icc-bytes` parses an ICC profile and keeps the corresponding
native profile alive for the lifetime required by the created color space.
`color-space->icc-bytes` serializes a native color space back to ICC bytes. Both
copied profile directions obey `current-skia-byte-limit`.

Passing `#:color-space` to `make-surface` or `rgba-bytes->image` tags the raster
with that source space. Passing it to `surface->rgba-bytes` or
`image->rgba-bytes` specifies the destination space and requests a native CPU
conversion. Omitting it retains the earlier untagged/readback behavior. This
stage does not add custom transfer-function/XYZ constructors or explicit ICC
profile injection options to PNG/JPEG/WebP encoding.
are reshaped with U+0640 TATWEEL while `mixed-text-line-text` and
`mixed-text-run-text` retain the logical source text; exposed shaped-run cluster
offsets are remapped to that logical UTF-8 text. The package does not ship
a Southeast Asian dictionary or language-specific hyphenator; emergency
breaking and language/font-specific kashida ranking or `jalt` policy remain
outside this stage.
