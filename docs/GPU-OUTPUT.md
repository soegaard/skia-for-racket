# GPU execution for bounded output groups

`draw-output-group` separates the representation of document content from the
place where an explicitly selected raster is rendered:

```
PDF/SVG policy → native replay, bounded raster, or rejection
bounded raster → CPU or a selected GPU context
GPU raster     → explicit synchronous readback → CPU-owned document image
```

CPU remains the default. GPU execution is opt-in and does not change the
capability table, author-provided geometry, or the existing rejection rules.
An ordinary vector group stays vector; a GPU is not an alternative meaning of
`require-vector`. See [output policy](OUTPUT-AUDIT.md) and
[GPU resource ownership](GPU-IMAGES.md) for the underlying contracts.

## An existing context

Import `skia/gpu-output` explicitly, alongside `skia` and `skia/gpu`:

```racket
(require skia skia/gpu skia/gpu-output)

(define context (make-gpu-context #:backend 'metal))
(dynamic-wind
  void
  (lambda ()
    (define executor (make-gpu-raster-executor context))
    (define page
      (make-output-page 240 180
        (lambda (canvas)
          ;; This content remains ordinary document geometry.
          (with-skia ([ink (make-paint #:color 'black)])
            (draw-line canvas 20 30 220 30 ink))
          (draw-output-group canvas 40 54 120 72
            (lambda (group-canvas)
              (with-skia ([effect
                           (make-runtime-effect
                            "half4 main(float2 p) { return half4(0.2,0.5,0.8,1); }")]
                          [shader (runtime-effect->shader effect)]
                          [paint (make-paint #:shader shader)])
                (draw-rounded-rect group-canvas 12 12 96 48 8 8 paint)))
            #:padding '(8 10 12 14)
            #:scale 3/2
            #:raster-executor executor))))
    (save-output/audit page "gpu-fallback.svg" 'svg #:policy 'error))
  (lambda () (gpu-context-close! context)))
```

An OpenGL context uses the identical executor and callback. Context construction
is still explicit through an OpenGL host/provider, or the optional EGL module.
This module does not initialize a GUI or choose a device on import.

### `make-gpu-raster-executor`

```racket
(make-gpu-raster-executor context) ; → output-raster-executor?
```

Borrows a ready `gpu-context?`. Creation and use belong to its owning Racket
thread. The executor keeps the context reachable but does not close it. Closed,
abandoned, shutdown-requested, or foreign-owner contexts are errors. Generation
and readiness are checked again on use.

CPU-owned captured resources can be replayed without the caller activating the
GPU: the executor activates its specified context around rendering and readback.
An already active scope for that same context is supported. An active foreign
context is rejected, never silently substituted.

A picture containing GPU-resident resources must belong to this exact context.
To author such a picture, surround capture with `call-with-gpu-context` for that
context and choose a raster policy when needed. The executor does not make a
GPU image eligible for native PDF/SVG serialization. A native replay containing
GPU-dependent resources still fails the existing document ownership guard.

## Lazily owned context

```racket
(call-with-gpu-raster-executor make-context proc
                               #:on-unavailable [policy 'error])
```

`make-context` is a zero-argument procedure returning a newly owned GPU context.
`proc` receives the executor and may export several documents/groups. Its return
values are preserved. A context is constructed at most once, only when a group
has actually selected raster representation and its outer audit policy has
accepted the decision. An all-vector export never calls the factory.

The scope closes the created context on normal return, exception, or escape.
The executor expires on exit, even when no context was created. Application GPU
children must not escape this owning scope; the ordinary context-close guard
still refuses to silently destroy live children.

The default policy is `'error`. Explicit `'cpu` permits a fallback only when the
**context factory** raises `exn:fail:gpu:unavailable?`. The absence and CPU choice
are recorded and reused for the rest of the scope. Invalid returned contexts,
wrong context/thread use, allocation limits, shader/render/readback failures,
and cleanup errors are not treated as absence. They fail instead of retrying on
CPU. In particular, authoring callbacks are never rerun to recover from a GPU
failure.

```racket
(call-with-gpu-raster-executor
  (lambda () (make-gpu-context #:backend 'metal))
  (lambda (executor)
    ;; Pass executor explicitly to the groups that may use it.
    (export-my-documents executor))
  #:on-unavailable 'cpu)
```

`export-my-documents` above denotes application code, not a library procedure.

## Group selection and nested capture

`draw-output-group` accepts the additional optional keyword:

```racket
#:raster-executor [executor #f]
```

