# Skia drawing contexts — 0.54

## Scope and requirements

`skia/dc` provides a persistent CPU-raster `skia-dc%` implementing Racket's
public `dc<%>` interface. Drawing uses Skia; text uses the existing Skia font
and HarfBuzz shaping code. This module does not create a GUI or GPU context.
Requiring it does not load Skia or HarfBuzz. Creating a DC requires Skia;
nonempty text measurement and drawing normally also require HarfBuzz.

The minimum is **Racket 8.18 and draw-lib 1.22**. Racket 8.17 introduced the
alpha methods as required interface members; 8.18 includes their default
implementations. The final Skia class explicitly overrides those defaults.
Raising the minimum does not implement alpha-group drawing: that remains 0.55.
The ordinary `skia` module and all Ganesh APIs and native pins are unchanged.

This is a compatibility layer with explicit limits, **not a full drop-in
replacement for every bitmap-dc%, record-dc%, pict or GUI use**. Unimplemented
operations raise `exn:fail:skia-dc:unsupported`; they are not rendered by a
hidden Cairo DC. Importing public `racket/draw` types can load Racket's own
support libraries, but Skia drawing is not routed through Cairo or Pango.

## Construction and lifetime

```racket
#lang racket/base
(require racket/class racket/draw skia/dc)

(define dc
  (new skia-dc% [width 640] [height 400]
       [backing-scale 2.0] [smoothing 'smoothed]))

(dynamic-wind
 void
 (lambda ()
   (send dc clear)
   (send dc set-font (make-font #:size 20 #:family 'swiss))
   (send dc set-text-foreground "navy")
   (send dc draw-text "Skia: office, á, שלום" 24 24 #t)
   (call-with-output-file "dc-example.png"
     (lambda (out) (write-bytes (send dc get-png-bytes) out))
     #:mode 'binary #:exists 'replace))
 (lambda () (send dc close)))
```

Constructor arguments remain `[width 640]`, `[height 480]`,
`[backing-scale 1.0]`, `[background "white"]`, and `[smoothing 'unsmoothed]`.
Logical dimensions are positive exact integers. Physical dimensions are
`ceiling(logical-size * backing-scale)` and must satisfy the existing Skia
surface allocation bounds and `current-skia-byte-limit`. The new surface is
transparent; `background` selects the color subsequently used by `clear`.

A DC belongs to its creating Racket thread; futures and other threads cannot
operate on it. `close` is idempotent on that thread. `ok?` becomes false after
close and when queried from another thread. State, drawing, measurement and
output methods reject a closed DC. Closing releases the backing surface and
unlocks any installed clipping region. Existing native finalization remains a
fallback, not a replacement for deterministic `close`.

The backing surface and canvas remain private. `snapshot` returns an owned
Skia image, independent of later drawing and usable after DC close. The caller
must close that image through the ordinary Skia resource protocol.

| Extension | Result |
|---|---|
| `get-pixel-size` | Two physical pixel dimensions |
| `get-rgba-bytes [#:premultiplied? #f]` | Copied physical RGBA bytes |
| `get-png-bytes` | PNG encoding of the physical backing |
| `snapshot` | Independent, caller-owned Skia image |
| `get-capabilities` | Immutable wrapper declarations, not runtime certification |
| `close` | Explicit release and region unlock |

`get-size` returns logical dimensions; `get-backing-scale` returns the backing
scale. `get-device-scale` returns `(values 1.0 1.0)`, `get-gl-context` returns
`#f`, and `cache-font-metrics-key` returns `0`: no shared external metrics-cache
identity is promised. Module-level exports also include `skia-dc?`,
`skia-dc-capabilities`, and the unsupported exception type/accessors.

## Drawing state and geometry retained from 0.53

The context supports pen/brush/background, alpha, text color/mode/font, smoothing,
origin, scale, rotation, initial matrix and full transformation get/set methods.
Affine coefficients use Racket's `#(xx yx xy yy x0 y0)` order. Positive rotation
is counter-clockwise in the default downward-y coordinates. Backing scale is
applied separately. A singular drawing transform produces no geometry.

