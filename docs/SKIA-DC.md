# Skia drawing contexts — 0.57 drawing contract

## Compatibility closure in 0.64

[The current compatibility boundary](DC-COMPATIBILITY.md) supersedes the older
font-description rejection below: single-family comma descriptions now support
weight, slant and stretch, and explicit faces honour font-directory overrides.
Combined tabs/hard breaks and richer font-description semantics remain explicit
exclusions; VT/FF are included in the separator guard. The additive
`skia-dc-compatibility` query accounts for the full installed DC method contract.
The historical 0.57 capability report and existing raster/GPU/document lifetimes
remain unchanged. Earlier stage descriptions below retain their historical scope.

## Canvas ownership added in 0.58

The GUI-only `skia/canvas` module now exposes this persistent raster DC through
`skia-canvas%`. Its DC keeps its identity and drawing state while resize/backing
scale changes replace the private raster storage. See
[the canvas contract](SKIA-CANVAS.md) for callbacks, presentation, resize,
explicit handler-thread close and the separate required GUI gate. Requiring
`skia/dc` still does not initialize the GUI. The existing DC capabilities and
0.57 validator report retain their 0.57 version and drawing scope.

## Direct consumer coverage in 0.56

This narrowly scoped stage adds a required corpus of actual `pict` and
`plot/no-gui` clients using the already implemented drawing subset. It does not
add gradients, stipples, hatches, general alignment, region utility emulation,
or GUI canvases. See [the consumer guide](DC-CONSUMERS.md) for tested operations,
font/layout boundaries and the native acceptance gate. Package installation
now also supplies `pict-lib` and `plot-lib` for the installed validation modules;
merely requiring `skia/dc` does not import those clients or initialize a GUI.

## 0.57 current compatibility additions

See [DC styles, geometry queries and their limits](DC-STYLES.md) for gradients,
stipple pens/brushes, six hatches, legacy aliases, affine alignment and path bounds.
Associated-region utilities now have an isolated query-only Cairo context. It is
never given the Skia backing and is never used as a drawing fallback. Native
Cairo-handle brushes remain unsupported. Earlier stage descriptions below are
historical where explicitly superseded by this 0.57 contract.

## Scope and requirements

`skia/dc` provides a persistent CPU-raster `skia-dc%` implementing Racket's
public `dc<%>` interface. Drawing uses Skia; text uses the existing Skia font
and HarfBuzz shaping code. This module does not create a GUI or GPU context.
Requiring it does not load Skia or HarfBuzz. Creating a DC requires Skia;
nonempty text measurement and drawing normally also require HarfBuzz.

The minimum is **Racket 8.18 and draw-lib 1.22**. Racket 8.17 introduced the
alpha methods as required interface members; 8.18 includes their default
implementations. The final Skia class explicitly overrides those defaults.
0.55 implements nested alpha groups and both upstream recording replay forms.
The minimum is unchanged from 0.54; no conditional older-interface class is added.
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

Ordinary and extended styles are supported as described in DC-STYLES.md,
including gradients, stipples, hatches and the pinned legacy aliases. **0.55 changes selection
semantics:** `set-pen` / `set-brush` retain and lock the supplied object instead
of installing an immutable copy. `get-pen` / `get-brush` return that same object.
A mutable selection cannot be changed until every selecting DC has released it.
Replacement and explicit close release each DC's lock exactly once; reselection
of the same object does not add a lock. Cached immutable objects remain immutable
when released. Color getters still return detached values.

Validation occurs before replacing the current selection, and validation,
locking, and installation are atomic with respect to Racket thread scheduling.
An unsupported candidate leaves the previous object selected and locked. A
weak-reference finalizer releases locks when a DC is collected; deterministic
`close` remains the intended lifetime boundary. 0.57 supports public stipple and
gradient sources; their separately mutable data is copied for every draw.

`'smoothed` supports general affine geometry. As of 0.57, `'aligned` and
`'unsmoothed` also accept nonsingular finite affine transforms, using upstream
effective row-norm snapping. Complete Cairo edge/hairline/dash identity is not
claimed. See DC-STYLES.md for geometric path-bound queries.

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
Monochrome `'xor` uses the legacy solid semantics in 0.57. Smoothing selects nearest
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

