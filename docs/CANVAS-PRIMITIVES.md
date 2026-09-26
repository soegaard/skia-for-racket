# Canvas primitives and scoped compositing layers

Available from `(require skia)` or `(require skia/canvas-primitives)`. All drawing
uses the existing borrowed `canvas?` and owned `paint?` resources, with the same
close/thread rules. No raw pointers or native rounded-rectangle handles escape.

## Points, line sets, and arcs

```racket
(draw-point canvas x y paint)
(draw-points canvas points paint #:mode 'points)
(draw-arc canvas x y width height start-degrees sweep-degrees paint
          #:use-center? #f)
(draw-color canvas color #:blend-mode 'src-over)
```

`points` is a list or vector of two-element point lists/vectors. Modes are:

- `'points`: independent point sprites. Stroke width gives their size; round caps
  produce circles, the other caps produce squares. Paint fill style is ignored.
- `'lines`: independent pairs. The wrapper requires an even count instead of
  silently dropping a trailing point.
- `'polygon`: consecutive line segments, without a closing edge. This differs
  from the existing closed `draw-polygon` helper. Segments use native point-mode
  semantics, not a single joined stroked path. The wrapper submits explicit
  independent pairs, also when recording, so SVG cannot turn them into joined
  vertices. The expanded native buffer is included in byte-limit validation.

An empty list does nothing but still checks canvas/paint lifetime and thread
ownership. Coordinates and count are checked before native submission. The
copied point buffer respects `current-skia-byte-limit` and the native int count
limit. No caller list/vector is retained, including during picture recording.
Zero stroke width retains Skia's device-hairline behavior.

Arc coordinates describe an oval's bounding rectangle. Zero degrees points
right; positive sweeps are clockwise in the initial y-down coordinate system.
A positive sweep of 360 degrees or more draws the full oval. The native API also
accepts negative sweeps. `#:use-center? #t` includes the oval center (a sector);
otherwise an open stroked arc or a chord-closed filled segment is drawn. Empty
ovals and zero sweeps paint nothing. Paint fill/stroke and cap settings apply.

`draw-color` covers the current clip and applies the selected blend mode; it is
not a transformed finite rectangle. Default source-over differs from the
source-replacing behavior of `canvas-clear!` when alpha is present.

The wrapper temporarily resets and then restores the matrix for this fill,
leaving the device clip unchanged. This avoids the pinned SVG drawPaint
implementation applying a local transform to its device-sized rectangle.
An unbounded color fill stored in a picture remains replay/clip-dependent:
the auditor conservatively requires rasterization for its SVG replay. Use a
finite `draw-rect` when a recorded background should have fixed local bounds.

## Four-corner rounded rectangles

```racket
(make-rounded-rect x y width height #:radii 0)
(rounded-rect? value)
(rounded-rect-bounds specification) ; immutable #(x y width height)
(rounded-rect-radii specification)  ; immutable vector of four immutable #(rx ry)

(draw-rrect canvas specification paint)
(draw-double-rounded-rect canvas outer inner paint)
(canvas-clip-rounded-rect! canvas specification
                           #:operation 'intersect #:antialias? #f)
```

These are **pure immutable specifications**, not owned resources; do not put
them in `with-skia`. Radii are a nonnegative scalar (same circular radius at
all corners), or four pairs in **top-left, top-right, bottom-right, bottom-left**
order. Lists and vectors are accepted and deeply copied. For example:

```racket
(define shape
  (make-rounded-rect 20 30 200 100
                     #:radii '((0 0) (30 20) (12 12) (24 36))))
(draw-rrect canvas shape paint)
```

The accessors return the requested specification. On submission, Skia normalizes
radii that do not fit the sides, proportionally reducing them. A corner with a
zero component becomes square. Native normalization may involve single-precision
rounding; the wrapper does not pretend requested radii are native normalized
radii. Zero-area specifications are permitted. Negative and non-finite inputs
and overflowing computed rectangle edges are rejected.

Double-rounded drawing leaves the interior unfilled (and respects paint stroke
style). The native operation is undefined for non-contained inner shapes. This
wrapper therefore uses a **sufficient but conservative** test: the entire inner
*bounding rectangle* must fit within the normalized outer rounded shape. Some
geometrically valid pairs whose bounding-box corners lie outside the outer curve
are rejected. An empty inner specification draws only the outer shape. Use
existing PathOps for more general hollow shapes.

Rounded clipping first normalizes through native SkRRect, then rebuilds a plain
path from the normalized verbs. This avoids the pinned SVG serializer's direct
RRect-clip shortcut, which writes only one `rx`/`ry` pair and cannot preserve
four different corners. The ordinary path representation also survives picture
recording and later SVG replay without erasing the corner differences.

Clip operation is `'intersect` or `'difference`. Difference clipping still needs
explicit fallback for reliable SVG; use the output auditor. The prior
`draw-rounded-rect` convenience API remains unchanged.

## Querying the clip

```racket
(canvas-local-clip-bounds canvas)     ; immutable #(x y width height), or #f
(canvas-device-clip-bounds canvas)    ; immutable integral vector, or #f
(canvas-clip-empty? canvas)
(canvas-clip-rect? canvas)
(canvas-quick-reject? canvas x y width height)
```

