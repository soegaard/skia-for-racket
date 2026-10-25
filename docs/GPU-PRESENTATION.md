# GPU window presentation

**0.49 adds explicit Windows x64 DXGI/D3D12 presentation.** The shared frame
and presenter contract below also applies to `[backend 'direct3d]`. For its
additional `adapter`, `adapter-index`, and `sync-interval` initialization
arguments, buffer-reuse fence waits, occlusion, state transitions and required
WARP tests, see [GPU-DXGI.md](GPU-DXGI.md). The historical no-CPU-wait statements
below describe GL/Metal; D3D12 may wait for a reused buffer's prior fence, but
normal frames perform no CPU pixel readback. All GUI constructors now share
the automatic backend policy described below.

Import `skia/gpu` for presenter/frame operations and `skia/gpu-gui` for the
Racket GUI widgets. Import `skia` for ordinary drawing. The drawing callback
is the same on OpenGL, Metal and Direct3D; it receives a borrowed frame, not a native
framebuffer, closeable surface, drawable, command buffer, or texture pointer.

The GUI module initializes `racket/gui/base` and therefore requires a usable
window system. Requiring `skia` or `skia/gpu` alone still does not initialize a
GUI or Metal/OpenGL. Installing the `gui-lib` dependency does not initialize it.
Offscreen context construction and image-transfer contracts are unchanged.
The GUI-initializing module is excluded from automatic package test traversal;
the explicit presentation validator exercises it on a GUI-capable host.

## First window

```racket
#lang racket/base
(require racket/class racket/gui/base
         (prefix-in sk: skia)
         skia/gpu skia/gpu-gui)

(define (draw frame)
  (define canvas (gpu-frame-canvas frame))
  (define w (gpu-frame-width frame))
  (define h (gpu-frame-height frame))
  (sk:canvas-clear! canvas 'white)
  (sk:with-skia ([paint (sk:make-paint #:color "#177C9C")])
    (sk:draw-circle canvas (/ w 2) (/ h 2) (* 0.3 (min w h)) paint)))

;; Contexts, targets and callbacks belong to this eventspace's handler thread.
(queue-callback
 (lambda ()
   (define window
     (new gpu-window% [label "Skia"] [width 640] [height 480]
          [backend 'auto] [render draw]))
   (send window show #t)))
```

`'auto` chooses Metal on macOS, Direct3D on Windows x64, and OpenGL on Unix,
using the same policy as the other GUI constructors. It is a selection policy,
not a fallback policy: failed Metal construction does not silently become
OpenGL or CPU drawing. An explicit backend is `'opengl`, `'metal`, or `'direct3d`.
Metal window presentation requires 64-bit macOS. The selected backend stays
fixed for the lifetime of the widget. To compare backends, create two widgets
using the same callback. GPU resources remain bound to their own contexts;
reusing an OpenGL image in a Metal callback is not permitted.

Native rendering and presentation on any particular platform are established
by host validation, not by the existence of the bindings. The authoring
package itself does not establish a new native or visible-window pass.

## Widgets

### `gpu-canvas%`

A subclass of `canvas%` that can be embedded in an ordinary Racket parent.

```racket
(new gpu-canvas%
     [parent parent]
     [style '(border)]
     [backend 'auto]
     [render void]
     [on-error raise]
     [background 'white]
     [automatic? #t]
     [min-width 1]
     [min-height 1])
```

`render` and `on-error` accept one argument. The renderer receives a
`gpu-frame?`; its result is ignored. The error handler receives the raised
value from a queued redraw. Immediate rendering raises directly. The default
error handler re-raises instead of silently accepting an unavailable backend.
The background is cleared before every drawing callback. No implicit image
readback or CPU-rendered image panel is inserted.

`style` accepts `border`, `control-border`, `no-focus`, and `deleted`.
Backend-specific flags are supplied internally. GPU canvases reject
`no-autoclear`: their frame pixels do not persist between callbacks.
Adapter indices range from 0 through 4294967294; WARP requires index 0.
The Direct3D synchronization interval is 0 or 1. Other explicit intervals
are rejected before a native widget or convenience window is created.