Ordinary primitives are `draw-line`, `draw-lines`, `draw-point`, `draw-polygon`,
`draw-rectangle`, `draw-rounded-rectangle`, `draw-ellipse`, `draw-arc`,
`draw-spline`, and `draw-path`. Paths use public `dc-path%` data and preserve
winding/odd-even fill rules. Closed shapes fill before stroking; lines and
splines do not accidentally use the brush.

Solid/transparent brushes and solid/transparent/dot/long-dash/short-dash/dot-dash
pens are supported, with caps, joins and hairlines. Pen/brush selection still
installs immutable snapshots rather than locking the caller's objects. Getters
return the installed immutable objects. Color getters return detached values.

`'smoothed` supports general affine geometry. The foundation's `'unsmoothed`
and `'aligned` snapping supports positive axis-aligned transforms only; rotated,
sheared or reflected aligned geometry remains an explicit unsupported case.
Use `'smoothed` for that geometry. This release does not claim complete Cairo
pixel-alignment, hairline or dash-phase equivalence.

`clear` paints the background with current DC alpha; `erase` clears to
transparency independently of alpha. Both respect the installed clip and
ignore the current drawing transform. Document lifecycle and flush methods
remain checked raster no-ops: they create neither documents nor window queues.

## Text and metrics

```racket
(send dc draw-text text x y [combine #f] [offset 0] [angle 0])
(send dc get-text-extent text [font #f] [combine #f] [offset 0])
(send dc get-char-width)
(send dc get-char-height)
(send dc glyph-exists? character)
```

`draw-text` uses a top-left anchor. Its angle is in radians and turns the text
counter-clockwise around that anchor. All drawing uses the current DC transform,
backing scale, clipping region and opacity. With text mode `'solid`, a background
rectangle is drawn only when the text's own angle is zero, matching the Racket
method contract. Foreground/background color alpha is multiplied by DC alpha.

The three combining modes are distinct:

| Mode | Shaping unit and order |
|---|---|
| `#f` | One Unicode character at a time, in logical order; control/format characters are excluded |
| `'grapheme` | One Racket grapheme cluster at a time, in logical order |
| Other true values | One combined single-line span, using existing mixed-script/bidi shaping and fallback |

Offset counts Racket characters and must lie in `[0,string-length]`. A NUL
terminates the selected text. Measurement and drawing use the same prepared
units and fallback choices. Character-mode widths are additive; grapheme-mode
widths are additive between clusters, without cross-cluster ligatures.

Font translation uses public `font%` accessors: face/family, weight, slant,
fractional pixel size, underline, hinting, smoothing and OpenType feature
settings. `get-size #t` preserves Racket's platform point-to-pixel convention;
backing scale is not folded into the font size. Fallback faces are selected and
drawn through the library's existing mixed-text implementation. A private
Skia-core submodule shares those existing fallback identities for metrics; no
new native symbols or public font API are introduced.

`get-text-extent` returns width, height, descent and extra leading. Extents use
Skia's native font metrics, with a common baseline accounting for selected
fallback runs. Aligned font hinting rounds each shaping unit's advance; unaligned
hinting preserves fractional advances. Empty text has zero width but retains
font height. A zero-sized font yields zero extents and no pixels. Character
metrics use the font's average width and vertical metrics; glyph availability
checks the selected font and an actual fallback font rather than inventing a
positive answer.

Native font, manager and shaper objects are scoped to each call. There is no
unbounded cross-call text cache or exposed native handle. This prioritizes a
clear lifetime boundary; no text-performance claim is made.

### Text limits

Combined/grapheme text containing tabs or hard line separators is explicitly
rejected in 0.54; it is not silently treated as a paragraph. Select an explicit
font face when a font-name-directory mapping contains a comma/Pango description;
that description syntax is not parsed as a Skia family. Smoothed text uses
grayscale, not LCD subpixel antialiasing, on the alpha-capable backing.

