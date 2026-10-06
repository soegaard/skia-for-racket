# 0.68b — Font options and glyph queries

Package version **0.68.2**. Additive to 0.68a's `typefaces.rkt`; the SkiaSharp
3.119.1 / Skia m119 and HarfBuzz pins and the Racket 8.18 / draw-lib 1.22
minimums are unchanged. All APIs below are exported by `main.rkt`; the new query
functions are also exported by `fonts.rkt`.

## Font controls

`make-font` adds three boolean keywords:

```racket
(make-font face #:size 24
                #:embedded-bitmaps? #f
                #:force-auto-hinting? #f
                #:baseline-snap? #t)
```

Those defaults preserve the pinned m119 constructor, including **embedded
bitmaps off**, rather than substituting a different platform's defaults.
Existing arguments and font controls retain their meanings. Non-boolean
options fail before a native allocation.

```racket
(font-embedded-bitmaps? font)
(font-set-embedded-bitmaps! font boolean)
(font-force-auto-hinting? font)
(font-set-force-auto-hinting! font boolean)
(font-baseline-snap? font)
(font-set-baseline-snap! font boolean)
```

These select SkFont flags; they do not promise identical pixels on CoreText,
FreeType, DirectWrite, GPU surfaces and document readers. Forced auto-hinting is
backend-dependent. Baseline snapping is not a general rounding operation on
all returned positions. Embedded bitmap/color glyphs can lack monochrome
outlines. Selecting a flag does not make an unavailable outline appear.

All three flags are copied with the other font configuration when constructing
a shaper, a positioned text blob, or a fallback font. Measurement uses the
same configured SkFont as simple native text drawing. HarfBuzz's design-unit
shaping and SkFont's raster hinting are still different operations; these
flags do not add a second shaping or pair-kerning pass.

## Typeface replacement and ownership

```racket
(font-typeface font)             ; a new owned typeface wrapper
(font-set-typeface! font face)   ; void; face must be a live typeface
```

The getter's result must be closed, just like `typeface-from-bytes`. It remains
valid after the font changes or closes. The setter retains its own native
reference, so the supplied typeface wrapper may immediately be closed. It does
not close a caller-supplied wrapper or reset size, scale, skew, hinting, edging,
or any boolean option. An implicitly-created default typeface wrapper is
released after successful replacement; unsuccessful argument/lifetime checks
leave the font unchanged.

There is no null reset sentinel. Use a scoped `(make-typeface)` result to select
a default explicitly. Replacing the font's typeface does not remap previously
obtained glyph IDs. Use glyph IDs from the new typeface for subsequent queries.
Existing shapers and blobs retain their original typeface and options. Create
a new shaper to shape with a newly selected face.

## Detached glyph measurements

Glyph inputs are lists or vectors of exact unsigned 16-bit IDs. The functions
also reject IDs outside the font's current typeface glyph count. They never
reinterpret character codes as glyph IDs; use `font-text->glyphs` for the
simple unshaped mapping or use an existing shaped run's glyph IDs.

```racket
(font-glyph-widths font glyphs #:paint [paint #f])
(font-glyph-bounds font glyphs #:paint [paint #f])
(font-glyph-widths+bounds font glyphs #:paint [paint #f]) ; two values
(font-glyph-positions font glyphs #:origin [origin '(0 0)])
(font-glyph-x-positions font glyphs #:origin [origin 0])
```

The first two return immutable vectors. Widths are advances in the font's
configured coordinates. Each bounds entry is an immutable list
`(x y width height)`, **not** `(left top right bottom)`, matching
`simple-text-bounds`. Bounds are relative to that glyph's baseline origin;
they have not been translated to a run position. The combined query returns
the width vector and the bounds vector from a single native operation. A
supplied paint participates in native bounds/measurement semantics.

Positions are an immutable vector of immutable `(x y)` lists. X positions are
an immutable vector of numbers. These are successive **unshaped, unkerned**
advances. They do not apply ligatures, bidi, fallback, script positioning or
pair kerning. Do not overwrite HarfBuzz positions with these convenience
positions. The two-dimensional origin accepts a two-element list or vector;
the native call always receives a valid non-null origin structure.

Input containers are copied. Results outlive their input containers and font
wrappers. Empty inputs return immutable empty vectors, but still validate
resource liveness, thread affinity, paint and other arguments.

## Batch outlines

```racket
(define paths (font-glyph-paths font glyphs))
(dynamic-wind
  void
  (lambda ()
    (for ([path (in-vector paths)] #:when path)
      ;; Consume the baseline-local outline here.
      ...))
  (lambda ()
    (for ([path (in-vector paths)] #:when path)
      (skia-close! path))))
```

