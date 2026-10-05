# Typeface resources — 0.68a

This additive stage exposes immutable typeface data and owned font-style sets.
Use `(require skia/typefaces)` alongside `skia`, or just `skia`, which re-exports
these operations. The release label is **0.68a**; its numeric Racket package
version is **0.68.1**. The four mutable-font/glyph-query groups remain **0.68b**.
SkiaSharp 3.119.1, ABI 119.0, Racket >=8.18 and draw-lib >=1.22 remain unchanged.

## Constructing typefaces

```racket
(typeface-from-bytes data #:index [index 0])
(font-manager-typeface-from-bytes manager data #:index [index 0])
```

Both return an owned `typeface?`, use the existing `skia-close!`/`with-skia`
lifetime protocol, and copy the supplied nonempty bytes. The native SkData
allocation retains no pointer into caller-owned Racket bytes. Changing the source
bytes or closing the manager does not invalidate the resulting face. Malformed
font data or an unavailable collection member is an error, not a request for a
system fallback font. A collection index is a nonnegative signed 32-bit integer.

Pinned m119's macOS CoreText backend rejects nonzero TTC indices, and its
index-zero singular-descriptor path rejected the valid generated TTC during
host acceptance. On macOS only, the wrapper therefore extracts the requested
collection member into an equivalent standalone SFNT, rewrites its absolute
table offsets, and recomputes `head.checkSumAdjustment` before passing that
copied data to Skia at native index 0. This is exact resource re-wrapping, not a
system-font fallback. Linux and Windows still exercise the native TTC
collection-index path directly. Raw font export may consequently return
standalone bytes with index 0, which is already part of the documented
data/index contract.

This does not construct a font manager containing the supplied bytes, install a
font, or expose a live port. The manager-specific operation creates a **typeface**
through that manager. Existing `typeface-from-file` is unchanged.

```racket
(with-skia ([face (typeface-from-bytes font-data #:index 0)]
            [font (make-font face #:size 24)])
  (displayln (typeface-postscript-name face))
  (draw-simple-text canvas "AV" 20 50 font paint))
```

Loading untrusted font bytes still invokes a native parser; these wrappers are
not a sandbox for native code. The byte limit bounds submitted/copied payloads,
not all allocations within Skia, a font host, or Racket's heap.

## Font-style values

```racket
(make-font-style #:weight [weight 'normal]
                 #:width [width 'normal]
                 #:slant [slant 'upright])
(font-style? value)
(font-style-weight style) ; integer 0..1000
(font-style-width style)  ; integer 1..9
(font-style-slant style)  ; 'upright, 'italic, 'oblique
(typeface-style face)
```

Weight and width accept the existing named options or their integer domains.
Styles are detached immutable values, not native resources. `typeface-style`
uses the existing native weight/width/slant queries; it is not a second mutable
SkFontStyle API. Closing the face does not expire the returned style.

## Owned style sets

```racket
(make-empty-font-style-set)
(font-style-set? value)
(font-manager-style-set manager family-name)
(font-manager-style-set-ref manager family-index)
(font-style-set-count styles)
(font-style-set-ref styles index)       ; detached font-style-entry?
(font-style-set-styles styles)          ; immutable vector of entries
(font-style-set-typeface styles index)  ; owned typeface
(font-style-set-match styles [pattern (make-font-style)]) ; typeface or #f

(font-style-entry? value)
(font-style-entry-index entry)
(font-style-entry-name entry)           ; immutable string, possibly empty
(font-style-entry-style entry)          ; detached font-style?
```

A style set is a `skia-resource?`. Its owned native reference outlives the manager
wrapper; a typeface created from it outlives the style-set wrapper. Entries and
vectors retain no native pointer and remain usable after either wrapper closes.
All resource operations enforce the existing creating-thread and closed-resource
checks, including empty-result queries. Index arguments are bounds-checked before
native indexing. Snapshots charge count and name payloads against the byte limit.

Family lookup is by an explicit string. A missing family returns an empty style
set. Matching an empty set returns `#f`; an out-of-range index is an argument error.
Family/style order and localized style names are font-host dependent. The matcher
uses the native matching policy, not a new Racket ranking algorithm.

## Metadata and font tables

