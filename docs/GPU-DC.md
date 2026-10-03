# GPU drawing contexts and GUI facade — 0.59

This stage supplies the existing Skia `dc<%>` drawing subset on Ganesh GPU
surfaces. It reuses the ordinary DC state, path, text, bitmap, style, recording,
region and alpha implementations. It does **not** replace `skia/dc`, the
persistent raster `skia/canvas`, or the raw `skia/gpu-gui` interface.

The native pins and minimum remain SkiaSharp 3.119.1, HarfBuzzSharp 8.3.1.2,
Racket 8.18 and draw-lib 1.22. No new native symbol or ABI layout is introduced.

## Lifetime is the central difference

A GPU DC is valid **only during its callback on the owning Racket thread**.
Every call creates a fresh DC. It is closed on success, exceptions (including
non-exception raised values), escapes and presentation failure. A retained
reference is never reactivated by a later frame. `ok?` is false after expiry;
drawing, state, measurement and output methods reject it. `close` is idempotent
on the owner thread after expiry, but cannot close the DC inside its callback.
Selected pen, brush and region locks are released at the scope boundary.

Nested DC scopes and synchronous nested rendering are rejected. Use `refresh`
to request a later frame. Do not save a DC, its associated region as a reusable
new-frame object, a continuation into the callback, or an implicit GPU target.
Keep application drawing state separately and select it anew each frame.

The existing 0.57 compatibility limits still apply; see [SKIA-DC.md](SKIA-DC.md)
and [DC-STYLES.md](DC-STYLES.md). These classes are not universal drop-in
replacements for every `canvas%`, `bitmap-dc%` or consumer of an exposed native
Cairo handle. `skia-gpu-dc?` is the appropriate predicate; a GPU DC is not an
instance of the separately constructed persistent `skia-dc%` class.

## Headless entry point

`skia/gpu-dc` exports:

```racket
(call-with-gpu-frame-dc frame proc
                       #:background [background "white"]
                       #:smoothing [smoothing 'smoothed])
(call-with-gpu-surface-dc surface proc
                         #:logical-width [logical-width #f]
                         #:logical-height [logical-height #f]
                         #:background [background "white"]
                         #:smoothing [smoothing 'smoothed]
                         #:clear? [clear? #f])
(skia-gpu-dc? value)
(skia-gpu-dc-capabilities)
```

Both callbacks receive one `dc<%>` object, and their return values are preserved.
Background and smoothing have the ordinary DC constructor semantics: a color
name or `color%`, and `'smoothed`, `'aligned` or `'unsmoothed` respectively.
The capabilities hash contains declarations, not a successful native probe.
Importing this module does not instantiate the GUI or create a GPU context.
Native GPU drawing code is loaded on first use.

### Existing presenter frame

Call `call-with-gpu-frame-dc` inside an existing presenter's render callback.
The frame must be live on its owner thread. Its context is already activated by
the presenter; **do not wrap the callback in another `call-with-gpu-context`**.

```racket
(lambda (frame)
  (call-with-gpu-frame-dc frame
    (lambda (dc)
      (send dc set-pen "black" 1 'transparent)
      (send dc set-brush "navy" 'solid)
      (send dc draw-rectangle 20 20 160 80))))
```

Each frame allocates an RGBA8 offscreen GPU surface in the frame's context,
clears it to the chosen background, draws through the DC, discards unfinished
alpha groups and copies a GPU snapshot onto the frame canvas with `Src`.
The presenter owns the actual flush/submission/presentation. A failed callback
does not copy the root to the frame, and the presenter cancels that frame.
Closing the widget during a callback requests cancellation; native retirement
waits for the callback and DC cleanup to unwind.

The final copy uses physical coordinates with an identity transform. A native
clip already installed on the borrowed frame canvas still limits that copy;
use the ordinary unmodified frame canvas for a full-window DC frame. The
frame's saved matrix/clip state is preserved by the final copy.

This is an extra **GPU-side allocation and GPU-to-GPU draw**, not zero-copy
presentation. There is no per-frame PNG conversion, automatic CPU bitmap
bridge, hidden CPU root rendering, or performance guarantee. CPU source images
and public `bitmap%` inputs may still need upload by Skia; this is distinct
from rendering the whole frame on the CPU. Software Mesa/WARP remains a GPU
API backend and is not evidence of execution on physical graphics hardware.

### Borrow an existing offscreen GPU surface

Call `call-with-gpu-surface-dc` **inside the surface's active owning context**.
The root is borrowed: the DC never closes it. Its logical dimensions default
to its physical dimensions. With `#:clear? #f`, existing root pixels remain;
`#:clear? #t` clears before the callback. This provides persistence of the
surface's pixels, not persistence of the DC object or drawing state.

```racket
(call-with-gpu-context context
  (lambda ()
    (with-skia ([surface (make-gpu-surface context 640 400)])
      (call-with-gpu-surface-dc surface
        (lambda (dc)
          (send dc set-pen "black" 1 'transparent)
          (send dc set-brush "blue" 'solid)
          (send dc draw-ellipse 12 12 100 70))
        #:logical-width 320 #:logical-height 200))))
```

The native save stack must be balanced. Use an unmodified native root clip;
an existing native clip is an additional constraint which DC region queries
do not describe and `set-clipping-region #f` cannot remove. Raw surface drawing
must not run concurrently with the scope. The native transform is reset for
individual DC draws and restored afterward. User exceptions can leave root
pixels already drawn; borrowed-surface drawing is not transactional. Failed
or unfinished alpha children are discarded without merging into the root.
CPU surfaces, expired surfaces and access outside the owning activation fail.

## Geometry and HiDPI