Create and use widgets on the creating eventspace's handler thread. A worker
must enqueue GUI work using `queue-callback` with the appropriate
`current-eventspace`; it must not call presenter/render methods directly.
First native initialization is lazy, normally after the widget is shown. Do
not initialize another widget while a GPU/presentation callback is active.

The widget's public methods are:

| Method | Contract |
|---|---|
| `(send canvas get-gpu-presenter)` | Initializes and returns the owned presenter on the handler thread. Fails after widget closure. Explicit invocation can retry an initial availability failure. |
| `(send canvas get-gpu-backend)` | Returns the selected backend symbol. |
| `(send canvas request-gpu-render)` | Coalesces a queued redraw; a closed widget ignores it. An initialization failure is not retried continuously. |
| `(send canvas render-gpu-now)` | Calls `gpu-presenter-render!`; not legal inside another active GPU scope. |
| `(send canvas close)` | Stops automatic scheduling and requests safe closure. Retry after retiring application GPU resources if they prevented context closure. |
| `(send canvas closed?)` | True only after rendering-resource cleanup succeeds. |
| `(send canvas get-close-state)` | `'open`, `'closing`, `'close-failed`, or `'closed`; includes deferred cleanup outcomes. |
| `(send canvas check-gpu-geometry)` | Checks geometry/visibility and requests redraw when needed. Normally called by the automatic monitor. |

With `automatic? #t`, exposure, resize, ancestor show/activation and a weak
150 ms geometry/visibility monitor request coalesced redraws. The monitor
also catches backing-scale changes when moving between displays, and retries
an unavailable drawable at a bounded rate. It is not an animation clock or
a frame-rate guarantee. With `automatic? #f`, explicit render/request calls
control drawing; this is useful for diagnostics. The engine still honors a
queued request made by a callback or a resize it observes during that callback.

`show #f` or minimizing suspends acquisition; neither closes the presenter.
A zero pixel/logical extent is also skipped. Restoration invalidates the
previous target geometry and a later acquired frame has a new generation.

### `gpu-window%`

A convenience `frame%` containing one `gpu-canvas%`:

```racket
(new gpu-window% [label "Skia GPU"] [width 640] [height 480]
     [canvas-style '(border)]
     [backend 'auto] [render void] [on-error raise]
     [background 'white] [automatic? #t])
```

It supplies `get-gpu-canvas`, `get-gpu-presenter`, `request-gpu-render`,
`close`, `closed?`, and `get-close-state`. The close-state queries describe
the contained canvas. Ordinary `show`, `resize`, `move`, and `iconize` remain GUI methods.
Closing from the window manager requests GPU closure and hides the frame.
`close` hides the frame even when application-owned GPU resources block
final context destruction; retain the presenter or window to retry cleanup.
Closing one window does not close another window's context.

## Presenter operations

`gpu-presenter?` recognizes the value. There is deliberately no public raw
adapter constructor in this release. Presenters come from the GUI widgets.

```racket
(gpu-presenter-backend presenter)
(gpu-presenter-context presenter)
(gpu-presenter-state presenter)
(gpu-presenter-info presenter)
(gpu-presenter-render! presenter)
(gpu-presenter-request-render! presenter)
(gpu-presenter-set-render! presenter procedure)
(gpu-presenter-close! presenter)
(gpu-drain-pending-presenters!)
```

Backend and context access, diagnostics, rendering, scheduling and closure
are owner-thread operations. The state accessor and predicates inspect only
Racket state. States are `'ready`, `'rendering`, `'closing`, `'closed`, and
`'failed`. `gpu-presenter-context` returns the presenter's owned execution
context for explicit offscreen surfaces/images used by this window; **do not
close that context separately**. Let the presenter close it after retiring
application-owned children.

`gpu-presenter-render!` acquires at most one target, invokes the callback once,
and returns `'present-requested`, `'skipped`, or `'cancelled`. The first means
submission and swap/presentation were requested, not that screen pixels were
observed. A nil Metal drawable skips the callback; it is not a successful
render. A hidden/zero-size widget is skipped without acquiring a target.

Nested immediate rendering is rejected, including rendering a second
presenter within an ordinary `call-with-gpu-context` scope. Use a queued
request instead. Redraw requests made during drawing coalesce. If a user
yield dispatches a queued redraw while a GPU scope is active, it is parked
until that scope unwinds rather than spinning the event loop or switching
contexts under the callback.

