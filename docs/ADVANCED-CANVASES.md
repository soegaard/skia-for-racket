# Advanced layers, drawables and specialized canvases — 0.74

Package version **0.74**; application baseline
`e9c91df2be2e305bde4d38d0643a6b98669968ba` (accepted 0.73 plus hotfixes).
SkiaSharp **3.119.1**, Skia **m119**, HarfBuzzSharp **8.3.1.2**, minimum Racket
**8.18**, and `draw-lib` **1.22** are unchanged.

Require `skia` for the public facade. The focused modules are `skia/layer-options`,
`skia/advanced-layers`, `skia/drawables`, and `skia/specialized-canvases`.
GPU targets still require `skia/gpu` and their matching active context.
Importing the new modules does not create a GPU, GUI, surface or native drawable.

## Layer records

```racket
(make-layer-options
  #:bounds #f
  #:preserve-lcd-text? #f
  #:initialize-with-previous? #f
  #:f16? #f)

(layer-options? value)
(layer-options-bounds options)
(layer-options-flags options)
(layer-options-preserve-lcd-text? options)
(layer-options-initialize-with-previous? options)
(layer-options-f16? options)
```

Options are immutable values, not resources. A supplied bounds list/vector
`(x y width height)` is checked and copied into an immutable vector. Coordinates
must be finite representable scalars; extents are nonnegative. `#f` means no
bounds hint. The options do not hold a native paint or backdrop pointer.

The reviewed m119 flags are `2` (LCD text preservation), `4` (initialize with
previous content), and `16` (F16 layer storage). The constructor takes booleans,
not arbitrary numeric flag bits. No flag is enabled by default. Requesting LCD
preservation does not certify subpixel text or discover a physical monitor's
pixel geometry. The F16 flag concerns the intermediate layer, not the final
window or document's color precision. In particular, m119 does not promise that
restoring/compositing an F16 layer is a bit-preserving or extended-range-preserving
copy into the destination.

```racket
(canvas-save-layer-rec! canvas
  #:options (make-layer-options)
  #:paint #f
  #:backdrop #f)

(call-with-canvas-layer-rec canvas thunk
  #:options (make-layer-options)
  #:paint #f
  #:backdrop #f
  #:clip #f)
```

`canvas-save-layer-rec!` creates the native layer and returns the previous save
count. Restore with the ordinary canvas restore operations. The existing
`canvas-save-layer!` and `call-with-canvas-layer` are unchanged; this is the
additive entry point for the richer C record.

`call-with-canvas-layer-rec` takes a zero-argument thunk. It returns the thunk's
values, pins the owner against explicit closure during the scope, protects its
restore floor, and restores native canvas state on normal return, exception or
continuation escape. Native restoration composites the layer even after a user
exception; this is **not pixel rollback**. Reentry of an expired scope rejects.

The optional paint controls layer composition, not each individual primitive.
The optional backdrop must be a live `image-filter?` belonging to the compatible
execution domain. These resources are validated when saving the layer. Native
layer/recording ownership retains what it needs; closing an original wrapper
after the successful save does not revoke native retained references. A recorder
that retains a GPU-affine backdrop inherits that affinity.

### Bounds are not a clipping API

Native layer bounds are advisory input to allocation/content handling. The
pinned backend can restrict work to those bounds; drawing outside a small hint
is not promised. They do not establish a reliable application-level clipping
contract. Use `#:clip` or the existing explicit clip operations to bound drawing.

```racket
(with-skia ([opacity (make-paint #:color (rgba 0 0 0 128))])
  (call-with-canvas-layer-rec canvas
    (lambda ()
      (draw-rect canvas 8 8 24 24 red-paint)
      (draw-circle canvas 28 20 10 blue-paint))
    #:paint opacity
    #:options (make-layer-options #:bounds '(0 0 48 40))
    #:clip '(0 0 48 40)))
```

This composes a group with half opacity. The clip is real; the bounds hint must
still conservatively cover the intended content/filter footprint.

### Backdrops and initialization

`#:backdrop` filters pixels already present in the destination; initialization
copies existing destination content into the new layer. Those pixels must exist
in the same rendering operation. A later group cannot retroactively capture a
PDF/SVG page's outer backdrop. Native filters can allocate internal scratch
storage; wrapper bounds and `current-skia-byte-limit` are not a universal cap on
those allocations.