The result is an immutable vector containing one independently owned
`skia-path?` or `#f` per input glyph. A missing outline is `#f`; an empty native
outline can instead be an owned empty path. Repeated IDs produce independently
closeable paths. Positions are **not** applied automatically. Paths include
the native callback's font transform, including size, horizontal scaling and
skew. They outlive the font and typeface.

The internal callback never exposes Skia's borrowed path or stack matrix to
application code. The native input array is immobile while callbacks can
allocate. A copied path is installed before its callback returns. All raised
values are caught inside the callback, completed copies are cleaned up on
failure, and the original failure is re-raised only after the C call returns.
No Racket exception is intentionally unwound through a C++ frame. The API does
not accept arbitrary user callback procedures.

## Simple prefix fitting

```racket
(define-values (count width)
  (font-break-text font text maximum-width #:paint paint))
(substring text 0 count)
```

`text` is a Racket string and the width is nonnegative and finite. The result
is a **Racket character/scalar count**, not a UTF-8 byte count, plus the native
measured width. The native returned byte count is checked and decoded strictly;
a byte count splitting a UTF-8 scalar is an error, not replacement-character
recovery. Embedded NUL and supplementary Unicode scalars are supported.

This is SkFont's simple prefix-fitting operation. It does **not** find a word,
grapheme, Unicode line-break, bidi or shaping-safe boundary. It can split a base
letter from a combining mark. Use `layout-text` / `layout-mixed-text` for
paragraph layout and existing shaped positions for shaped text. Low-level
pair kerning from 0.68a must not be reapplied to HarfBuzz advances.

## Limits, lifecycle and document behavior

Finite C-float arguments, signed-int glyph counts, checked uint16 IDs and
`current-skia-byte-limit` constrain wrapper input/output buffers. Batch copying
additionally charges copied path controls and verbs. The charges bound logical
buffer payload and estimated result storage, not exact Racket heap overhead or
all allocations inside Skia's font caches or rasterizers. Returned
measurements are detached; returned paths/typefaces are owned. Native access
uses the existing resource/thread lifetime protocol. Requiring `fonts.rkt`
does not load a native library or change global caches.

Native PDF text can retain embedded text; SVG outline mode uses paths. The new
options do not change exporter policies or silently rasterize unavailable
outlines. The existing policy/audit layer remains authoritative. This stage
adds neither variable-font axes/palettes nor MATH-table layout, live font
streams, multi-run text blobs, or text-on-path; those retain their roadmap
placements.

## Acceptance

```bash
python3 -m pip install -r tools/dc-output-requirements.txt
python3 tools/update-source-sums.py --check
python3 tools/api-inventory.py --check
python3 tools/test-font-queries.py
python3 tools/validate-font-queries.py --racket "$RACKET" \
  --require-gpu --backend metal --require-renderers
```

Select `egl` on Linux or `direct3d --adapter warp` for Windows software GPU
acceptance. `--require-renderers` requires `pdftoppm` and `rsvg-convert`; it never
silently skips missing programs. Without that flag, actual PDF/SVG structure
is still inspected, but independent rendering is explicitly not claimed.
Without `--require-gpu`, GPU execution is explicitly not claimed.

The validator compiles the full static/dynamic regression graph, runs all
ordinary pure/native regression suites, then generates six controlled
PDF/SVG documents and RGBA references. It checks changed-face versus retained
snapshot pixels, transformed batch geometry, vector-only export, native PDF
font embedding/text extraction and outlined SVG. The optional GPU gate draws
three scenes and requires zero drawing readbacks and exactly three explicit
inspection readbacks. Linux CI requires independent Poppler/librsvg rendering
and Mesa GPU execution; Windows requires WARP execution and document structure.
No GUI or physical-display result is inferred.

The procedural fixtures are source code, not copies of installed font files.
Synthetic inspector tests establish only that the checks reject bad evidence.
Every acceptance run creates fresh, token-matched receipts and command logs.
A failed run retains `validation.json` and its failed command/log path.

## Reviewed sources

Pinned C declarations and ownership/callback implementation:
`mono/skia`, revision `40f75dc0051d141913c07c20d4c19590c7da0cb7`,
`include/c/sk_font.h`, `src/c/sk_font.cpp`, and `src/core/SkFont.cpp`.
Racket FFI callback lifetime/atomicity follows the *Function Types* chapter of
the Racket Foreign Interface manual. Header checks are not runtime ABI proof.

## Subsequent text support

Stage 0.69 now provides the multi-run and path-text APIs described in
[TEXT-BLOBS.md](TEXT-BLOBS.md), retaining the font-query contracts above.
