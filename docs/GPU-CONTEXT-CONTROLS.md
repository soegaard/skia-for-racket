# GPU context options and targeted resource operations — 0.77b

The package version is `0.77`. This stage adds six immutable m119 context
options, targeted surface/image flush, and **healthy-host** release-and-abandon.
It does not add a compiler, CMake, another native library, or another worker.

The accepted 0.77a implementation is the baseline. This stage does not replace
`graphics.rkt`, its trace collector, its tests, or its global-cache guide.

## Configuration values

```racket
(require skia/gpu-context-options)

(make-gpu-context-options
 #:avoid-stencil-buffers? #f
 #:runtime-program-cache-size 256
 #:glyph-cache-texture-maximum-bytes 8388608
 #:allow-path-mask-caching? #t
 #:manual-mipmapping? #f
 #:buffer-map-threshold -1)
```

`gpu-context-options?` recognizes the immutable value. The accessors are:

```racket
(gpu-context-options-avoid-stencil-buffers? options)
(gpu-context-options-runtime-program-cache-size options)
(gpu-context-options-glyph-cache-texture-maximum-bytes options)
(gpu-context-options-allow-path-mask-caching? options)
(gpu-context-options-manual-mipmapping? options)
(gpu-context-options-buffer-map-threshold options)
(gpu-context-options->jsexpr options)
```

The last operation returns an immutable JSON-compatible hash of requested
settings. Requiring this module does not load Skia or initialize a backend.
The option value is not a native resource and does not require `skia-close!`.

| Keyword | Meaning and accepted values |
|---|---|
| `#:avoid-stencil-buffers?` | Boolean request to use alternatives to stencil buffers. |
| `#:runtime-program-cache-size` | Exact positive program/pipeline cache entry count, at most 2^31−1. Zero is not exposed by this reviewed wrapper. |
| `#:glyph-cache-texture-maximum-bytes` | Exact positive 64-bit byte budget for glyph cache textures. It is not a total GPU-memory limit. |
| `#:allow-path-mask-caching?` | Boolean request to permit caching path masks. |
| `#:manual-mipmapping?` | Boolean request for Skia's manual mipmap construction path where applicable. |
| `#:buffer-map-threshold` | `-1` delegates the mapping threshold to native platform selection; otherwise an exact integer from 0 through 2^31−1. |

The defaults mirror the six fields in the pinned `GrContextOptions` definition.
Unsupported fields from the much larger C++ structure are not silently invented.
Backend capabilities and driver workarounds still apply; a request is not proof
of a particular caching strategy, memory consumption or performance outcome.

## Context construction

`gpu.rkt` re-exports the configuration API and accepts `#:options`:

```racket
(require skia skia/gpu)

(define options
  (make-gpu-context-options #:runtime-program-cache-size 128
                            #:allow-path-mask-caching? #f))
(define context (make-gpu-context #:backend 'metal #:options options))
```

OpenGL hosts use `(make-gpu-context provider #:options options)`. Owned Direct3D
contexts also accept the keyword, together with existing adapter selection.
`make-egl-gpu-context` in `gpu-egl.rkt` forwards `#:options` to the GL driver.

**Omitting `#:options`, or passing `#f`, retains the existing native factory.**
An explicit value uses the corresponding native `*_with_options` factory. Thus
an explicitly constructed default value and `#f` are distinguishable requests.
The native factory copies the six-field descriptor synchronously; no descriptor
pointer or Racket option value is retained by Skia.

`gpu-context-info` adds these detached fields:

- `context_factory`: the factory route selected by the wrapper.
- `context_options_source`: `"native-defaults"` or `"explicit"`.
- `context_options`: `#f` or the requested configuration hash.
- `context_options_native_readback`: always `#f`.

**The pinned C ABI has no effective-options getter.** These fields are not
native readback and must not be relabelled as verified effective settings.
Existing provider/backend diagnostic fields remain intact.

This wrapper reviews the 64-bit m119 POD layout: size 24, alignment 8, offsets
0/4/8/16/17/20. It checks the FFI layout before marshalling explicit values.
The Direct3D backend descriptor remains passed **by value**, with the options
record passed by pointer, matching the native signature.

Existing convenience presenters and GUI factories retain their own context
construction defaults. This stage does not add option keywords to every GUI
constructor. No global default-options parameter is introduced.

## Targeted flush

```racket
(gpu-flush-surface! context surface)
(gpu-flush-image! context image)
```

Both require the owning Racket thread and an active `call-with-gpu-context`
scope for `context`. The resource must be live, actually GPU-resident, and owned
by that same execution domain. CPU/PDF/SVG resources are rejected rather than
uploaded. A surface must also have a balanced native canvas save/layer stack.
Borrowed/exclusive surface-use guards remain in effect.