Device bounds are in the native device grid. They stay fixed when the current
transform changes, but are not universally PDF points or output CSS pixels:
PDF's internal raster scale is relevant. Local bounds use the inverse transform
and can be conservatively enlarged. An empty clip (or unavailable local inverse)
returns `#f`. Returned values are detached and remain usable after canvas closure.

A true quick-rejection result means the supplied rectangle is outside the clip.
False means **not quickly rejected**, not proven visible. Include stroke/filter
expansion in the supplied rectangle before using it to skip expensive drawing.
The wrapper does not install automatic culling or convert these queries into
exact shape intersection tests.

## Compositing layers

```racket
(canvas-save-layer! canvas #:bounds #f #:paint #f) ; returns pre-save count
(call-with-canvas-layer canvas thunk #:bounds #f #:paint #f)
(with-canvas-layer canvas #:bounds bounds #:paint paint body ...)
```

`thunk` takes **zero arguments**, as in `call-with-canvas-state`, and can return
any number of values. The macro permits either keyword, both (in either order),
or neither. Drawing keeps the same local coordinate system; this is not the
origin-resetting interface of `draw-rasterized`.

A layer starts transparent, receives subsequent drawing, and composites into
its parent when restored. Its paint applies group alpha, color/image filters,
and blending **once at restore**, not once per object. Color channels, shader,
stroke geometry, path effects, and mask filters of the layer paint are not a
replacement for the paints used inside the group. The native layer snapshots
its paint state, so the caller can close or mutate that paint after save.

```racket
(with-skia ([group (make-paint #:color (rgba 0 0 0 128))]
            [red (make-paint #:color 'red)]
            [blue (make-paint #:color 'blue)])
  (with-canvas-layer canvas #:paint group
    (draw-rect canvas 10 10 120 80 red)
    (draw-rect canvas 70 10 120 80 blue)))
```

The overlap is blue inside the group, then receives group opacity. Giving both
objects half opacity would instead let red contribute to the overlap.

### Bounds: use conservative content bounds

`#:bounds` is `#f`, or an `(x y width height)` list/vector in current local
coordinates. It is passed to the native layer API. **Do not draw outside the
supplied content bounds expecting preservation.** Although general Skia API
documentation calls this a hint, the pinned m119 implementation can intersect
an unfiltered layer's extent with those bounds; filtered/custom-blend paths can
size it differently. Use `#f` when a reliable conservative bound is unavailable.
For a deliberate portable clip, call `canvas-clip-rect!` explicitly inside the
layer. Include all relevant input/filter extents in bounds and fallback padding.

Native layer allocation can be larger than supplied local bounds after
transforms and filtering. `current-skia-byte-limit` is not a bound on internal
layer allocations or total native heap use. Use explicit bounded raster groups
when exact fallback pixel dimensions need to be chosen and checked.

### State, exceptions, and closing

Restore a low-level layer with `canvas-restore!` or
`canvas-restore-to-count!` using the returned pre-save count. Scoped layers protect
their own stack entry, unwind extra saves, preserve multiple values, and restore
on raised values, breaks, or continuation escape. Re-entry into an expired scope
is unsupported. Closing an owner in the body skips dangling-pointer cleanup.
Ending a PDF page, finishing SVG, or finishing a picture recorder while inside
a protected scope is rejected. The recorder guard also applies to existing
`with-canvas-state` scopes.

**Restoration is not rollback:** a partially drawn layer can composite during
exception cleanup. The enclosing scoped PDF/SVG file helpers still discard an
unsuccessful export; raster pixels are not transactional.

## Output auditing and backend limits

The new operations participate in direct, preflight, and recorded-picture audits.
Arcs, rounded geometry, line pairs/open polylines, and intersection clips use the
ordinary geometry/paint rules. Non-default `draw-color` blending is reported.

| Feature | PDF audit | SVG audit |
| --- | --- | --- |
| Isolated point sprites | vector | needs-raster |
| Native compositing layer | native-expansion | needs-raster |
| Recorded unbounded color fill | vector | needs-raster |
| Either inside explicit raster group | rasterized | rasterized |

The pinned SVG device does not implement independent point sprites. Normal
un-audited SVG output can omit them. Strict audited export rejects the unsupported
call rather than silently repairing it. Use `draw-rasterized`, or explicitly draw
circle/rectangle geometry when that matches the desired semantics. Do not infer
hairline or cap behavior from geometric replacements.

Native layers are not universally representable by the SVG writer. PDF can
retain or expand them depending on effects. An audit classification is not a
promise of zero images in PDF. Rasterization of a backdrop-dependent blend must
include the required backdrop. Place document links outside layers/fallback
regions: layer-contained annotations may be lost when a native layer rasterizes.
The layer warning is conservative, not a per-device annotation-preservation
proof. Existing explicit-raster annotation-loss reporting remains unchanged.

## Pinned implementation references

Native source: `mono/skia` commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/c/sk_canvas.h`, `include/c/sk_rrect.h`, `src/core/SkCanvas.cpp`
(`get_layer_mapping_and_bounds`, `internalSaveLayer`, `onDrawPoints`),
`src/core/SkRRect.cpp` (radius normalization), and `src/svg/SkSVGDevice.cpp`
(point-mode implementation). These pinned sources take precedence over a
newer generic API page when behavior differs.
