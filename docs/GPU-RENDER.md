# Render one image on the GPU

The `render-gpu->raster-image` function is available from `skia/gpu`. It uses the
existing GPU backends and ordinary canvas drawing API, with no new native ABI.

```racket
#lang racket

(require skia skia/gpu)

(define (draw-scene canvas)
  (define paint (make-paint #:color "#326DE6"))
  (draw-circle canvas 160 90 55 paint))

(define image
  (render-gpu->raster-image 320 180 draw-scene
                           #:backend 'metal
                           #:background 'white))

(save-image image "gpu-scene.png" 'png #:exists 'replace)
```

The result is an ordinary owned CPU image. All GPU resources created by the
helper have been closed before it returns. The caller can encode, inspect, or
retain the image without another GPU activation. Use ordinary bindings unless
prompt release of that CPU image matters.

## Contract

```racket
(render-gpu->raster-image width height draw
                         #:backend backend
                         #:background [background 'transparent]
                         #:provider [provider #f]
                         #:adapter [adapter #f]
                         #:adapter-index [index #f])
```

The width and height are exact positive pixel dimensions, at most 32768. Their
RGBA byte size must fit `current-skia-byte-limit`; the selected context's native
render-target limit can be smaller. The background accepts the same colors as
`make-surface`. These checks occur before GPU construction.

The callback must accept one positional argument without required keywords. It
is invoked once, synchronously on the caller's Racket thread, with an ordinary
borrowed `canvas?` inside the new context's activation. Its return values are
ignored, including zero or multiple values. It must not retain or later use the
canvas. The helper is not a sandbox or a timeout for callback code.

The target uses the existing default GPU surface settings: RGBA8888,
premultiplied alpha, no explicit color-space tag, requested sample count zero,
and a top-left, y-down coordinate system. There is no implicit DPI scaling.
The returned CPU image uses the existing `gpu-surface->raster-image` transfer.
Different formats, color spaces, sample counts, and context options remain
available through the lower-level API rather than extra options on this helper.

## Explicit backend selection

The backend keyword is required. There is no `auto` mode, CPU fallback, or retry
on another backend.

* The `metal` backend uses an owned context on a compatible macOS system. It
  accepts no provider or adapter options.
* The `direct3d` backend uses an owned context on Windows. The adapter defaults
  to `hardware`; explicitly select `#:adapter 'warp` for software WARP. The
  adapter index defaults to zero, is in 0 through 4294967294, and must be zero
  for WARP. There is no automatic hardware-to-WARP fallback.
* The `opengl` backend requires `#:provider` with an existing OpenGL host
  provider. The helper owns its new Ganesh context, but **borrows the host**.
  Keep that host alive through the call. It must not already belong to another
  live Ganesh context. The helper neither creates nor destroys an OpenGL window
  or host. Adapter options do not apply.

For example, an application that already has a suitable GL host can pass the
provider returned by `make-racket-gl-provider`. Context creation retains the
existing host-identity, owner-thread, future, and nested-domain checks. Do not
call this one-shot helper from inside another GPU activation.

## Lifetime and failure behavior

The helper creates a context, activates it, creates a surface, calls the drawing
function, and synchronously reads back the pixels. It then closes the surface,
leaves the activation, and closes the context. Only then is the CPU image
returned. No separate flush or submit call is needed before this readback.

Cleanup runs on normal completion, exceptions, arbitrary raised values, breaks,
and outward continuation escapes. Saved continuations cannot reenter a finished
render. The GPU resources are acquired in protected scopes; backend checks are
inside those scopes too. If cleanup fails after a CPU image has been obtained,
the helper closes that undeliverable image rather than leaking it.

Callback and rendering failures propagate when cleanup succeeds. A cleanup
failure can supersede an earlier failure, following the nested cleanup scopes;
it is not suppressed, retried, or disguised as an availability fallback. Native
resource destruction can be indeterminate after a driver failure. This helper
does not promise recovery from every device-loss condition or forcibly close
resources owned by other code.

The helper verifies the context, surface, and canvas backend before drawing.
Those checks identify the execution path; they do not certify hardware
acceleration, speed, or exact CPU/GPU pixel parity. The explicit WARP choice is
still software rendering even though it uses the Direct3D backend.

## Repeated rendering

Each call creates and destroys a context and performs a synchronous download.
Use this helper for a one-off image, preview, or export, not as the default
animation loop. Keep a context and surfaces between frames with
`make-gpu-context`, `call-with-gpu-context`, and `make-gpu-surface` when reuse
matters. Use GPU-resident snapshots when later work should remain on the GPU.

See [offscreen GPU surfaces](GPU-OFFSCREEN.md), [GPU images](GPU-IMAGES.md), and
[Metal](GPU-METAL.md) for the underlying operations and ownership contracts.

## Validation and API review

The pure suite exercises the production lifetime worker with injected operations
and checks public arguments without loading a GPU driver. The native suite runs
real solid-color rendering, PNG encoding after teardown, expired-canvas checks,
callback failures, prompt escapes, and successive renders.

```bash
racket tests/gpu-render-pure-test.rkt
racket tools/gpu-render-doctor.rkt --backend metal
# Windows alternative, deliberately selecting software WARP:
racket tools/gpu-render-doctor.rkt --backend direct3d --adapter warp
```

The native suite also accepts an idle OpenGL provider through its test factory,
`make-gpu-render-native-tests`, for existing OpenGL host test harnesses. The
command-line doctor above tests the owned Metal and Direct3D routes only.

The exact public API gate requires approval of this additive export. The
separate `tools/accept-gpu-render-api.py` command uses real Racket reflection and
refuses every difference other than this function's declared call boundary.
Without `--accept` it only reports the proposed update. The source review also
checks the exact patch bytes/edits declared in `api/gpu-render-addition.json`,
updates the frozen release-source ledger, and rejects unrelated changes. It
never fabricates a runtime observation or weakens the general validators.

```bash
python3 tools/accept-gpu-render-api.py --racket /absolute/path/to/racket
python3 tools/accept-gpu-render-api.py --racket /absolute/path/to/racket --accept
python3 tools/update-source-sums.py
python3 tools/update-source-sums.py --check
python3 tools/validate-public-api.py --racket /absolute/path/to/racket
```

The accepted snapshot, generated index, and updated release-source review and
report must be reviewed and committed with this addition. The source manifest
is regenerated on the complete checkout,
including those reflected files. Tests and source declarations are not evidence
that the selected native backend has actually executed on this machine.