```racket
(typeface-postscript-name face) ; immutable string or #f when unavailable
(typeface-fixed-pitch? face)    ; boolean
(typeface-glyph-count face)     ; nonnegative integer
(typeface-units-per-em face)    ; positive integer or #f when native returns zero

(font-table-tag value)         ; uint32, four bytes, or four Latin-1 characters
(font-table-tag->bytes tag)    ; uint32 -> immutable four-byte big-endian value
(typeface-table-tags face)     ; immutable vector of uint32 tags, host order
(typeface-table-size face tag) ; exact size, or #f for an absent table
(typeface-table-bytes face tag #:start [start 0] #:end [end #f])
```

Table slices use half-open byte offsets `[start,end)`; `#f` means the table's end.
A missing table returns `#f`. A valid empty slice returns `#""`. Reversed,
noninteger and out-of-range offsets are errors; structural argument errors are
not hidden by an absent table. Tags preserve all 32 bits, including trailing
spaces (for example `"CFF "`). Numeric tags are not machine-endian strings.

Copies are immutable and detached. Full-table reads use native `copyTableData`;
partial reads use `getTableData`. Sizes and requested payload budgets are checked
before allocation, exact native read lengths are checked, and all temporary native
resources are closed before return. A small slice can be read even when a full
copy would exceed `current-skia-byte-limit`. Empty-table detection may require a
bounded tag-list query because native size zero also denotes absence.

Table bytes are raw data. This stage does not parse OpenType MATH, instantiate
variation axes, or implement color-palette selection.

## Pair kerning

```racket
(typeface-kerning-pair-adjustments face glyphs)
```

The input is a list/vector of valid glyph IDs within the face. For `n >= 2`, the
result is an immutable vector of **n-1 signed design-unit** horizontal adjustments,
or `#f` when the font host does not supply them. The undefined native output
buffer is never inspected on failure. Fewer than two glyphs produce `#()`, after
normal lifetime and glyph-ID checks. This is not character mapping or shaping.

Scale a design-unit adjustment by `font-size / units-per-em` when implementing a
simple layout. Do not apply it again to positions already shaped by HarfBuzz.
A zero vector is a supported result, distinct from unavailable `#f`.

## Copied raw font data

```racket
(define-values (data collection-index) (typeface->font-bytes face))
```

Returns immutable copied bytes plus the index needed to reload that specific
face. This reuses the bounded, temporary native-stream helper already used by
HarfBuzz. The stream is destroyed before return; no native stream pointer or port
escapes. Unavailable/empty data and short reads are errors.

A backend may reconstruct a standalone font rather than return its original TTC.
Use **the returned data/index pair**, not the index originally used for loading.
Byte-for-byte preservation of an input file is not promised. Font embedding or
redistribution rights are not granted by access to these bytes.

## Scope and acceptance

0.68a changes no SkFont options, shaper snapshots, glyph layout, GPU transfers,
canvas API, or output-fallback policy. The earlier GPU workflows remain regression
gates; the new typeface workflow does not claim GPU or GUI execution.

`tests/typeface-fixtures.rkt` constructs small original SFNT/TTC fixtures from
geometric glyphs and explicit tables, without checking in binary fonts. Native
tests cover both members, copied input lifetime, table slices, metadata, optional
host kerning, raw-data re-import, style-set ownership, thread checks and cleanup.
System fonts are used only for exercising real manager/style enumeration.

`tools/validate-typefaces.py --racket <selected-racket>` recompiles the regression
runner and its dynamic test targets, runs all regressions, generates six real
documents, and performs structural/semantic inspection. The matrix is native-text
PDF, outlined PDF, and outlined SVG for each fixture face. Native PDF must embed
the face and extract as `AV`; outlines must contain no text or raster fallback.
A separate vector marker and URL remain in each document. `--require-renderers`
requires Poppler/librsvg and compares independently rendered pixels with direct
Skia references, using interior probes and explicit antialiasing tolerance.

Native SVG relies on viewer font availability and is deliberately not claimed
by this uninstalled-fixture test. Only its outlined SVG export is selected.

The label and actual numeric version are separate throughout evidence. Historical
execution receipts are not rewritten as evidence for newly added features. Run
all eight workflows before accepting the new baseline; `CI required` aggregation
and repository branch protection are unchanged.

## Upstream basis

Pinned mono/skia commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/c/sk_typeface.h`, `src/c/sk_typeface.cpp`, `include/core/SkTypeface.h`,
`include/core/SkFontMgr.h`. These establish retained SkData/style-set ownership,
optional kerning, table-copy ownership, and font-stream index semantics.