A supplied executor selects GPU execution for a raster-selected group. Explicit
`'cpu` selects the existing CPU implementation. `#f` means contextual default:
it inherits only from the **exact recording canvas of the enclosing output-group
capture**, otherwise it means CPU. `output-raster-executor?` recognizes executor
values; it does not imply that an owning scope or context is still live.

There is no global GPU-output parameter. Drawing into an unrelated CPU canvas
inside a group callback does not inherit the group executor. An unrelated picture
recorder cannot inherit either its document backend or its executor. Its group
attempt is rejected. Explicit nested overrides are allowed subject to the usual
context/thread guards.

Each authoring callback runs once per group invocation. A nested raster child is
resolved during capture, and its detached image can become part of a natively
replayed outer picture. Conversely, a forced-raster outer group may rasterize
that already-captured child again; the two raster executions and two transfers
are recorded on their respective reports. Each group's policy is checked at its
own decision point; rejection of an outer group does not undo work already done
by a nested group while capturing it.

## Geometry, color, and cost

Both CPU and GPU execution derive pixel sizes by ceiling the padded logical
extent times the requested scale. The pixel-to-logical transform uses those
actual integer extents. The inset order is **left, top, right, bottom**. Page
placement stays outside the capture; the padded local clip is shared by both
strategies. For a 120 × 72 content box, insets `(8 10 12 14)` and scale `3/2`, the
embedded image is exactly **210 × 144** pixels covering **140 × 96** local units.
The existing `current-raster-output-scale`/output DPI defaults remain effective.

The GPU surface is transparent, RGBA8888/premultiplied, with requested sample
count zero. The current device's allocation/sample limits are enforced. This
does not read the receiving document's backdrop: blending is isolated exactly
as in the CPU path. Include any needed internal backdrop in the group itself.

`#:color-space` is passed to the temporary GPU surface, and the detached image
retains that space. The normal readback and CPU-image construction routines are
reused. GPU execution is not a zero-copy document export: it allocates a target,
waits for synchronous readback, and copies pixels into CPU-owned image storage.
Native documents may retain the CPU reference after the Racket temporary has
closed, and can finish/serialize after the GPU context has closed.

The byte limit constrains individual raster dimensions/allocations; it is not a
promise that simultaneous target, readback, document, and driver caches together
fit that many bytes. No speedup is assumed. Small groups or frequent downloads
may be slower than CPU rendering and require measurement.

## Policies and audit reports

The native/raster/reject decision is unchanged. GPU selection does not weaken
`require-vector`, outer `vector-only` audit, unknown/imported-SKP provenance,
annotation loss, native-text loss, or device-coordinate clipping rules. Native
PDF text combined with effects still requires an explicit text-outline choice
before it can become a raster group. Put document links outside the raster.

GPU lifetime checks always see a GPU target. For representation auditing only,
an internal scope gives **one exact temporary surface handle** raster semantics
while replaying the picture. Another surface, an inherited thread, an expired
scope, or unrelated recording cannot borrow that authority.

`output-group-report-execution` returns an immutable detached hash, also present
as `execution` in `output-group-report->jsexpr`. The existing report accessors
and fields keep their meanings. The added execution fields are:

| Field | Meaning |
|---|---|
| `requested` | `cpu` or `gpu`. |
| `phase` | `native`, `rejected`, `planned`, `rasterized`, or `completed`. |
| `backend` | Document backend for native replay, `raster` for CPU, or `opengl`/`metal` for GPU; false when undecided. |
| `context_generation` | Actual GPU generation, or false. |
| `fallback` | False, or the explicit factory-unavailability reason/step/message. |
| `readback_count`, `transfer` | This group's actual readbacks and `gpu-to-cpu`/`none`; nested work is in `captured_children`. |
| `image_storage` | `cpu-owned` after raster production, otherwise false. |
| `target` | Detached native GPU surface diagnostics, or false. |

The `draw-output-group` audit event remains the **pre-execution decision** and
may say `planned`; it does not certify a completed download. The additional
`execute-output-group` event records actual raster production and transfer. GPU
execution emits that event before destination embedding (`rasterized`); the
returned group report says `completed` after successful embedding. A later
exception prevents a successful output/report return. Nested decisions made
while capture suppresses the collector remain in `captured_children`.

`analyze-output-page` is still an executing preflight, not static analysis.
As with CPU temporary rasters, a GPU-selected temporary raster really runs and
reads back; the final destination drawing is suppressed. Separately analyzing
and exporting a page is two invocations of its application callback.
