# `skia-dc%` — raster drawing-context foundation (0.53)

`skia/dc` is an opt-in implementation of Racket's public `dc<%>` interface,
rendering directly to an owned, persistent **CPU Skia surface**. It does not
subclass `bitmap-dc%`, delegate drawing to Cairo, open a window, or construct a
GPU context. The ordinary `skia` module does not re-export this class.

**This is the 0.53 foundation, not a complete drop-in `racket/draw` replacement.**
Text, text metrics, bitmap input, arbitrary clipping regions, and several pen /
brush modes are explicit unsupported operations. They do not silently fall back
to another renderer and do not return invented measurements.

## Construction and ownership

```racket
#lang racket/base
(require racket/class
         (only-in racket/draw make-pen)
         skia/dc
         (prefix-in sk: skia))

(define dc
  (new skia-dc%
       [width 640]
       [height 400]
       [backing-scale 2.0]
       [background "white"]
       [smoothing 'smoothed]))

(define image
  (dynamic-wind
    void
    (lambda ()
      (send dc clear)
      (send dc set-pen (make-pen #:color "navy" #:width 3))
      (send dc set-brush "lightblue" 'solid)
      (send dc draw-rounded-rectangle 25 25 300 160 18)
      (send dc snapshot))
    (lambda () (send dc close))))

;; A snapshot is independently retained: encoding after DC close is valid.
(sk:with-skia ([im image])
  (call-with-output-file "dc-example.png"
    (lambda (out) (write-bytes (sk:image->png-bytes im) out))
    #:mode 'binary #:exists 'replace))
```

Logical `width` and `height` are positive exact integers (defaults 640 and 480).
The backing scale is positive and finite (default 1.0). Physical dimensions are
`ceiling(width * backing-scale)` and `ceiling(height * backing-scale)` and must
fit Skia's positive integer dimensions and existing allocation limits.

The constructor allocates Skia storage. Merely requiring `skia/dc` does not
resolve libSkiaSharp or initialize a GUI. It does load `racket/draw` to use its
public interface and color/pen/brush/font/path/region classes; this is not a
claim that `racket/draw` itself is free of native library dependencies.

Pixels initially have transparent black contents. The `background` argument is
the color used by `clear`, not an implicit initial clear. The DC is owned by its
creating Racket thread; using it from another thread or a future is rejected.
Explicit `close` is recommended. It releases the owned surface once, is
idempotent, and does not close previously obtained snapshots. No raw surface,
canvas, native pointer or mutable backing bitmap is exposed.

`skia-dc?` recognizes instances of the public class, including closed instances.
`ok?` reports whether it is open and usable by the current execution owner.
Other operations after close raise an error. This class has its own `close`
method; it is not itself a `skia-resource?` for `skia-close!`.

## Size and output extensions

| Method | Result |
|---|---|
| `get-size` | Two logical dimensions |
| `get-pixel-size` | Two exact physical pixel dimensions |
| `get-backing-scale` | Construction backing scale |
| `get-device-scale` | `1.0`, `1.0`; distinct from backing scale and user scale |
| `snapshot` | Independent ordinary CPU Skia `image?` |
| `get-rgba-bytes #:premultiplied? [#f]` | Copied physical RGBA pixels, row-major, four bytes per pixel |
| `get-png-bytes` | Encoded physical raster PNG |
| `get-capabilities` | Source-only support description for this stage |
| `close` | Release the DC's owned target, once |

The free function `(skia-dc-capabilities)` returns the same immutable declaration
without constructing a DC. It explicitly reports `native_probe_performed #f`
and `full_drop_in_compatibility #f`. Neither the capability query nor class
membership proves rendering fidelity or runtime availability.

## State and ordinary drawing

Implemented drawing methods are `draw-line`, `draw-lines`, `draw-point`,
`draw-polygon`, `draw-path`, `draw-rectangle`, `draw-rounded-rectangle`,
`draw-ellipse`, `draw-arc`, and `draw-spline`. Paths use `dc-path%` and its public
`get-datum` operation; there is no private Racket/Cairo path extraction.

Polygon/path offsets and the `odd-even` / `winding` fill-rule argument are
supported. Open paths remain open for stroking; Skia applies its fill closure
semantics. Arcs use Racket's counter-clockwise angles and separate filled
sectors from curved outline strokes. Equal start/end angles represent a full
ellipse. Rounded rectangles retain the public `dc-path%` radius convention.

Lines and splines never fill with the current brush. Filled shapes draw brush
then pen. Transparent tools suppress their respective pass. The initial pen is
black, solid, width 1, round cap/join; the initial brush is white and solid.

Supported pens are `solid`, `transparent`, `dot`, `long-dash`, `short-dash`, and
`dot-dash`, with round/butt/projecting caps and round/bevel/miter joins. Width
zero follows the foundation's device-aligned hairline rule. Supported brushes
are `solid` and `transparent`. Invalid or deferred selections fail before
replacing the prior tool. Colors accept ordinary `color%` objects and Racket
color names. Channel alpha and DC `set-alpha` multiply.

### Tool selection is intentionally a snapshot contract

`set-pen` and `set-brush` install **immutable copies**, returned by the matching
getters. They do not retain/lock the caller's mutable object and do not promise
`eq?` identity with it. Changing the original object later does not change the
DC. Colors returned by getters are detached public `color%` objects. This is an
explicit difference from the built-in DC's installed-object locking semantics;
full selection/identity compatibility remains 0.55 work.