Private Racket dependencies are isolated in two adapters:
`private/dc-region-adapter.rkt` consumes checked region paths and the private
clipping-matrix identity, while `private/dc-replay-adapter.rkt` imports the exact
`do-set-pen!` / `do-set-brush!` identities from `racket/draw/private/dc` and
`adjust-lock` from `racket/draw/private/local`. The region adapter delegates
utility queries to `dc-region-query.rkt`, which owns a temporary query-only
Cairo recording context. It receives no Skia pixels; no drawing is rerouted.
Other DC modules use public Racket drawing types. Minimum/current-version CI must exercise these
adapters; a change in upstream private protocols requires review.

**Region utilities in 0.57:** the private query callback is supplied by an
isolated scratch Cairo recording context. It receives no Skia pixels, and its
contents are never rendered to the output. Upstream utility approximations and
caching remain. See DC-STYLES.md for the query-only boundary and cleanup rules.

## Direct recorded drawing

```racket
(define recording (new record-dc% [width 640] [height 400]))
(send recording set-smoothing 'smoothed)
(send recording set-brush "navy" 'solid)
(send recording draw-rectangle 10 20 80 40)

((send recording get-recorded-procedure) dc)
((recorded-datum->procedure (send recording get-recorded-datum)) dc)
```

Both forms use Racket's own recording interpreter without rewriting the datum
format or special-casing a recorded program. The adapter implements the actual
private local-member identities, not public symbols with the same spelling.
Replay passes through normal Skia DC validation and pen/brush locking.

Supported recorded operations include the established geometry, text, bitmap,
transform, region, and alpha-group subset. Successful upstream replay restores
the destination's saved pen and brush **identities**, font, smoothing, text mode
and colors, background, opacity, transformation, and selected clipping region.
The recording's transform, opacity, and clip composition remain controlled by
Racket's upstream replay procedure. A recording using a still-unsupported style
raises the usual unsupported exception; replay is not an implicit fallback.

**Exception boundary:** upstream `record-dc%` replay restores state after normal
completion, not through an exception-safe transaction. An exception from a
recorded operation can leave partially drawn pixels and changed destination
state, including unfinished alpha groups. This stage does not promise rollback
for upstream procedures. Explicitly closing the DC releases its locks and
all unfinished group storage without committing those groups. Balanced valid
recordings are the supported replay contract, not arbitrary malformed datums.

## Nested alpha groups

```racket
(send dc set-alpha 0.8)
(send dc start-alpha 0.5) ; saves 0.8; get-alpha is now 1.0
(send dc set-brush "red" 'solid)
(send dc draw-rectangle 10 10 60 40)
(send dc set-brush "blue" 'solid)
(send dc draw-rectangle 40 10 60 40)
(send dc end-alpha)      ; composites once at 0.8 * 0.5; restores 0.8
```

`start-alpha` requires a finite real in `[0,1]`. Each group has an independent,
initially transparent CPU Skia raster surface at the DC's physical dimensions.
Group storage is bounded to those physical dimensions: off-canvas drawing is
not retained for a later copy back into the canvas. This is not an unbounded
Cairo recording surface. The group starts with drawing alpha 1.0. Its constituent shapes therefore
occlude one another normally before the completed group is composited once.
This is not equivalent to multiplying each constituent draw's alpha.

Groups can nest. `end-alpha` composites into the immediately enclosing target
using the saved outer alpha multiplied by the group's alpha, and restores that
saved drawing alpha. Changing alpha inside the group affects its draws, not its
stored group opacity. An unmatched `end-alpha` is a checked no-op. Transforms and
backing scale apply to constituent drawing; merging uses physical coordinates
and does not apply the current drawing transform again.

Clipping follows Racket's separate group-target behavior: the parent's clip at
entry remains on the parent and is applied at merge. A new group has no inherited
clip; a `set-clipping-region` / `set-clipping-rect` during the group changes that
group's clip. Ending the group returns to the parent's saved clip. Other drawing
state is not pushed by `start-alpha`; in particular, the global selected region
object still records the most recent selection. Reselect it after `end-alpha`
when the intent is to install it on the parent too. This distinction prevents
applying the parent's clip both to every child draw and again to the whole group.

Text, bitmap drawing, clear, erase, and copy use the active target. A copy inside
a group sees that group's contents, not the root or parent. `snapshot`,
`get-rgba-bytes`, and `get-png-bytes` are explicit extensions that inspect the
**root backing only**: an unfinished group is not implicitly merged or exposed
as an independent external target. Existing snapshots remain independent.

Before allocating a layer, the controller checks the aggregate full-sized RGBA
storage for the root and all live group surfaces against
`current-skia-byte-limit`. Allocation failure leaves the parent and alpha state
unchanged. This is a surface-storage budget, not a bound on all allocator memory,
retained client snapshots, or native temporary storage. No GPU readback or CPU
pixel round trip is used to merge these CPU-native surfaces.