`get-size` returns the authoritative logical width and height. `get-pixel-size`
returns the actual physical extents. GPU frames can have independently rounded
X and Y extents, so a single guessed Retina factor is not used:

```
scale-x = physical-width / logical-width
scale-y = physical-height / logical-height
```

`get-device-scale` returns those two values; `get-backing-scale` is **1.0**.
Logical DC transforms, text metrics, recorded commands and region state do not
have device scale pre-applied. The renderer maps drawing matrices and clip
paths exactly once. Alpha children are allocated at the physical size; their
pixels are not scaled again at merge. This convention is deliberately different
from the raster DC's scalar `get-backing-scale` convention.

For a CPU-transfer pixel oracle, convert an interior logical sample using the
corresponding X/Y device scales, then use physical row stride. Do not read raw
pixel `(3,4)` to assert the color of logical point `(3,4)` on a Retina frame.

## Alpha, copy and explicit exports

`start-alpha` allocates an isolated same-context GPU surface. `end-alpha` merges
its GPU snapshot, with the parent's clip and group opacity, then releases it.
Unfinished groups at callback exit are discarded. The existing byte-budget
checks apply to checked root and alpha allocations, but are not a bound on all
memory held by a graphics driver.

Overlap-safe `copy` also uses a same-context GPU snapshot. Neither alpha merge
nor copy uses the public CPU-transfer methods. Public `snapshot`,
`get-rgba-bytes` and `get-png-bytes` are explicit synchronous transfers of the
**root**, not an unfinished child. `snapshot` returns an independent CPU Skia
image which the caller closes with `skia-close!`; it remains usable after the
DC and GPU context close. The PNG operation encodes such a detached CPU image.
These explicit transfers can stall GPU execution and are not part of normal
presentation. The DC's `flush` remains a checked no-op: the presenter controls
frame submission, or an offscreen caller uses the existing GPU submission API.

## GUI entry point

Import `skia/gpu-canvas` explicitly. It exports `skia-gpu-canvas%`,
`skia-gpu-canvas?` and the convenience `skia-gpu-window%`.

```racket
(new skia-gpu-canvas%
     [parent panel]
     [backend 'auto]
     [paint-callback (lambda (canvas dc) ...)]
     [on-error raise]
     [background "white"]
     [smoothing 'smoothed]
     [automatic? #t]
     [min-width 1] [min-height 1])
```

The backend options are inherited from the raw GPU widget: `'auto` selects
Metal on macOS and OpenGL elsewhere; `'opengl`, `'metal` and `'direct3d` are
explicit choices. Direct3D-only `[adapter ...]`, `[adapter-index ...]` and
`[sync-interval ...]` are passed through unchanged. Backend unavailability is
an error, not a reason to switch to a CPU canvas.

Construct, manipulate and close the widget on its eventspace handler thread.
The paint callback receives `(canvas dc)` and `get-dc` returns that same DC
**only during that callback**. `refresh` coalesces a request for a later frame;
`refresh-now [one-argument-proc]` paints synchronously and expires the DC before
returning. `#:flush? #f` is unsupported because the facade has no persistent
unpresented frame. `present` is explicitly unsupported; use refresh instead.
Inherited `request-gpu-render`/`render-gpu-now` also remain available. `automatic?`
controls exposure/geometry scheduling as in the raw widget, not explicit calls.

`close-skia`, `close` and `close-gpu` release the widget; hiding it does not.
`skia-closed?` and `get-skia-info` provide detached lifecycle information.
The convenience window exposes `get-skia-canvas`, `get-gpu-presenter` and
`close-skia`; its close event also closes the GPU canvas. This is not the full
raster-canvas constructor: scrolling, style lists and persistent-DC access are
not added here. Directly replacing the inherited presenter's render callback
bypasses this facade and is an advanced raw-presenter operation.

The GL host lookup now explicitly calls the toolkit superclass `get-dc`, not
the facade's frame-only override. This fixes initialization ordering without
changing the existing raw GPU widget's public drawing interface.

## Validation

```bash
python3 tools/update-source-sums.py --check
python3 tools/test-validate-gpu-dc.py
python3 tools/validate-gpu-dc.py --racket "$RACKET" --require-gui
"$RACKET" examples/skia-gpu-canvas.rkt
```

The new validator requires 33 instrumented-renderer cases and 15 real GPU
cases. `--require-gui` additionally requires 10 real-window cases; a missing
backend/display is a failure. Offscreen native tests use EGL on Linux, Metal
on macOS, and Direct3D on Windows. Override with `--backend egl|metal|direct3d`;
`--adapter warp` is available for Direct3D. The corresponding Linux GUI tests
use the existing OpenGL window presenter. The validator uses the exact chosen
Racket for every command and writes fresh command logs plus `validation.json`.
No headless result is labelled a GUI pass.

Native tests include fixed interior-pixel checks at 1x, 2x, asymmetric and
fractional logical dimensions; GPU alpha/copy; bitmap/text input; explicit
post-context-close CPU images; and real presenter frame expiration, failure,
cancellation and GPU-to-GPU copy. An I/O ledger checks for absence of wrapper
readback calls during ordinary frame rendering. It does not measure internal
Skia/driver stalls, uploads, allocations, or physical screen pixels.

`.github/workflows/gpu-dc.yml` is an additional workflow with required selected
native/GUI gates on Linux Mesa under Xvfb, for Racket 8.18 and 9.3. It does not
change the existing `CI required` aggregation or repository branch-protection
settings. The usual `run-tests.rkt` includes the new pure suite, not GPU/GUI
initialization. macOS Metal and Windows desktop behavior still need their
native host runs. A successful software-Mesa CI run does not certify those
backends or manual monitor/visibility behavior.