Font fallback, rasterization and metrics may differ from Cairo/Pango. Extents
are logical typographic extents, not a promise that every overhanging glyph or
underline pixel lies inside them. Exact text pixel/metric equivalence, every
platform's emoji behavior, and complete editor/pict compatibility are not
certified by this stage. The text input and bitmap bridge enforce the existing
byte limit on their checked buffers; that is not a global process-memory bound.

## Bitmap input, masks and copy

```racket
(send dc draw-bitmap bitmap x y [style 'solid] [color black] [mask #f])
(send dc draw-bitmap-section bitmap x y sx sy sw sh
      [style 'solid] [color black] [mask #f])
(send dc draw-bitmap-section-smooth bitmap x y dw dh sx sy sw sh
      [style 'solid] [color black] [mask #f])
(send dc copy x y width height x2 y2)
```

The first two methods are `dc<%>` operations; the smooth-section operation is a
bitmap-dc-like convenience. `black` above denotes a black `color%` object. A
valid bitmap returns `#t`, including an empty/off-target drawing; a failed source
bitmap returns `#f`. Invalid masks and unsupported configurations raise.

Public `bitmap%` pixels are copied on each operation, using `#:unscaled? #t` to
retain physical backing resolution. No Cairo bitmap handle is borrowed and no
unsafe cache ignores later bitmap mutation. Logical source coordinates are
converted to physical coordinates. Partially out-of-range source rectangles
clip source and destination together instead of stretching the remaining image.

Color sources preserve their color/alpha and ignore monochrome style/tint.
For monochrome sources, `'solid` draws black bits with the supplied color and
leaves white bits transparent; `'opaque` uses the DC background for white bits.
Monochrome `'xor` remains explicitly unsupported. Smoothing selects nearest
sampling for `'unsmoothed`, linear otherwise; the smooth-section method always
uses linear sampling without changing the caller's DC state.

Only the explicit mask argument is applied; callers wanting a loaded mask must
pass `(send bitmap get-loaded-mask)`. Masks must be valid and have the same
logical dimensions as the source. Alpha masks use their alpha channel; masks
without alpha use inverse average RGB (black opaque, white transparent).
Source alpha and mask coverage are combined once, then converted to premultiplied
RGBA; DC opacity is applied by Skia. Differing mask backing scales are sampled
at source-pixel centers using nearest mask pixels. This explicit bounded policy
is not a claim of identical Cairo sampling at every fractional scale.

`copy` snapshots the native Skia backing before drawing. It therefore handles
overlap without feeding modified destination pixels back into the source. It
uses source replacement, ignores current DC opacity, and respects destination
clipping. Source and destination are in the same DC coordinate system: under an
affine map, the physical displacement is its linear part applied to the logical
displacement. Outside-surface source samples are transparent (decal sampling).
There is no CPU readback in this native raster-surface copy implementation.

## Real region% clipping

```racket
(define region (new region% [dc dc]))
(send region set-ellipse 20 20 120 80)
(send dc set-clipping-region region)
;; Draw while clipped; the selected region cannot be modified.
(send dc draw-bitmap bitmap 0 0)
(send dc set-clipping-region #f)
```

`set-clipping-rect` now builds a real associated region. `get-clipping-region`
returns the actual selected region rather than the earlier rectangle ticket.
Associated regions must belong to this exact DC and retain their construction-
time transformation. Unassociated regions are transformed when installed.
Later DC transform changes do not move the installed clip.

The region adapter copies all constituent paths and their fill rules. Multiple
region paths represent intersections and are installed as sequential Skia clips.
Empty regions clip out everything. Standard region construction and its path-
based combinations, including odd-even holes, are consumed without flattening
into a rectangle or raster mask.

The selected region is locked using Racket's region protocol. Replacing/removing
it or closing the DC releases that lock. Validation precedes selection changes;
a rejected region does not discard the old clip. A finalizer provides a weak-
reference lock-release fallback without retaining an otherwise dead DC.

