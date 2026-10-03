# Persistent raster GUI canvas — 0.58

`skia/canvas` provides `skia-canvas%` and `skia-canvas?`. The class extends
Racket's `canvas%`, owns one persistent CPU-raster `skia-dc%`, and presents its
completed pixels through the GUI toolkit. A normal paint callback receives
the widget and that DC. Programs can retain the DC between callbacks.

The minimum remains **Racket 8.18 / draw-lib 1.22**. This module explicitly
initializes the GUI; `skia`, `skia/dc`, and the existing non-GUI modules remain
usable without a display or a loaded Skia library. The canvas requires a
working GUI; drawing or obtaining its DC requires the pinned Skia library.
Native backing creation is lazy until it is needed. Text uses the existing
Skia/HarfBuzz path. The drawing subset and limitations are the
[0.57 DC contract](SKIA-DC.md) and [style contract](DC-STYLES.md).

## Create a canvas on its handler thread

```racket
#lang racket/base
(require racket/class racket/gui/base skia/canvas)

(queue-callback
 (lambda ()
   (define canvas #f)
   (define window%
     (class frame%
       (define/augment (on-close)
         (when canvas (send canvas close-skia))
         (send this show #f))
       (super-new)))
   (define window
     (new window% [label "Skia raster canvas"] [width 640] [height 400]))
   (set! canvas
     (new skia-canvas%
          [parent window]
          [smoothing 'smoothed]
          [paint-callback
           (lambda (canvas dc)
             (send dc set-background "white")
             (send dc clear)
             (send dc set-pen "navy" 3 'solid)
             (send dc set-brush "lightblue" 'solid)
             (send dc draw-rounded-rectangle 30 30 220 120 16))]))
   (send window show #t)))
```

The construction, painting, presentation, resizing and release operations
belong to the parent canvas's eventspace handler thread. Use `queue-callback`
in that eventspace to schedule work from another thread. A retained DC follows
the same owner-thread rule. Merely parameterizing `current-eventspace` on a
worker does not make the worker its handler thread.

## Constructor

`parent` is required. The supported initialization arguments are:

| Argument | Default / contract |
|---|---|
| `paint-callback` | Procedure receiving `(canvas dc)`; default does nothing |
| `background` | `"white"`; sets the DC background used for ordinary repaint clearing |
| `smoothing` | `'unsmoothed`; accepts the DC's supported smoothing modes |
| `style` | Empty list; supported flags are `'border`, `'control-border`, `'no-focus`, `'deleted`, and `'no-autoclear` |
| `label`, `enabled` | `#f`, `#t`; ordinary basic canvas initialization |
| `horiz-margin`, `vert-margin` | `0`, `0`; ordinary canvas layout margins |
| `min-width`, `min-height` | `1`, `1`; ordinary minimum layout size |
| `stretchable-width`, `stretchable-height` | `#t`, `#t`; ordinary layout stretching |

Customize painting through `paint-callback` or the `refresh-now` procedure.
Overriding `on-paint` replaces the wrapper's whole managed paint-and-present
path; a subclass doing so must arrange its own presentation and cleanup and is
outside the callback guarantees documented here.

Unsupported canvas style flags fail explicitly. This stage does not add
scrollbars, an OpenGL canvas mode, a GPU backend selector, raw Skia backing handles,
or universal replacement of every `canvas%` subclass. A `'deleted` or hidden
canvas remains an owned live object; deletion from layout is not release.

## Painting and presentation

