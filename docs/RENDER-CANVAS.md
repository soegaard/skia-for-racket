# 0.61 — Unified callback-oriented render canvases

`skia/render-canvas` provides a single construction function and protocol for
raster and GPU GUI drawing. It does not rename or replace `skia-canvas%`,
`skia-gpu-canvas%`, or either existing drawing-context contract.

## Construction

```racket
#lang racket/gui
(require skia/render-canvas)

(define (paint canvas dc)
  (send dc set-background "white")
  (send dc clear)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush "royalblue" 'solid)
  (send dc draw-ellipse 20 20 100 60))

(queue-callback
 (lambda ()
   (define frame (new skia-render-window%
                      [label "One callback, either renderer"]
                      [renderer 'auto]
                      [paint-callback paint]))
   (send frame show #t)))
```

For an application-owned parent:

```racket
(make-skia-render-canvas parent
  #:renderer 'auto                 ; 'auto, 'raster, 'gpu
  #:backend 'auto                  ; 'auto, 'opengl, 'metal, 'direct3d
  #:adapter #f                     ; #f, 'hardware, 'warp; Direct3D only
  #:adapter-index #f               ; Direct3D hardware index, default 0
  #:sync-interval #f               ; Direct3D 0..4, default 1
  #:paint-callback (lambda (canvas dc) ...)
  #:on-error raise
  #:background "white"
  #:smoothing 'smoothed
  #:min-width 1 #:min-height 1)
```

The result is an actual `canvas%` implementing `skia-render-canvas<%>`, not a
panel containing an inaccessible canvas. `skia-render-canvas?` recognizes this
protocol. Focus, parentage, widget layout, and GUI events remain those of the
underlying canvas. Construction and rendering operations belong to the owning
eventspace's handler thread; use `queue-callback` from other threads.

A **factory** selects the concrete superclass before constructing the widget.
There is deliberately no new `skia-render-canvas%` with a misleading fixed
superclass, and no `[renderer ...]` argument added to the persistent
`skia-canvas%`. The existing specialized classes remain available for subclassing
and for their backend-specific init arguments and methods. This is not a claim
that all inherited raster/GPU canvas methods have identical semantics.

Requiring this explicit GUI module initializes `racket/gui`. It does not force
either implementation class: the factory loads only the selected implementation.
Neither `main.rkt` nor the ordinary headless drawing modules import it. The
private selection and callback-state modules are GUI/native independent.

## Selection, not silent fallback

`'raster` always selects the existing CPU raster canvas. Supplying a GPU backend
or Direct3D options together with raster is an error, not an ignored hint.

`'gpu` with `#:backend 'auto` chooses Metal on macOS, Direct3D on Windows x64,
and desktop OpenGL on Unix. Explicit backend selection is checked against the
host platform. WARP must be explicitly requested; hardware failure never silently
selects WARP. A nonzero hardware-adapter index cannot be combined with WARP.

`'auto` uses the same native GPU preference on those platforms. On a platform
without a declared native preference it chooses raster. This is a **declarative
platform rule, not a driver probe**. GPU initialization, allocation, context loss,
or rendering failure does not switch the object to a CPU renderer, recreate it,
or replay an application callback. A selected but unavailable backend fails.

The selection is fixed for the widget's lifetime. Create another canvas to
change renderers. `get-renderer`, `get-backend`, and `get-render-info` expose the
requested and selected choices; before first rendering, they do not certify
that a native driver has been initialized or is available.

GPU initialization may be deferred until a shown canvas requests its first
frame. Synchronous `refresh-now` errors propagate to its caller; scheduled GPU
errors reach `#:on-error`. Scheduled raster paint errors also reach this handler.
The default error callback is `raise`. Application errors are never treated as
backend-unavailability evidence or as permission to retry the callback on raster.

## Common protocol

| Method | Contract |
| --- | --- |
| `get-renderer` | Selected `'raster` or `'gpu`; queryable after closure. |
| `get-backend` | Selected `'raster`, `'opengl`, `'metal`, or `'direct3d`. |
| `get-render-capabilities` | Immutable lifetime, storage-path, and raster-only capability disclosure. |
| `get-render-info` | Immutable outer record with selection, capabilities, callback counts, last callback size, close state, and implementation diagnostics. |
| `get-dc` | The exact DC supplied to the active paint callback. Rejects outside callbacks on both renderers. |
| `refresh` | Request/coalesce another frame using the existing scheduler. Safe from a paint callback; a no-op after closure. |
| `refresh-now [proc #f] #:flush? [#t]` | Synchronous frame. Optional one-argument callback applies only to that invocation. Only `#:flush? #t` is portable. Hidden/zero-sized GPU windows can defer a frame, as in the existing presenter. |
| `set-paint-callback proc` | Replace the ordinary two-argument callback while idle. Does not implicitly draw or request a frame. |
| `get-raster-dc` | Explicitly acquire the persistent raster DC. Rejects for GPU without readback or fallback. |
| `present` | Raster-only presentation of cached pixels. GPU callers must request a frame instead. |
| `close`, `close-skia` | Close through the existing implementation. Reject inside a paint callback on both renderers. Cleanup is retryable if the backend reports retained resources. |
| `closed?` | The underlying widget's closed state; a failed GPU cleanup may already have disabled future drawing. |