Only `private/dc-region-adapter.rkt` imports `racket/draw/private/region` and
`racket/draw/private/local`. It implements the exact private clipping-matrix
member identity required by region construction, checks the path representation,
and exposes only copied commands to the renderer. All other DC modules stay
on public Racket drawing types. Minimum-version and current-version CI must
exercise this adapter; private upstream representation changes require review.

**Remaining region limit:** some built-in region utility operations, notably
`is-empty?` on a nonempty associated region, ask their DC for a Cairo context.
The Skia DC does not manufacture one. Such utility queries are not promised by
this stage even though the region can be installed and clipped correctly. Full
associated-region utility compatibility belongs to 0.55.

## Remaining unsupported operations

The exception `exn:fail:skia-dc:unsupported` extends `exn:fail:contract` and carries
`method`, `feature`, and planned `stage`. An exception is not a successful draw.

| Deferred area | Operations |
|---|---|
| 0.55 styles and grouping | Gradients, stipples, hatches, XOR/hilite pens/brushes, alpha groups |
| 0.55 broader compatibility | Path ink bounds, complete alignment and object-lock semantics, associated-region utility queries, direct record-dc% replay |
| 0.56–0.57 GUI | skia-canvas%, persistent GUI management, scoped GPU-frame facade |

`start-alpha` still raises; `end-alpha` with no active group is a no-op.
Direct `record-dc%` replay remains deferred: current Racket recordings use
internal replay helpers such as `do-set-pen!` and `do-set-brush!`, beyond the
public DC method boundary. Ordinary user procedures using supported public
methods can draw directly. This distinction is not erased by satisfying the
`dc<%>` interface.

## Validation and evidence

Run `python3 tools/validate-dc.py --racket "$RACKET"`. The required sequence
compiles the modules and executes all four suites:

| Suite | Cases |
|---|---:|
| Foundation pure | 60 |
| Foundation native | 31 |
| Text/bitmap/region pure | 36 |
| Text/bitmap/region native | 34 |

Thus the DC gate executes **96 pure and 65 native cases**. Foundation case
counts and the 48x40 independent exact oracle are retained. A second independent
64x48 exact oracle covers bitmap pixels/masks, HiDPI source sampling, copy,
region holes/intersections and construction/installation transforms.

Five PNGs are retained: both exact oracles, the existing 460x320 Skia/Racket
geometry examples, and a 320x104 colored Skia text sample. The large examples
remain manual-review material. The text-sample inspector requires nonempty
colored ink; it does not independently prove glyph shape or text equivalence.
Native tests separately exercise text measurement/drawing consistency and the
supported mode/lifetime behavior. Snapshots are encoded after the DCs close.

All CPU CI lanes, including the required Racket 8.18 lane, use the same validator
from an isolated installed package. The artifact subdirectory remains
`dc-foundation` for compatibility with CI report consumers. Missing captures,
wrong pixels, reduced counts, old interpreters and failed commands are errors,
not optional skips. Existing GPU gates, workloads and pins are unchanged.

The source baseline for this candidate is
`ad31074e2b3a9727a4e830290d0bf2efda031292`. Delivery checks and source inspection
are not runtime acceptance; review the resulting host and CI evidence before
accepting 0.54. The candidate does not retroactively turn earlier 8.7/8.17
failures into successful runs.

## Reference contracts

- Racket dc<%>: <https://docs.racket-lang.org/draw/dc___.html>
- Racket font%: <https://docs.racket-lang.org/draw/font_.html>
- Racket bitmap%: <https://docs.racket-lang.org/draw/bitmap_.html>
- Racket region%: <https://docs.racket-lang.org/draw/region_.html>
- Racket 8.18 draw interface: <https://github.com/racket/draw/blob/v8.18/draw-lib/racket/draw/private/dc-intf.rkt>
- Default implementations (draw-lib 1.22): <https://github.com/racket/draw/commit/55819da32ae19b9c900bb2c64edb8600dd8c720d>
- Isolated region adapter reference: <https://github.com/racket/draw/blob/v8.18/draw-lib/racket/draw/private/region.rkt>