The C layout is three pointers (`bounds`, `paint`, `backdrop`) and one enum-sized
flags field. It is **not** the layout of C++ `SkCanvas::SaveLayerRec`. The record
and its temporary rectangle stay rooted for the synchronous call; no Racket
callback is installed in that native record.

## Discard hint

```racket
(canvas-discard! canvas)
```

This is the native destination-content invalidation hint, **not** a clear to
transparent, an eraser, or an operation with defined previous pixel values.
Completely overwrite discarded content before observing or relying on it.
Document auditing classifies discard as semantic loss and rejects it in strict
export, even if the native PDF/SVG device might ignore the hint.

## Native recorded drawables

```racket
(picture->drawable picture)
(call-with-drawable width height draw-callback)
(drawable? value)

(draw-drawable canvas drawable #:matrix #f #:mode 'retained)
(drawable->picture drawable)
(drawable-bounds drawable)
(drawable-generation-id drawable)
(drawable-approximate-bytes-used drawable)
(drawable-notify-drawing-changed! drawable)
```

These operations create a **real native SkRecordedDrawable**, not an alias for
`picture?`. `picture->drawable` records the supplied immutable picture into the
native drawable constructor. `call-with-drawable` first captures authoring once;
its callback receives an ordinary recording canvas. Neither native replay nor
fan-out reruns that application callback.

The public drawable subset is deliberately **recorded-only**. It does not expose
an externally mutable or Racket callback-backed native drawable. A native
`SkDrawable` can support more general mutation, but this wrapper does not pretend
an immutable captured command list is such an editing API.

`#:mode 'retained` calls canvas `drawDrawable`, allowing a native recorder to
retain the drawable. `#:mode 'immediate` invokes drawable drawing directly on the
canvas. Both go through the same ownership and output-policy checks. `#:matrix`
is `#f` or an existing affine `matrix?`; there is no unvalidated native matrix
pointer option.

Drawables participate in `skia-resource?`, `with-skia`, `skia-close!` and the
existing thread/context rules. They own independent native references. Pictures,
paints and other sources may close without invalidating retained content.
`drawable->picture` returns an independently owned native snapshot, retaining
GPU affinity and output provenance where applicable. It is not a CPU pixel
materialization or a way to remove a GPU dependency.

Bounds are copied as `(x y width height)` in an immutable vector. Generation IDs
and approximate byte counts are detached scalars. Approximate bytes are a native
estimate, not total retained memory, driver allocations or process RSS.
`drawable-notify-drawing-changed!` invalidates native generation metadata; it does
not edit the captured commands, authorize external mutation, or revive a closed
resource.

```racket
(with-skia ([drawable
             (call-with-drawable 64 48
               (lambda (c)
                 (with-skia ([ink (make-paint #:color 'blue)])
                   (draw-rect c 8 8 24 24 ink))))])
  (draw-drawable canvas drawable)
  (with-skia ([snapshot (drawable->picture drawable)])
    (draw-picture canvas snapshot #:x 80 #:y 0)))
```

## Callback-scoped specialized canvases

```racket
(call-with-nodraw-canvas width height draw-callback)
(call-with-nway-canvas (list surface-a surface-b) draw-callback)
(call-with-overdraw-canvas alpha8-surface draw-callback)
```

Callbacks receive a borrowed `canvas?`, not a resource to close. It expires on
**every** callback exit, including exceptions. Retaining the Racket value cannot
keep it usable or retain the original target wrappers through that expired
lease. Multiple callback return values are preserved. Application drawing runs
outside native FFI allocation/atomic sections.

### NoDraw

NoDraw maintains native canvas geometry, matrix, clip and save state but has no
pixel output. `canvas-execution-backend` reports `nodraw`. It can exercise
ordinary drawing authoring without claiming raster/GPU rendering evidence.
GPU-dependent input is not implicitly downloaded into it.

### NWay

NWay invokes authoring once and forwards native canvas operations to every
attached target. It accepts **1 through 64 distinct owned surfaces**, all with
identical dimensions and the same execution backend. GPU surfaces must also
belong to the same active execution domain. Same physical hardware does not make
two contexts interchangeable.

Every target must begin at its root save count, with an identity transform and
full rectangular clip. The wrapper saves/restores target state and owns an
exclusive borrow for the scope. Drawing through a previously obtained original
canvas, taking a new original canvas/snapshot, or closing a target while borrowed
rejects. This prevents unsynchronized changes behind the native fan-out wrapper.
After normal or exceptional exit, target state is restored and the borrow ends.
Pixels already drawn on a failed callback are **not rolled back**.