A failed merge is propagated. The group is already popped, the parent/alpha are
restored, and the child is released; retrying `end-alpha` cannot repeat that merge.
As with any failed native drawing operation, pixel rollback is not promised.
`close` discards unbalanced groups rather than silently compositing them and
attempts to release every owned target even when an individual release fails.

## Remaining unsupported operations

The exception `exn:fail:skia-dc:unsupported` extends `exn:fail:contract` and carries
`method`, `feature`, and planned `stage`. An exception is not a successful draw.

| Deferred area | Operations |
|---|---|
| Still deferred | Native Cairo-handle brushes; arbitrary platform-specific native pattern sources |
| Not universally certified | Exact Cairo edge/metric equivalence and consumers outside the tested subset |
| Deferred text edge cases | Combined tabs/hard breaks and Pango font-description interpretation |
| 0.59 GPU facade | GPU-backed `skia-canvas%` with frame-scoped `dc<%>` lifetime |

The replay suite deliberately does not add `pict`, plotting, gradients or new
styles to 0.55's acceptance criteria. Interface membership is not evidence of
universal drop-in compatibility. No new native pins or backend expansions occur.

## Validation and evidence

Run `python3 tools/validate-dc.py --racket "$RACKET"`. The required sequence
compiles the modules and executes all seven RackUnit suites:

| Suite | Cases |
|---|---:|
| Foundation pure | 60 |
| Foundation native | 31 |
| Text/bitmap/region pure | 36 |
| Text/bitmap/region native | 34 |
| Replay/locking/alpha pure | 28 |
| Replay/locking/alpha native | 28 |
| Real pict/plot consumers and replay | 16 |

Thus the DC gate requires **124 pure and 109 native cases**. The replay pure suite
also invokes 24 standalone production alpha-controller cases using a recording
renderer; those 24 cases are not claimed as native pixel tests. Run them alone
with `racket tests/dc-alpha-test.rkt` without Skia or `racket/draw`.

The original 48x40 foundation oracle and 64x48 bitmap/region/copy oracle remain
**exact**. Three new 48x32 captures render the alpha corpus directly, through an
upstream recorded procedure, and through an upstream recorded datum. Each is
checked against an independently calculated analytical compositing oracle with
a maximum error of **2 per 8-bit channel** to accommodate alpha quantization in
nested compositing. Agreement between the three implementations alone is not a
pass. No tolerance is added to either existing exact oracle.

The eight existing PNGs are retained: the two exact oracles, those three alpha captures,
the existing 460x320 Skia/Racket geometry examples, and a 320x104 colored text
sample. The large examples remain manual-review material; the text image does
not independently prove glyph shape or Cairo/Pango equivalence. Native replay
tests separately require actual colored text ink and a known bitmap pixel.
Every retained Skia snapshot is encoded after its DC closes.

Eight additional 320x240 consumer PNGs show direct, recorded-procedure,
recorded-datum and Racket reference drawing for each of `pict` and `plot/dc`.
Each image must pass semantic pixel probes; matching empty images cannot pass.
The two replay forms of the same recording are compared within two channel
units. Direct/reference image differences are retained for manual inspection,
not subjected to an invented universal text/raster tolerance.

All existing CPU CI lanes, including required Racket 8.18, invoke this validator
from the isolated installed package. The artifact directory remains
`dc-foundation`. The 0.55 suites remain wired into `run-tests.rkt`, with pure
replay running before native installation. The new 0.56 consumer suite is
mandatory inside this installed-package DC gate. Missing captures, reduced counts,
failed commands, wrong pixels, or stale/mismatched evidence fail the gate.
Existing GPU jobs, workloads, dependencies and pins are unchanged.

The 0.56 source baseline is `f1568cf68e57b0358ac27e4c5eeb1e0e33e6de8a`,
accepted by the maintainer after the 0.55 Mac gate and CI passed. The two GPU
demos and here-string checker fix are preserved. 0.56 acceptance requires its
own actual native/consumer and minimum-version CI results; source reading and
synthetic Python inspector tests alone do not establish that acceptance.

## 0.57 acceptance

The required DC validator now adds style suites and four semantic style captures.
See DC-STYLES.md for counts and drawing limits. The raster canvas is added in
[0.58](SKIA-CANVAS.md); the remaining GUI roadmap stage is the 0.59 GPU facade.