| Method | Behavior |
|---|---|
| `(send canvas get-dc)` | Returns the canvas's persistent `skia-dc%`; rejects after close |
| `(send canvas refresh)` | Requests a toolkit repaint; repeated requests can coalesce |
| `(send canvas refresh-now)` | Paints synchronously using the ordinary callback and presents |
| `(send canvas refresh-now paint-proc #:flush? flush?)` | Calls `paint-proc` with the DC instead of the ordinary two-argument callback, then presents |
| `(send canvas on-paint)` | Runs the ordinary paint path: prepare the backing, invoke the callback, and present |
| `(send canvas present)` | Presents the current root backing without running the paint callback |
| `(send canvas close-skia)` | Explicitly releases the canvas's raster resources on its handler thread |
| `(send canvas close)` | Alias for `close-skia` |
| `(send canvas closed?)` | Reports whether explicit closure has occurred |
| `(send canvas get-skia-info)` | Immutable stage, geometry, paint/presentation count and lifetime diagnostics |
| `(send canvas set-canvas-background color)` | Sets both the window underlay and Skia automatic-clear background; requires a `color%` object |
| `(send canvas get-canvas-background)` | Returns a detached copy of the configured canvas background, including its alpha |

Normal paint prepares the current client extent and clears the whole root
backing using the DC background, unless `'no-autoclear` was requested. This
automatic clear is independent of the current clip and transform. The callback
then draws and the completed backing is presented. The canvas preserves the
client's selected pen, brush, font, transform and clip. A callback that relies
on a particular state should set that state explicitly, just as with a retained
DC. Calling the DC's `set-background` affects later automatic clears; use
`set-canvas-background` when the toolkit underlay should change as well. The
window underlay uses the configured RGB with opaque alpha. The configured
alpha is applied to the Skia root once and is retained in snapshots/readbacks;
it is not applied a second time to the display underlay.

`refresh` expresses invalidation. It does not guarantee one callback for every
request. For synchronous painting use `refresh-now`; its optional callback has
one argument, the DC. Its `#:flush?` argument requests the normal toolkit flush
behavior. A submitted bitmap or completed flush is not a certification that
physical display pixels have appeared.

`present` is useful after incremental drawing through the retained DC:

```racket
(define dc (send canvas get-dc))
(send dc set-pen "firebrick" 2 'solid)
(send dc draw-line 20 20 160 80)
(send canvas present)
```

All three operations in this example run on the owning handler thread. The
next exposure or requested repaint invokes the ordinary callback. Keep durable
application content in the model that the callback redraws, or deliberately
manage incremental content with `'no-autoclear` and the resize policy below.

Unfinished alpha groups are discarded at paint entry and exit, including when
the callback raises an exception. They are not silently composited into the
root and cannot leak into a later paint. Direct `present` observes only the root
backing; use balanced `start-alpha` / `end-alpha` for content intended to appear.

Synchronous exceptions propagate after cleanup. Painting is not a transactional
pixel rollback: drawing completed before an exception may already have changed
the root. Nested synchronous paint, direct backing replacement and close are
rejected while painting. Toolkit resize notifications and queued `refresh`
requests schedule later work without recursively entering the active paint.

## Persistent DC, replaceable backing

The object returned by `get-dc` keeps its identity across resize and backing
scale changes. Its selected objects and drawing state remain selected. The
private raster storage is replaced by a new transparent allocation of the
current physical size. Old pixels are **not preserved**. Resize also discards
unfinished alpha groups and restores their outer saved alpha. Normal repaint
clears and redraws the replacement through the same callback.

Client dimensions are logical coordinates. The GUI's compatible bitmap reports
the actual backing scale for the current window, and physical allocation follows
that scale. There is no fixed 1x or 2x assumption, user-supplied monitor guess,
or permanent reference to the scale at construction. A zero client extent
defers painting until the canvas becomes drawable and retains the most recent
backing. Asking for `get-dc` before any positive extent exists creates a minimal
1-by-1 logical backing so the persistent DC is available immediately.

The default automatic clear uses the configured background. With
`'no-autoclear`, a new backing starts transparent and incremental content still
needs reconstruction after resize. The style suppresses paint clearing; it
does not turn raster storage into an unbounded or automatically preserved image.

Independent snapshots obtained through the DC keep their existing lifetime
contract across resize and canvas close. They own their pixels. Retaining a
snapshot is different from retaining the canvas's live drawing target.