Callbacks may return zero, one, or multiple values; their values are ignored.
Callback arguments must accept the documented positional arity without mandatory
keyword arguments. Nested `refresh-now`, callback replacement, `present`, and
close are rejected during a callback. Schedule close later rather than destroying
a widget while its DC is borrowed. Exceptions, non-exception raised values, and
continuation escapes remove the common active-DC access scope. Continuations
captured inside a callback cannot reenter a retired callback across its barrier.

The `callbacks_completed` counter means only that a callback returned normally.
It is not a presented-frame count, and neither callback counts nor a successful
submission certify physical display pixels.

### The real DC lifetime remains visible

| Property | Raster | GPU |
| --- | --- | --- |
| Underlying DC | Persistent `skia-dc%` | Fresh frame-scoped GPU DC |
| `get-dc` outside a callback | Reject | Reject |
| Explicit persistent access | `get-raster-dc` | Unsupported |
| A saved callback DC after return | Still a live raster DC, not artificially expired | Expired and never revived |
| Drawing state between callbacks | Retained | Fresh |
| Normal presentation | CPU pixel/bitmap bridge | Existing GPU-only staging/snapshot/presentation path |

Portable application callbacks must not retain their DC or depend on state or
pixels left by an earlier callback. Initialize any transformation, clip, alpha,
font, pen, brush, and colors that the drawing needs. This layer **does not reset
or secretly recreate the raster DC to imitate GPU lifetime**. Applications that
intentionally keep raster state should use `get-raster-dc` and check
`'persistent_dc` in the capability record, or keep using `skia/canvas`.

The raster DC remains owned by its canvas: do not close it separately. Close
the widget. The same rule applies to both DCs received in callbacks.

### Toolkit dispatch boundary

Racket's `canvas%` implementation obtains its virtual `get-dc` before calling a
`refresh-now` paint procedure. The raster adapter permits that single internal
handoff, consumes the permission immediately, and clears it on all exits.
Application access still requires an active callback or explicit raster access.
This does not change `canvas.rkt` or the toolkit's buffering implementation.

## Window helper

`skia-render-window%` extends `frame%`. Its init arguments are `label`, `width`,
`height`, `renderer`, `backend`, `adapter`, `adapter-index`, `sync-interval`,
`paint-callback`, `on-error`, `background`, and `smoothing`, with the same defaults
as the factory (640 by 480 for window size). `get-render-canvas` returns the
factory-created canvas. `close-render` closes it and hides the frame, and is also
used by `on-close`. A rejected close during painting does not hide the window.

## Validation

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Pure, headless, no native renderer:
"$RACKET" tests/render-canvas-pure-test.rkt

# Required raster GUI plus its 0.58 prerequisites:
python3 tools/validate-render-canvas.py --racket "$RACKET" --require-gui

# Full gate: old raster, complete 0.60 native/GUI, and all three choices:
python3 tools/validate-render-canvas.py --racket "$RACKET" --require-gpu

# Interactive inspection:
"$RACKET" examples/render-canvas.rkt --renderer raster
"$RACKET" examples/render-canvas.rkt --renderer gpu
```

The full validator requires 33 headless policy/state cases and 20 real-window
cases per selected construction mode: raster, GPU, and auto. Each mode retains
24 backing-pixel captures: four existing 0.60 workloads, three direct/replay
modes, and two window sizes. Normal frames and explicit inspection frames have
separate I/O ledgers. GPU inspection supplies a readback positive control; raster
must emit no GPU events. The inspector reuses 0.60's semantic pixel probes and
bounds procedure/datum differences without demanding CPU/GPU byte equality.

Thus the full new GUI gate has **60 case executions and 72 captures**, in
addition to the unchanged selected prerequisites. Every raw capture is inspected,
and each mode has eight bounded procedure/datum comparisons. PNGs and
`review.html` are generated for inspection; these are not screen captures.

The standalone validator defaults to pure/headless checks only. `--require-gui`
selects raster GUI without initializing a GPU. `--require-gpu` implies GUI and
also selects GPU/auto, with native backend options `auto`, `egl`, `metal`, or
`direct3d`. `egl` corresponds to OpenGL for the GUI factory. On macOS automatic
validation uses Metal. For a separate macOS OpenGL facade check, run the GUI
suite directly with `--renderer gpu --backend opengl`; it is not an EGL test.

All output is written to a new `output/render-canvas-0.61-*` directory, or a new
`--directory` path. `validation.json` records which gates actually ran. Missing
executables/backends/displays, partial or duplicate completion output, stale run
identities, incomplete matrices, unsafe capture paths, failed pixels, implicit
readbacks, and source changes fail the gate. No skipped selection is a pass.

The new `Unified render canvas` workflow requires Linux Mesa/Xvfb on Racket
8.18 and 9.3 and Windows D3D12 WARP on Racket 9.3. Windows GUI coverage is a new
selected requirement, not preexisting validation evidence. It retains the old
raster and 0.60 GPU prerequisite gates and compiles interactive examples.
Existing `CI` and `GPU DC` workflows and the `CI required` aggregation are
preserved. Requiring the additional workflow in branch protection remains a
repository settings decision; this patch does not change those settings.

## Scope and next stage

No new native symbols, GPU backend, implicit transfers, persistent GPU DC,
runtime fallback, raster state reset, or optimization is introduced. The GPU
path still uses 0.59's staging allocation and GPU snapshot/copy. Direct target
rendering or safe pooling belongs to 0.62. Shared PDF/SVG authoring remains the
subsequent vector-output stage, not an undocumented behavior of this GUI factory.
