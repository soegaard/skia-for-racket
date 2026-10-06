# Multi-run text blobs and shaped text-on-path — 0.69

Package version **0.69.0**. Comparison remains SkiaSharp **3.119.1**, Skia m119 at
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. Native pins, Racket **8.18** minimum,
and draw-lib **1.22** minimum are unchanged.

Require `skia` / `main.rkt` for the full API, or `text-blobs.rkt` for the additive
operations here. Existing `make-positioned-text-blob`, drawing, bounds, IDs,
shapers, and font-query APIs remain available.

## Builders and ownership

```racket
(make-text-blob-builder)                    ; -> text-blob-builder?
(text-blob-builder-run-count builder)        ; -> exact-nonnegative-integer?
(text-blob-builder-finish! builder)          ; -> text-blob? or #f
```

The builder is an ordinary `skia-resource?`: use `with-skia`,
`call-with-skia-resource`, `skia-close!`, and `skia-closed?`. It is owner-thread
confined and single-use. `finish!` consumes and closes it; finishing an empty
builder returns `#f`, not a native object with an invalid null handle.

Every successful nonempty append captures an independent font snapshot including
its typeface, size, scale/skew, edging, hinting, subpixel/linear metrics, embolden,
embedded bitmaps, forced auto-hinting, and baseline snapping. Inputs are copied.
Changing or closing source fonts, typefaces, shapers, or input vectors does not
alter appended runs. The blob owns those snapshots after `finish!`; closing an
unfinished builder releases its snapshots. Closing a blob releases its native
reference and all of its private fonts. Each native owner has a GC fallback.

Argument, count, glyph-range, metadata and budget errors are checked before a
native run is allocated. Those errors leave existing builder contents usable.
After native allocation has begun, an append error closes the builder: the
native builder cannot roll back a partially filled run. No public writable
native buffers or callback-backed user drawing objects are exposed.

An empty append validates the source font and all input, but adds no run.
An empty run cannot carry nonempty original text, which would be discarded.

## Four placement formats

```racket
(text-blob-builder-add-run!
 builder font glyphs
 #:origin [origin '(0 0)] #:text [text #f] #:clusters [clusters #f])

(text-blob-builder-add-horizontal-run!
 builder font glyphs x-positions
 #:y [baseline 0] #:text [text #f] #:clusters [clusters #f])

(text-blob-builder-add-positioned-run!
 builder font glyphs positions
 #:text [text #f] #:clusters [clusters #f])

(text-blob-builder-add-transformed-run!
 builder font glyphs transforms
 #:text [text #f] #:clusters [clusters #f])
```

`glyphs` is a list or vector of exact uint16 glyph IDs belonging to that font's
current typeface. No character-to-glyph conversion or shaping is implied.
Positions and transforms must have exactly one entry per glyph. Coordinates
must be finite and representable as native C floats.

| Format | Input and meaning |
|---|---|
| Default | An `(x y)` origin. Skia supplies unshaped natural glyph advances. |
| Horizontal | One X coordinate per glyph and a common Y baseline. |
| Positioned | One `(x y)` list/vector per glyph. |
| Transformed | One `(scos ssin tx ty)` list/vector or existing `atlas-transform?` per glyph. |

The transformed format uses an RSXform, not a general projective matrix:

```text
x' = scos*x - ssin*y + tx
y' = ssin*x + scos*y + ty
```

The transform acts on the font-sized glyph, including the font's own scale and
skew. Uniform scale and rotation are supported; zero scale is legal. Existing
`make-atlas-transform` values, including rotation in degrees and local anchors,
can be reused without inventing a second transform value type.

Runs may use different fonts and formats in the same blob. The wrapper preserves
**authored run boundaries** for inspection. Skia may internally coalesce compatible
runs, so this count is not a report of native internal run records.

## Original text and clusters

`#:text` and `#:clusters` are either both absent or both supplied. Text is a
Racket string or well-formed UTF-8 bytes. The stored bytes are an immutable copy;
malformed input is rejected rather than repaired.

Clusters are exact **UTF-8 byte offsets into that run's text**, not Racket string
indices, UTF-16 positions, or glyph indices. Each offset must be inside the text
and at a Unicode scalar start. A run stores exactly one cluster offset per
glyph. Repeated offsets are valid for shared clusters, and descending offsets
are valid for RTL glyph order. Text byte length and glyph counts are checked
against the pinned ABI's signed-int limits.

The wrapper validates representation and bounds. It cannot prove that supplied
text actually corresponds to supplied glyph IDs. Do not attach unrelated text
to glyphs and interpret the result as correct extraction or accessibility.

For already shaped text:

```racket
(text-blob-builder-add-shaped-run!
 builder shaper shaped-run
 #:origin [origin '(0 0)] #:text [original-text #f])
```

This keeps the run's glyph order, glyph positions and, when text is supplied,
its HarfBuzz clusters. The origin is added to each shaped position. No additional
kerning or reordering is applied. Supply the same shaper/font snapshot and exact
original text used to create the shaped run; the existing `shaped-run?` value
does not carry a verifiable shaper identity.

## Example: retain text independently of its authoring owners

```racket
#lang racket/base
(require "main.rkt")

(with-skia ([font (make-font #:size 24 #:hinting 'none)]
            [large (make-font #:size 36 #:hinting 'none)]
            [shaper (make-shaper font)]
            [builder (make-text-blob-builder)])
  (text-blob-builder-add-shaped-run!
   builder shaper (shape-text shaper "First run")
   #:origin '(20 40) #:text "First run")
  (text-blob-builder-add-run!
   builder large (font-text->glyphs large "AV")
   #:origin '(20 90) #:text "AV" #:clusters '(0 1))

  (skia-close! shaper)
  (skia-close! font)
  (skia-close! large)
  (with-skia ([blob (text-blob-builder-finish! builder)]
              [surface (make-surface 260 120 #:background 'white)]
              [paint (make-paint #:color 'black)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)
    (save-png surface "retained-text.png")))
```

The first run is shaped; the second deliberately uses simple unshaped glyph
advances. A text blob is not a paragraph layout, fallback selection engine, or
Unicode line-breaking operation.

## Detached inspection and owned font copies

```racket
(text-blob-run-count blob)
(text-blob-runs blob)               ; immutable vector of text-run-info?
(text-blob-run-font blob index)     ; independently owned font?

(text-run-info-positioning info)    ; 'default / 'horizontal / 'positioned / 'transformed
(text-run-info-glyphs info)         ; immutable vector
(text-run-info-positions info)      ; immutable vector of immutable (x y) lists
(text-run-info-transforms info)     ; immutable vector of (scos ssin tx ty), or #f
(text-run-info-utf8 info)           ; immutable bytes or #f
(text-run-info-clusters info)       ; immutable vector or #f
```

Default and horizontal runs include their resolved explicit XY positions for
outline replay. Transformed runs have an empty positions vector and a non-false
transform vector. Inspection values contain no font handle and remain usable
after blob closure. The font getter returns a new owned resource; changing or
closing it never changes the blob. Run indices are zero-based and checked.
Legacy positioned blobs are exposed as one positioned run with absent text and
cluster metadata; no metadata is invented for them.

## Outline conversion and document output

`text-blob->path` and the existing `current-text-output-mode` dispatch now handle
multi-run blobs. Every glyph outline uses its captured font and its exact run
placement, including rotation/scale. The result is baseline-local and
independently owned. It remains usable after blob closure.

For new multi-run blobs, a glyph that has visible native bounds but no available
monochrome outline causes an explicit error, rather than silently deleting
visible text. Whitespace with no ink is permitted. Native bitmap/color glyph
coverage is not converted into invented vector outlines. Existing legacy
single-run outline behavior is not changed in this stage.

Use native PDF text for supported ordinary runs when selectable/searchable text
is required; the acceptance gate checks extraction and embedding for a controlled
multi-font fixture. Storing UTF-8 does not by itself guarantee PDF extraction for
all languages or fonts. Transformed/path text's guaranteed document route in
this stage is **explicit outlines**. Outlined text is not searchable or editable
text and does not preserve logical accessibility semantics. Request SVG outlines
through the existing output APIs. No new silent raster fallback is added.

The example `examples/text-blobs-advanced.rkt` produces outlined PDF and SVG using
only public APIs and retains its blobs after source-owner closure.

## Geometric intercepts

```racket
(text-blob-intercepts blob top bottom #:paint [paint #f])
; -> immutable vector of (left right) pairs
```

The band requires finite `top < bottom`. Coordinates are local to the blob,
without a later `draw-text-blob` translation or canvas transform. Results use
Skia's geometric outline semantics and remain in native order. They are **not**
a sorted/merged union, alpha-coverage bounds, or a guarantee that filters and
bitmap/color glyphs are represented. Empty results are `#()`; optional paints
must be live even when the band hits nothing.

**RSXform restriction:** pinned m119 silently skips transformed runs in its
native intercept query. This wrapper rejects any blob containing such a run,
including mixed transformed/untransformed blobs. It does not report a partial
answer as the intercepts of the whole blob.

## Explicitly positioned outline utility

```racket
(positioned-glyphs->path font glyphs positions) ; -> owned skia-path?
```