## Pixel transfer and renderer boundary

Skia draws the scene into owned CPU raster storage. Presentation reads its
premultiplied RGBA pixels directly, reorders the channels into the toolkit's
premultiplied ARGB byte layout, updates a reusable compatible bitmap, and blits
that bitmap with the toolkit DC. The bitmap and ARGB transfer buffer are reused
until the geometry requires a replacement. Each presentation still allocates
one copied RGBA readback buffer. Normal presentation does not PNG-encode or
decode the scene and does not allocate an independent native snapshot per frame.

The toolkit performs the final bitmap blit. On platforms where its bitmap DC
uses Cairo, this is still presentation of already rendered Skia pixels. Shapes,
styles and text are not redirected to a hidden Cairo scene renderer. This
boundary involves CPU pixel transfer and is not a zero-copy or GPU rendering
claim. Alpha, row orientation and channel ordering have dedicated transfer tests.

## Close explicitly

Arrange for the owner window's `on-close` to call `close-skia`, as in the example.
Hiding or removing a canvas can be temporary and does not imply closure. Closing
releases backing storage and presentation resources and discards unfinished
groups; the retained DC can no longer draw. Repeated close is harmless.

Do not close the DC directly while its canvas still owns it. Release the canvas
through `close-skia` so both rendering and presentation resources retire
together. Closing during an active paint or from another thread is rejected.

## Validation and acceptance

On Linux, GTK/Pango may have already loaded the system HarfBuzz before Skia
text is used. The bundled HarfBuzz now loads locally with `RTLD_DEEPBIND` so its
internal `hb_*` calls stay within that same implementation. This corrects a
native object mismatch that could crash both canvas text and ordinary
`skia-dc%` text after GUI initialization. Other platforms retain ordinary local
loading, and the HarfBuzzSharp pin remains 8.3.1.2. The policy is automatic;
restart an existing Racket or DrRacket process after upgrading to load its
libraries under the new binding policy.

The two headless suites, `tests/canvas-dc-pure-test.rkt` (38 cases) and
`tests/canvas-dc-native-test.rkt` (14 cases), are part of `run-tests.rkt`. The pure
suite does not initialize the GUI or require native libraries. Native checks exercise
the actual Skia/DC backing and bitmap transfer without creating windows.

Run the stage validator with the same selected Racket used for your install:

```bash
python3 tools/validate-skia-canvas.py --racket "$RACKET" \
  --require-gui --output output/skia-canvas-0.58
```

The output directory must be new. Required GUI mode creates actual widgets and
executes the 15-case eventspace/lifecycle suite. Fresh subprocesses also check
both GTK-first and Skia-first library loading, with repeated Skia and ordinary
Racket text rendering and independent ink checks. A missing display, failed
initialization, wrong-thread error or failed GUI case fails the gate; it cannot
be reported as a successful skip. Omitting `--require-gui` performs the headless
stage checks and explicitly records GUI as **not run**.

The required Linux `canvas` CI job runs this GUI gate under Xvfb against a
freshly installed source package and pinned native libraries. Reports and logs
are retained in the job artifact. CPU and EGL jobs still clear display variables;
neither is represented as GUI acceptance. The preexisting 0.57 DC validator,
its exact/semantic pixel oracles, and all GPU gates remain required.

For host review, run `"$RACKET" examples/skia-canvas.rkt` and inspect exposure,
rapid resizing, minimize/restore, independent closure and movement between
displays with different backing scales. Xvfb validates GUI behavior at its
reported scale; it cannot establish physical monitor output or macOS Retina
behavior. Successful headless tests alone do not accept those host properties.

The next stage is **0.59: a GPU-backed canvas/DC facade** using the established
GPU presenters. Its frame-scoped DC lifetime will be explicit. This persistent
raster canvas neither changes `gpu-canvas%` nor disguises a borrowed GPU frame
as a DC that can be retained indefinitely.