Fonts and text foreground/background/mode are stored through their usual state
methods, but no font is shaped or measured in 0.53. `cache-font-metrics-key`
returns 0. `get-gl-context` returns `#f`.

## Transformations and smoothing

Six-element matrices use Racket's order:

```text
#(xx yx xy yy x0 y0)
x' = xx*x + xy*y + x0
y' = yx*x + yy*y + y0
```

The logical effective transform is:

```text
initial-matrix * translation(origin) * scale * rotation(-radians)
```

`set-origin`, `set-scale`, `set-rotation`, and `set-initial-matrix` preserve the
other components. `transform`, `translate`, `scale`, and `rotate` concatenate
and collapse them into the initial matrix, resetting separate components.
`get-transformation` is an immutable defensive snapshot and can be restored
with `set-transformation`. The backing scale is applied separately, last on
the destination. Numeric state uses finite doubles; drawing crosses Skia's
binary32 boundary. This is not arbitrary-precision geometry.

`smoothed` accepts general affine transforms, including rotation, shear and
reflection. Singular transforms are accepted, with empty shape drawing.
`clear` / `erase` still operate independently of that user transform.

`unsmoothed` (the default) and `aligned` implement snapping for **positive
axis-aligned** transforms. `aligned` enables antialiasing after snapping;
`unsmoothed` does not. `set-alignment-scale` changes the snapping grid, not the
logical transform. Rectangular/elliptical outlines account for the aligned
one-unit boundary convention separately from the full-area fill.

Aligned rotation, shear and reflection raise an explicit unsupported exception;
select `smoothed` to draw those now. Broader Cairo alignment equivalence,
edge coverage and unusual hairlines remain 0.55 work. The larger example is a
review aid, not a guarantee of byte-identical Cairo/Skia pixels.

## Clipping, clearing and erasing

`set-clipping-rect` captures the rectangle under the current logical transform.
Later transform changes do not move that stored clip. A new rectangle replaces
the prior clip; a zero-area rectangle clips everything. `set-clipping-region #f`
removes clipping.

`get-clipping-region` returns a real `region%` subclass representing an immutable
snapshot in logical device coordinates. It is not bound to a Racket DC; its
`get-dc` is `#f`. The snapshot can be saved and restored **on the same Skia DC**.
Documented region mutation methods raise instead of silently changing geometry
that the DC would ignore. Arbitrary regions and another DC's snapshot are
rejected pending 0.54. This restricted ticket is not general `region%` interop.

`clear` paints the background with source-over composition and current DC alpha.
`erase` clears pixels to transparency, independently of DC alpha. Both ignore
the current drawing transform but respect the installed clipping region.

## Explicit unsupported operations

The exception `exn:fail:skia-dc:unsupported` extends `exn:fail:contract` and carries
`method`, `feature`, and planned `stage` fields. These are not availability
errors and must not be treated as a successful draw.

| Deferred area | Operations |
|---|---|
| 0.54 text | `draw-text`, `get-text-extent`, character metrics, `glyph-exists?` |
| 0.54 bitmap/regions | `draw-bitmap`, `draw-bitmap-section`, `copy`, arbitrary clipping regions |
| 0.55 style/compatibility | Gradients, stipples, hatches, XOR/hilite styles, alpha groups, path ink bounds, complete alignment / object-lock semantics, direct `record-dc%` replay |
| 0.56–0.57 GUI | `skia-canvas%`, persistent GUI management, GPU-frame facade |

`start-alpha` raises; `end-alpha` with no active group is a no-op. The final class
explicitly overrides alpha methods to avoid inheriting newer Racket interface
default no-ops. Document lifecycle and flush methods are checked raster no-ops;
they do not produce a PDF or synchronize a window.

## Validation and next steps

`python3 tools/validate-dc.py --racket "$RACKET"` compiles and runs 60 pure
production-class tests and 31 native tests, creates retained snapshots, and
checks an independently specified 48×40 pixel oracle exactly. It also retains
460×320 Skia and Racket example images for manual review. Four native tests
compare constrained geometry / alpha cases against `bitmap-dc%`, and a minimal
public-method drawing procedure is replayed. Direct `record-dc%` replay is deferred
to 0.55: current `racket/draw` recordings send private local-member methods such
as `do-set-pen!` and `do-set-brush!`, and 0.53 deliberately does not depend on
`racket/draw/private/*`. None of this is broad `pict` or text compatibility.

All existing native CPU CI lanes run the new suites and the separate exact-pixel
gate from the isolated installed package. Artifacts are placed under the job's
`dc-foundation` directory. Missing libraries, missing captures, compilation
errors, wrong pixels and reduced test counts are failures, not optional skips.
The Racket 8.7 lane remains required; GPU workflows and pins are unchanged.

0.54 adds text, bitmap input and general region support. The remaining accepted
roadmap is unchanged: 0.55 real consumers, 0.56 `skia-canvas%`, 0.57 GPU facade.

## Reference contracts used

- Racket `dc<%>`: <https://docs.racket-lang.org/draw/dc___.html>
- Racket `dc-path%`: <https://docs.racket-lang.org/draw/dc-path_.html>
- Racket interface defaults: <https://docs.racket-lang.org/reference/createinterface.html>
- Racket draw source inspected at `b7338af16c11183dffffd113e6bc9376d20bbdd1`.
- Skia wrapper baseline: `bff9c172b84ecb353a5134ce42abd8d49256815a`.