Changing the callback schedules one redraw. A callback exception cancels
presentation and retires its target; subsequent explicit drawing remains
possible when cleanup succeeded. Unbalanced canvas save/layer state fails
before submission. An error in acquisition, submission, presentation or
indeterminate native cleanup is not treated as an ordinary callback failure.
A failed presenter must be closed, not silently reused.

Closing during drawing marks the presenter closing, cancels presentation,
and defers native destruction until the callback and target scopes unwind.
Closing another presenter during a GPU scope is deferred for the same reason.
Queued old redraw tickets cannot revive a closed presenter.

`gpu-presenter-info` returns detached diagnostics: selected backend, state,
acquired/presented/skipped/cancelled counts, pending redraw, target generation,
last-frame/error snapshots, and the adapter's context/reference counts. Numeric
GL framebuffer IDs can appear as diagnostics, but no raw FFI pointer or
ownership handle is exposed. A count of presentation requests is not a
count of visible or completed display frames.

## Frame coordinates and lifetime

```racket
(gpu-frame? value)
(gpu-frame-expired? frame)
(gpu-frame-canvas frame)
(gpu-frame-context frame)
(gpu-frame-info frame)
(gpu-frame-width frame)          (gpu-frame-height frame)
(gpu-frame-logical-width frame)  (gpu-frame-logical-height frame)
(gpu-frame-scale-x frame)        (gpu-frame-scale-y frame)
(gpu-frame-generation frame)    (gpu-frame-index frame)
```

Canvas and context access require the original handler thread and a live
callback. Both are cleared from the frame when it expires. Saving the raw
borrowed canvas does not bypass expiry: it also becomes unusable when its
GPU activation ends. Neither a later frame nor another activation revives it.

`gpu-frame-info` and the geometry/generation/index accessors read immutable
metadata and remain usable after expiry. Width/height are **actual framebuffer
pixels**, not requested top-level window dimensions. Logical client dimensions
exclude decorations. Scale is pixel extent divided by logical extent; it can
change when moving between displays. Coordinates exposed to drawing always
start at the top left with positive y down, even though the native GL target
is wrapped with bottom-left origin.

The target generation changes with size/scale/visibility recovery or target
identity. It need not change merely because CAMetalLayer returns a different
drawable texture from its pool. The frame index advances for every acquired
frame, including one subsequently cancelled; skipped acquisition does not
advance it. Neither number is a portable cache key or a texture handle.

A callback that yields may observe resize/hide/closure. Before presenting,
the engine rechecks geometry. It cancels a changed-size frame and schedules
a fresh one instead of presenting stale geometry as current output.

## Native presentation and ownership

**OpenGL:** the adapter captures the host framebuffer before Ganesh creation,
then queries its real format, samples, stencil, draw buffer and pixel extent.
It wraps that target, draws, flushes/submits without a CPU completion request,
and calls the host's swap operation. It never deletes the host framebuffer.
The GUI GL context is exclusive to the presenter. Restoring framebuffer
bindings is not restoration of arbitrary foreign shaders, VAOs or textures;
general external GL interoperation belongs to a separate API.

**Metal:** the GUI adapter adds an owned `CAMetalLayer` sublayer to the
Racket NSView's existing backing layer. It does not replace Racket's layer or
delegate and does not intercept its input events. It uses BGRA8Unorm,
framebuffer-only textures, and an explicit sRGB color-space tag. The GUI
layer is opaque; transparent top-level windows are not implemented. Sizes come
from `bounds` and `convertRectToBacking:`. Objective-C/Core Graphics operations
are checked for the creating handler and the macOS main OS thread. Short
autorelease pools surround synchronous native operations, never user code or
a callback that may yield.

A drawable is retained until drawing, Skia submission, the same-queue
presentation request and target-wrapper cleanup have finished. The adapter
borrows the **exact device and command queue owned by its Ganesh context**;
it does not create an unrelated presentation queue. On a successful frame,
Skia submits first, then a command buffer from that queue receives
`presentDrawable:` and `commit`. Skia wrapper, backend descriptor and local
drawable reference are retired in that order. The committed command buffer
holds the resources needed by its asynchronous presentation.