A targeted flush asks Skia to flush pending work associated with that target.
It may include dependent work: this is not a promise that no unrelated GPU work
will execute. It does **not** request submission, wait for CPU completion,
present a window, or copy pixels to CPU memory. Its return value is `void`.

To request completion explicitly:

```racket
(call-with-gpu-context context
  (lambda ()
    ;; ...draw using live resources owned by context...
    (gpu-flush-surface! context surface)
    (gpu-submit! context #:wait? #t)))
```

`gpu-wait!` remains the existing whole-context flush/submit/wait convenience.
A targeted flush is not an exported native fence or a synchronization primitive
for interoperation with another device/queue.

The private ledger records `kind="flush"`, a `target` of `surface` or `image`,
the context generation, `submission_requested=#f`, and
`completion_guaranteed=#f`. Existing readback and submission ledgers are not
rewritten. There is no hidden upload, detach, image conversion, or readback.

## Healthy-host release and abandonment

```racket
(gpu-context-release-and-abandon! context)
```

Use this only while the native host/context/device is still usable. It must run
on the context owner **outside all GPU execution scopes**. The operation:

1. Activates the provider and rechecks the domain after provider activation.
2. Performs the driver's validity/reset check and drains pending resource releases.
3. Calls native `releaseResourcesAndAbandonContext` and verifies abandonment.
4. Makes subsequent use of the context and its children fail.

Live image/surface wrappers are not silently closed. They still own references:
retire them with `skia-close!`, then close the context with `gpu-context-close!`.
Until then, normal context close rejects live children. This preserves existing
ownership accounting and finalization behavior. Old canvas leases are invalid.

The native context and any separately retained device/queue handles remain owned
until final close. A successful abandon lets later queued Skia unrefs be drained
without reactivating a host that may since have been destroyed.

There is no promise that unsubmitted content is preserved. Request `gpu-wait!`
before teardown when the application requires completion of prior drawing. The
new operation is not advertised as a CPU fence or as a readback.

### Three distinct operations

| Operation | Intended use | Context afterwards |
|---|---|---|
| `gpu-free-resources!` | Release purgeable/context resources under the existing cache API. | Still usable. |
| `gpu-context-abandon!` | Host is lost or no longer safe to activate. Existing nonactivating loss path. | Abandoned. |
| `gpu-context-release-and-abandon!` | Healthy host is about to be retired; activate it and release resources first. | Abandoned. |

The old loss path is not redirected to the healthy-host operation. A native
exception or failed postcondition after healthy teardown has begun makes the
domain `release-failed` and requests shutdown. It is **quarantined**, not retried
via healthy teardown, loss abandonment, or close. This intentionally favors a
rooted leak over indeterminate double destruction. An error before native
teardown, such as provider activation failure, does not claim native release.

Asynchronous breaks are suppressed during provider/native teardown and lease
retirement. This is not an arbitrary user callback API. The scheduling hooks and
native dispatch hooks are private; no new user-supplied native destructor exists.

## Validation

```bash
python tools/validate-gpu-context-controls.py \
  --racket "/Applications/Racket v9.3.0.2/bin/racket" \
  --require-gpu --backend metal
```

For Linux use `--backend egl`; for Windows software execution use
`--backend direct3d --adapter warp`. The validator always requires a real selected
GPU backend; `--require-gpu` makes that requirement explicit, not optional.
There is no mocked-worker or CPU-fallback acceptance mode.

The focused suites contain 22 pure cases, 12 native ABI/symbol cases (no GPU
rendering is inferred from them), and 20 selected-backend cases. The latter
produce five independently checked 32×24 RGBA captures, targeted-flush ledgers,
and healthy-abandon/child-retirement evidence. Pixel correctness does not by
itself prove a hint changed a driver's internal policy; request metadata stays
explicitly distinct from native readback.

The default also runs complete global regressions. `--regressions none` omits
only that global suite; focused tests and native evidence remain required and
omitted work is reported as `not-run`, not passed. Independent document renderers
are not required for this stage. Existing PDF/SVG acceptance remains unchanged.

`gpu-context-controls.yml` adds Linux Racket 8.18/9.3 and Windows WARP 9.3 jobs
inside Acceptance and feeds its required gate. Central installed-package CI also
runs the pure and ABI suites, including macOS. Local Metal execution remains a
separate native acceptance command; a configured workflow is not execution proof.

## Reviewed native sources

All refer to mono/skia commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`:

- `include/c/sk_types.h`: `gr_context_options_t`.
- `include/c/gr_context.h`: option factories, targeted flush and release/abandon.
- `src/c/gr_context.cpp` and `src/c/sk_types_priv.h`: forwarding/copy semantics.
- `include/gpu/GrContextOptions.h`: six option meanings/defaults.
- `include/gpu/GrDirectContext.h`: healthy-host versus lost-context abandonment.

GPU diagnostics and GL/GLES/interface helpers remain stage 0.77c. This stage does
not alter the accepted 0.77a process-global cache or memory-statistics contract.
