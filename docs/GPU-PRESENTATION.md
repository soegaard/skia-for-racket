# GPU window presentation

Import `skia/gpu` for presenter/frame operations and `skia/gpu-gui` for the
Racket GUI widgets. Import `skia` for ordinary drawing. The drawing callback
is the same on OpenGL and Metal; it receives a borrowed frame, not a native
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

`'auto` chooses Metal on macOS and OpenGL elsewhere. It is a selection policy,
not a fallback policy: failed Metal construction does not silently become
OpenGL or CPU drawing. An explicit backend is either `'opengl` or `'metal`.
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
| `(send canvas close-gpu)` | Stops automatic scheduling and requests safe closure. Retry after retiring application GPU resources if they prevented context closure. |
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
     [backend 'auto] [render void] [on-error raise]
     [background 'white] [automatic? #t])
```

It supplies `get-gpu-canvas`, `get-gpu-presenter`, `request-gpu-render`, and
`close-gpu`. Ordinary `show`, `resize`, `move`, and `iconize` remain GUI methods.
Closing from the window manager requests GPU closure and hides the frame.
`close-gpu` hides the frame even when application-owned GPU resources block
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