Normal successful frames request no explicit CPU completion wait or readback.
This does not mean every operation is nonblocking: `nextDrawable` can block
for drawable-pool backpressure, swap may synchronize with the window system,
and first-use shader compilation or allocation may take time. Only immediate
command-buffer error status is checked; the API does not yet report a later
asynchronous GPU/display failure through a completion callback.

**Cancellation is intentionally different.** An unpresented Metal drawable
must not return to the pool while Ganesh still has work targeting it. An
aborted/failed frame therefore flushes and synchronously completes pending
Skia work before returning that drawable. This exceptional-path wait is
reported as `cancelled-frame-sync`; it is not a normal per-frame fence.
Indeterminate abort/destruction quarantines remaining references rather than
releasing a drawable too early or retrying an uncertain unref. Normal context
closure also waits for outstanding work. The adapter keeps at most one owned
reference to its latest presentation command buffer and waits for it during
teardown, before detaching the layer or releasing the context's queue owner.
Ganesh need not track command buffers created by the presentation adapter.

The source's pinned native reference contract is unchanged: Ganesh retains
both Metal device and queue. The new registry stores borrowed pointers, not
additional native ownership, and removes entries before context destruction.

## Opt-in Metal presenter timing

The [windowed-stall investigation](METAL-PRESENTER-TIMING-FINDINGS.md) records
why these probes were added, the quiet-desktop comparison, and the limits of
the conclusions. Desktop compositor workload can delay drawable availability
after the application's GPU work has completed; a long `nextDrawable` call is
not by itself evidence of slow drawing or a leaked drawable.

Use timing when a Metal window stalls before or after its drawing callback. Set
`SKIA_METAL_PRESENTER_TIMING=1` before starting Racket, and attach a debug log
receiver for the topic `skia-metal-presenter`. Both are required: without the
opt-in or an interested receiver, the timing points read no clocks and produce
no events. The environment setting is read when the timing module loads.
No public drawing API or game-loop changes are needed.

The existing Racket GUI event-tracing approach can collect these spans alongside
GUI callbacks. Each log message has prefab data with this layout:

```racket
(struct gui-event (start end name) #:prefab)
(define receiver
  (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
```

Keep the receiver alive while capturing, and drain it from a separate Racket
thread into a bounded buffer. Save the buffer after the capture, not from the
render callback. A receiver accepting all debug topics also works. Existing
collectors that recognize `gui-event` need no new data type; collectors that
filter topics must include `skia-metal-presenter`. If a collector labels every
non-game topic as `racket-gui`, identify these events by their `metal-` names.

Each span produces one completed event, including on an exception or escape;
there is no separate start event. `start` is epoch milliseconds, compatible
with GUI event timestamps. `end` is `start` plus elapsed monotonic milliseconds,
so `end - start` is the duration even if the wall clock changes during the call.
Clock changes can still affect alignment between independently started spans.
The event records time spent, not whether the operation succeeded. A blocked
call produces its event only when it returns or unwinds.

| Phase | What is timed |
| --- | --- |
| `metal-measure` | Reading view geometry and visibility, including native-scope entry/exit. May occur several times per frame. |
| `metal-context-entry` | Entering the GPU context, including its checks and pending resource cleanup, before acquisition begins. |
| `metal-layer-updates` | Updating the layer for the measured frame, including the Core Animation transaction. |
| `metal-layer-frame`, `metal-layer-scale`, `metal-layer-drawable-size` | The individual frame, contents-scale, and drawable-size setters. |
| `metal-layer-commit` | Committing the Core Animation transaction. Also appears during layer setup and teardown. |
| `metal-next-drawable` | The `nextDrawable` call, including time waiting for an available drawable. A null result is timed too. |
| `metal-acquire` | The complete acquisition, including layer updates, `nextDrawable`, validation, and native-scope entry/exit. |
| `metal-wrap-target` | Creating the Skia target wrapper and frame canvas. |
| `metal-clear` | Clearing the target before the drawing callback. |
| `metal-receive` | The common frame receiver: the drawing callback, subsequent checks, and submission/presentation when accepted. This is not drawing-callback time alone. |
| `metal-flush-submit` | Skia flush and submission; not completion of GPU execution. |
| `metal-present` | Queuing the same-queue presentation command buffer, not waiting for display. |
| `metal-retire-target`, `metal-release-drawable` | Retiring the Skia wrapper and backend descriptor, then releasing the local drawable reference. The latter is part of the former. |
| `metal-cancelled-frame-sync` | The existing exceptional-path completion wait for an unpresented frame. |
| `metal-target` | The complete adapter target call, including context entry, acquisition, drawing, presentation, cleanup, and context exit. It excludes earlier handler dispatch and geometry measurement. |