This binds the pinned `sk_text_utils_get_pos_path` using the **glyph-ID encoding**
and a byte length of twice the glyph count, not a character count. Inputs are
validated; positions are copied; the result outlives the source font. Empty
inputs return an owned empty path after validating the font.

This is an unshaped outline utility, separate from text-on-path. It returns
available monochrome outlines only; missing bitmap/color-only outlines are not
reconstructed. It is not a substitute for native text rendering of those fonts.

## Shaped text along a path

```racket
(shaped-run->text-blob/on-path
 shaper run path
 #:start-offset [start 0]
 #:normal-offset [normal 0]
 #:contour [contour 0]
 #:force-closed? [closed? #f]
 #:text [original-text #f])
; -> owned text-blob? or #f for empty shaped text

(draw-shaped-run/on-path
 canvas shaper run path paint
 #:start-offset [start 0] #:normal-offset [normal 0]
 #:contour [contour 0] #:force-closed? [closed? #f])
```

The implementation snapshots the path through the existing path-measure API and
uses an explicitly selected zero-based contour. For each shaped glyph at `(gx gy)`,
it samples the frame at arc distance `start + gx` and applies normal offset
`normal + gy`. A tangent `(tx ty)` gives a normal `(-ty tx)`; on a left-to-right
horizontal path, positive normal offsets move downward.

Glyphs rotate rigidly with the tangent. Glyph outlines are not bent or warped.
Ligatures, marks, RTL glyph order and shaping offsets remain properties of the
input shaped run. No character-to-glyph assumption, second kerning pass, or
implicit visual-order reversal occurs. Negative shaped X positions need a
sufficient start offset, just like any other positioned glyph.

Every **glyph origin** must be inside the selected contour's measured distance
range. Overruns, unavailable contours and nonmeasurable contours for nonempty
text reject. There is no hidden wrapping to another contour, clamping, cropping,
or fitting/scaling. A glyph's ink may extend beyond an endpoint: origin fitting
is not a promise that its full outline fits. Empty shaped text returns `#f` after
resource and contour validation. Closed paths do not automatically wrap text.

Constructed blobs no longer depend on the source path, shaper, or font wrappers.
The convenience drawing operation closes its temporary blob automatically.

## Limits and evidence

Copied input, run bookkeeping, cumulative builder payload, interval outputs and
copied outline geometry are checked with `current-skia-byte-limit`. These are
wrapper budgets, not an upper bound on every Skia cache, allocator, driver or
font-decoder allocation. No native structure sizes or dependency versions change.
Nine native functions are added in the existing registry. The three planned
0.69 capability families acquire reviewed public anchors; generated inventories
keep execution evidence separate from source declarations.

The stage includes pure/native Racket suites, original procedural Unicode/GSUB
fixtures, seven native-generated PDF/SVG documents, and six GPU captures (three
scenes in native and outline modes). The pixel inspector uses independent
rectangle/triangle geometry and numerical cubic arc-length frames, with probes
away from contour edges. Reference images alone cannot establish a pass.
Synthetic inspector tests are explicitly not renderer-execution evidence.

## Acceptance commands

From the repository root, with the intended Racket selected:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -m pip install -r tools/dc-output-requirements.txt
python3 tools/update-source-sums.py --check
python3 tools/api-inventory.py --check
python3 tools/test-text-blobs.py
python3 tools/test-text-blob-documents.py
python3 tools/validate-text-blobs.py --racket "$RACKET" \
  --require-gpu --backend metal --require-renderers
```

`--require-renderers` requires both `pdftoppm` and `rsvg-convert`; missing programs
fail the gate. Linux CI selects `--backend egl` and requires both viewers on
Racket 8.18 and 9.3. Windows CI selects `--backend direct3d --adapter warp` and
requires GPU pixels and document structure. A Mac host should run the Metal gate
above. The ordinary full test runner includes the new native and pure suites.

The validator uses a fresh output directory, records command logs and invocation
identity, and checks the source manifest before and after. A failure reports its
actual log path. GUI, physical display, and unrequested GPU/viewer execution are
never inferred from a source-only or baseline CI pass.

## Pinned implementation references

- C API: `mono/skia` at the pin above, `include/c/sk_textblob.h`, `include/c/sk_font.h`.
- Shim implementation: `src/c/sk_textblob.cpp` and `src/c/sk_font.cpp`.
- Run buffer ownership/coalescing: `src/core/SkTextBlob.cpp`, `SkTextBlobBuilder::allocInternal` and `mergeRun`.
- RSXform intercept omission: `src/core/SkTextBlob.cpp`, `SkTextBlob::getIntercepts`.
- Captured SkFont configuration and glyph positions: this repository's existing `private/core.rkt`.