This version does not accept arbitrary document/recording canvases, dynamically
mutate the target list during drawing, or fan out across GPU contexts. Target
formats may differ where each native target supports the submitted operation;
that is not a promise of byte-identical results across formats/backends.

### Overdraw

Overdraw requires an **Alpha8** target initialized to zero. Its saturating alpha
channel records native coverage increments. Two overlapping ordinary filled
rectangles produce counts one and two in the corresponding interior regions.

These are the pinned SkOverdrawCanvas approximations, not hardware fragment,
occlusion, shading-cost or performance counters. Antialiasing, glyph treatment,
filters and optimized native primitives can differ from visible coverage.

The safe entry point accepts direct primitives and state operations. It rejects
text, pictures/drawables and layers: pinned m119's overdraw glyph path does not
support every transformed text run, and recorded content could conceal such a
run. This restriction prevents unsupported native paths rather than silently
claiming universal overdraw coverage. Alpha8 GPU support is queried on the actual
context; an absent capability is reported explicitly, never substituted with a
CPU target.

## PDF/SVG policy and retained provenance

Ordinary captured drawable geometry can be exported natively as vector content.
A drawable's dependencies are still audited individually: wrapping a filtered,
float, GPU-affine or unknown picture does not make it portable vector content.

Backdrop, previous-content initialization, LCD layer preservation and F16
requirements remain visible in recordings, native drawables and picture
snapshots. Strict document export rejects these unsupported direct routes.
An explicit bounded raster group must contain the required background and all
content that depends on it. GPU output still crosses the existing explicit
transfer boundary; downloading does not erase float precision provenance.

NoDraw/NWay/Overdraw are not PDF/SVG output targets. Their scopes cannot borrow
another operation's exact-target bounded-raster authority. To export a diagnostic
result, complete its scope, explicitly snapshot/convert the real target, and
embed that detached image with the corresponding audit classification.

## Validation

From the applied checkout:

```bash
source "$HOME/.venvs/skia-for-racket/bin/activate"
python -m pip install -r tools/dc-output-requirements.txt
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

python tools/validate-advanced-canvases.py \
  --racket "$RACKET" \
  --require-gpu \
  --backend metal \
  --require-renderers
```

Linux uses `--backend egl`; Windows uses `--backend direct3d --adapter warp`
for the software D3D12 lane. The independent renderer flag requires **both**
`pdftoppm` and `rsvg-convert`. Missing required tools/backends fail explicitly.
Without `--require-gpu`, the report says GPU execution is false; an explicit
backend without that flag is rejected rather than ignored.

The stage registers **28 pure and 33 native** RackUnit cases in the complete
regression runner, and **11 selected-GPU** cases. The latter require six known-
pixel captures, successful F16-layer execution on an F16 GPU target with no hidden
drawing readback, cross-context exclusions, NWay authoring-once and state cleanup.
The binding/source checks establish that flag `16` is passed as m119
`kF16ColorType`; final-composite pixels are not used to infer the intermediate
layer's exact precision or extended-range behavior. Alpha8 overdraw either executes
with checked count pixels or is disclosed as not executed only when the native
format capability is zero.

Four documents (native-vector drawable and explicitly materialized layer, each
as PDF and SVG) retain a vector green marker and a URL annotation. The inspector
checks page sizes, native object/XML structure, embedded image dimensions,
vector/raster audit classifications and independently rendered pixel regions.
The GPU lane's document image comes from bytes retained after the GPU driver
process has closed its contexts. Synthetic Python parser tests are deliberately
separate from this actual native rendering evidence.

The new workflow is a reusable `Acceptance` child. Normal pushes continue to
create three top-level runs: **CI**, **API inventory**, **Acceptance**. Existing
backend coverage and previous-stage validators remain enabled.

## Pinned implementation references

All native source references use Skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:

- [C layer record/flags](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_types.h),
  [canvas declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_canvas.h)
  and [C implementation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_canvas.cpp).
- [Drawable C API](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_drawable.h)
  and [picture/recorder factories](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_picture.h).
- [NWay raw target borrowing](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/utils/SkNWayCanvas.cpp)
  and [Overdraw implementation/restrictions](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/core/SkOverdrawCanvas.cpp).