Spans are nested and logged in completion order. Do not add parent and child
durations together. Compare `metal-layer-updates` with `metal-next-drawable`
first, then use the smaller phases to locate other delays. These are CPU-side
elapsed times, including blocking, GC, or scheduling pauses where permitted;
they do not measure GPU execution or prove the cause of drawable backpressure.
Several windows can emit the same names, so correlate with the enclosing GUI
callback or capture one window at a time.

For a quick textual check without a trace collector:

```sh
SKIA_METAL_PRESENTER_TIMING=1 \
PLTSTDERR='error debug@skia-metal-presenter' \
racket examples/gpu-presenters.rkt --backend metal
```

Messages show the phase and elapsed milliseconds. Console logging and trace
collection add overhead; use buffered capture for performance comparisons and
compare equivalent runs with timing disabled. Instrumentation adds no GPU
waits, readbacks, retries, or changes to layer updates, drawable acquisition,
frame scheduling, cancellation, or the application's simulation.

### Individual garbage collections

To compare GC pauses with presenter stalls, set `SKIA_GC_TRACE=1` before loading
the developer helper `tools/gc-trace.rkt`. This is a collector opt-in, not a
rendering option: the helper is not loaded by the library and does not request
collections, change GC policy, or change frame scheduling. Enabling the flag
alone does not create a capture.

`make-gc-trace-receiver` creates a receiver for debug topic `GC` when enabled,
or returns `#f` when disabled. A collector with an existing all-debug receiver
can use that receiver instead. Pass each message to `gc-log-message->record`
and buffer any returned record alongside the presenter spans. The helper reads
the environment once on module loading; `gc-trace-enabled?` reports that setting.

Each JSON-compatible `gc` record includes:

- `mode`: `minor`, `major`, or `incremental`;
- `start` and `end`: the runtime's epoch-millisecond collection timestamps;
- `cpu_start`, `cpu_end`, `cpu_ms`, and `wall_ms`: processor timestamps and the
  CPU/elapsed durations, in milliseconds;
- `pre_bytes`, `post_bytes`, their `*_admin_bytes` counterparts, and `code_bytes`:
  memory before/after collection, including overhead in the admin values;
- `received_at`: when the collector processed the message, which can be later
  than the collection if a native call delayed Racket threads.

The helper uses Racket's documented `gc-info` payload, not its message text.
It ignores `GC:major`, which would count a major collection a second time, and
accepts additional trailing payload fields. An unsupported `GC` payload produces
a `gc-error` record; do not interpret those errors as an absence of collections.
The memory values describe the reporting Racket place, not total process/GPU
memory. Capture one application place for unambiguous correlation.

Compare interval overlap using `start`/`end`, never `received_at`. GC timestamps
may have millisecond resolution, so a very small apparent gap or overlap is not
conclusive. Distinguish collections inside a stall from those immediately before
or after it; correlation alone does not establish the cause of drawable waits.
Keep startup/restart collections separate from steady gameplay statistics.
Report dropped records and retain enough post-sample capture time to drain logs
that were delayed by a stall. Buffering itself allocates memory and can affect
GC frequency; do not log to disk or print individual events during the sample.

### Layer geometry and occlusion observations

To distinguish setter calls from actual geometry changes, keep the same opt-in
and attach a second debug receiver for `skia-metal-presenter-state`:

```racket
(struct metal-presenter-state (time host phase fields) #:prefab)
(define state-receiver
  (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-state))
```

The receiver gets snapshots at `before-update`, `after-update`, `after-acquire`,
and `after-release`. `time` is epoch milliseconds at the start of the observation;
`host` identifies the layer without exposing a native pointer. These records are
separate from `gui-event` spans, so existing span-only collectors ignore them.
Without an interested state receiver, the additional native getters do not run.

The immutable `fields` hash contains:

- `frame`, `bounds`, and `view_bounds`: `(x y width height)` in logical units;
- `contents_scale` and `window_backing_scale`: scale factors;
- `drawable_size` and `requested_drawable_size`: `(width height)` in pixels;
- `window_present`, `window_visible`, `window_minimized`, `window_key`,
  `view_hidden`, the raw `window_occlusion_state` bitmask, and `occlusion_visible`;
- `live_drawables`, `presents_requested`, and the `drawable_id` after acquisition;
- `skip_unchanged_setters` and `skip_empty_transactions`: the two experiment switches;
- `display_sync_enabled` and `presents_with_transaction`;
- `observation_ms`: time spent reading the snapshot, excluding log emission.

Window-dependent fields are `#f` when no window is attached. Requested size is
`#f` after release; drawable ID is `#f` outside acquisition or for a null result.
The after-acquisition observation precedes registering the local drawable lease.
If a diagnostic read raises an ordinary exception, the record instead contains
`observation_error` and its duration; rendering errors are not suppressed.

Compare each before/after pair, and successive frames, to identify real changes.
By default, all original setters still run even when their values match. Occlusion is only
observed: it does not skip frames or change visibility policy. A visible occlusion
bit means some of the window is visible, not that the entire canvas is unobscured;
the before/after snapshots cannot exclude a transition during a blocking call.
The snapshots describe model-layer properties, not compositor completion. Stable
geometry alone does not prove that redundant setters have no deferred cost.

Buffer both topics and correlate their timestamps with Metal System Trace before
attributing stalls to the compositor. Observations add CPU work but no GPU waits,
readbacks, layer changes, drawable references, or changes to the simulation.

### Experiment: skip unchanged layer setters

To test whether repeated setter calls contribute to drawable stalls, set
`SKIA_METAL_SKIP_UNCHANGED_LAYER_SETTERS=1` before starting Racket. This private
experiment is off by default and independent of timing and log receivers. Its
environment setting is read when the Metal layer module loads; it is not a
public rendering option or an established performance improvement.

When enabled, the adapter compares the layer's current model `frame`,
`contentsScale`, and `drawableSize` with the requested values immediately before
each corresponding setter. It skips only an equal value, using exact numeric
comparison without a tolerance or cached requests. Changed values still use the
original setters in the original order. With the experiment disabled, all three
setters run as before, without these extra comparison reads.

With only this switch enabled, the Core Animation transaction still begins and
commits, even when all three setters are skipped. This isolates setter omission
from transaction omission.
Layer creation, drawable acquisition and ownership, submission, presentation,
frame scheduling, and the application's simulation are unchanged.

For a matched timing capture, use both environment settings and the same log
receivers. A skipped setter produces no `metal-layer-frame`, `metal-layer-scale`,
or `metal-layer-drawable-size` span; the enclosing `metal-layer-updates` and
`metal-layer-commit` spans remain. State records include `skip_unchanged_setters`
so a capture identifies which mode ran. Compare equivalent steady-size runs,
and also check resizing: unchanged values should skip setters, not prevent a
new size or scale from taking effect. One faster run alone does not establish
that setter omission fixes a compositor stall.

### Experiment: also skip empty layer transactions

To extend the setter experiment, also set
`SKIA_METAL_SKIP_EMPTY_LAYER_TRANSACTIONS=1` before starting Racket. Both this
switch and `SKIA_METAL_SKIP_UNCHANGED_LAYER_SETTERS=1` are required; the new
switch alone has no effect. It is default-off, read on module loading, and
independent of timing and log receivers.

With both switches enabled, the adapter first compares the current layer frame,
contents scale, and drawable size with the requested values in the existing
owner-thread native scope. If all match, it returns without beginning a Core
Animation transaction, disabling actions, calling setters, or committing. If
any value differs, the existing transaction and selective setters still run.
Default and setter-only modes do not perform this extra preflight.

An unchanged frame therefore has no setter or `metal-layer-commit` spans, while
`metal-layer-updates` still measures the preflight. State observations report
both switches. Layer-creation and teardown transactions remain, as do update
transactions for real size or scale changes. This does not suppress transactions
created by Racket, AppKit, or other application code, or change presentation's
`presentsWithTransaction` setting.

Compare this mode with the setter-only capture to test the effect of omitting
empty update transactions. Drawable acquisition, ownership, GPU submission,
presentation, frame scheduling, and the game's simulation remain unchanged.

### Opt-in Racket flush and Cocoa run-loop tracing

Set `SKIA_METAL_COCOA_TRACE=1` before creating a Metal presenter and subscribe to
the debug topic `skia-metal-presenter-cocoa`. This switch is default-off and
independent of timing and both layer-update experiments. It is read on module
loading; the receiver must exist when the presenter is created. Without both
opt-in and a receiver, no observer is installed and no private GUI state is read.

The topic carries prefab records
`(metal-presenter-cocoa-state time host phase fields)`. The phases are
`before-next-drawable` and `after-next-drawable`; the latter also runs when
acquisition raises. Sampling is outside the `metal-next-drawable` timing span.
Fields include:

- `flush_suspended` and `flush_suspended_for_window`: Racket's current global
  flush suspension and whether it belongs to this presenter's window;
- `racket_sleeping`, `racket_events_suspended`, and `racket_run_loop_exited`:
  Racket's private Cocoa event-pump flags, not measures of OS thread activity.
  The last flag remembers a run-loop exit during Racket's current or latest
  native sleep attempt; `#t` is not itself an error or evidence of a stall;
- `run_loop_events` and separate entry, before-timers, before-sources,
  before-waiting, after-waiting, and exit counters: passive observations of the
  main Core Foundation run loop in common modes;
- `run_loop_last_activity`, `run_loop_last_age_ms`, `racket_version`, and
  `observation_ms`: the latest observed phase, its age, runtime version, and
  snapshot cost. An absent last activity is `#f` until an event is observed.

Counters are cumulative per presenter. Equal counters before and after a long
acquisition show no observed run-loop progress during that call; they do not
prove that lack of progress caused the wait. These are Core Foundation phases,
not counts of Racket polling calls or proof of a Core Animation commit. Likewise,
the flush flag covers Racket's own suspension mechanism, not every transaction
that AppKit or application code might have opened.

Private Racket bindings may change across versions. Installation or observation
failures are reported as `installation_error` or `observation_error`, not as an
unsuspended state. `run_loop_callback_error` reports an observer failure. No
native pointers enter records. The observer is removed on presenter close.
This diagnostic does not edit Racket, replace its callbacks, flush transactions,
pump events, add wakeups, or change GPU work or frame scheduling. Observation
still costs CPU time, so compare equivalent runs without it before drawing
performance conclusions. `observation_ms` measures snapshot cost, not the
separate cost of the native run-loop callbacks.

## Cleanup, failures, and scope

Retire application-created images, paints, pictures and surfaces that retain
the presenter's GPU context before final closure. `gpu-presenter-close!`
refuses a context with live children and leaves a retryable closing state.
It does not abandon the context merely to conceal leaks.

GC and custodian fallback request owner-side cleanup. They do not issue Cocoa
or GPU destruction from the finalizer thread. `gpu-drain-pending-presenters!`
tries pending cleanup for the current owner outside all GPU scopes, returning
diagnostic snapshots. A dead handler/eventspace or an indeterminate native
release can leave quarantined resources; this is a safety measure, not a
promise of complete cleanup after forcibly killing a GUI owner. Explicit
closure before shutting down an eventspace is preferred.

This API does not adopt external textures, share GPU objects between contexts,
automatically migrate a widget between backends, implement Linux EGL, or add
GPU PDF/SVG fallback rendering. CPU transfer and document policy remain as
specified by the existing APIs. See [validation](GPU-PRESENTATION-TESTING.md).

## Implementation sources

The native baseline is SkiaSharp 3.119.1 / mono/skia
`40f75dc0051d141913c07c20d4c19590c7da0cb7`.

- [Pinned Skia Metal window acquisition and same-queue presentation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/tools/window/MetalWindowContext.mm)
- [Pinned Ganesh render-target C ABI](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/gr_context.h)
- [Racket canvas sizes and backing scale](https://docs.racket-lang.org/gui/canvas___.html)
- [Racket canvas/OpenGL host methods](https://docs.racket-lang.org/gui/canvas_.html)
- [Racket native window handles](https://docs.racket-lang.org/gui/window___.html)
- [Apple Metal command queues and buffers](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Cmd-Submiss/Cmd-Submiss.html)
