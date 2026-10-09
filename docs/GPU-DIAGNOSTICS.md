# GPU diagnostics and GL interface selection — 0.77c

Numeric package version: `0.77`. Native baseline: SkiaSharp 3.119.1 / m119.0.
This stage adds no compiler, native helper library, worker, GUI initialization,
or implicit pixel transfer. GPU diagnostics are exported by `gpu-diagnostics.rkt`
and re-exported by `gpu.rkt` (not the CPU `main.rkt` facade).

## Context-local memory reports

```racket
(gpu-memory-statistics context
                       #:detailed? [detailed? #f]
                       #:dump-wrapped? [wrapped? #f]
                       #:max-entries [max-entries 4096]
                       #:string-limit [string-limit 4096]
                       #:byte-limit [byte-limit 1048576])
```

The context must belong to the calling Racket thread and have a matching active
`call-with-gpu-context` scope. Closed, abandoned, shutdown-requested, wrong-owner,
wrong-host-current and inactive contexts are rejected before native capture.
The native abandonment flag is checked too. GPU loss requests domain shutdown;
this does not pretend to restore the lost host.

The result is a `memory-statistics?` value. The 0.77a accessors continue to work:

```racket
(memory-statistics-scope report)
(memory-statistics-entries report)
(memory-statistics-detailed? report)
(memory-statistics-dump-wrapped? report)
(memory-statistics-truncated? report)
(memory-statistics-dropped-count report)
(memory-statistics-string-bytes report)
(memory-statistics->jsexpr report)

(memory-statistic-kind entry)
(memory-statistic-name entry)
(memory-statistic-value-name entry)
(memory-statistic-units entry)
(memory-statistic-value entry)
```

Those accessors are available from `graphics.rkt` and `main.rkt`. Numeric records
contain exact unsigned 64-bit values. String records contain immutable copied
strings; the entries vector is immutable. No borrowed native pointer or
closeable context wrapper enters the report. Saved reports remain usable after
later rendering, purges, garbage collection and context closure.

**Scopes are distinct.** Global `skia-memory-statistics` retains
`process-global-skia-caches`; a GPU report has `gpu-context-skia-resources`.
`memory-statistics->jsexpr` preserves that distinction. Capture `gpu-context-info`
alongside a report when storing diagnostic evidence for several contexts.

## Limits and interpretation

Entry and per-string caps must be exact nonnegative integers at most 65,536.
The combined record/string allocation budget is also constrained by
`current-skia-byte-limit`. Native strings are bounded before copying.

Limits omit *whole records*: no shortened resource names or truncated numeric
values are published. `truncated?` and `dropped-count` explicitly disclose
omissions. Zero entry, string, or byte limits are useful to exercise bounded
capture; they are not a statement that native resources consume zero bytes.

The dump is Skia's reported resource accounting, not physical driver allocation,
VRAM pressure, process RSS, or a complete ownership graph. In particular:

- `gpu-cache-info` reports the **budgeted** resource cache; a memory dump may
  include other cached resources, including wrapped resources when requested.
- Native fields such as `size` and `purgeable_size` can describe the same bytes.
  This API deliberately does not add them into an invented memory total.
- Neither the dump nor a combination of separate queries is an atomic joint
  snapshot of all native activity. There is no hard allocation-cap guarantee.

The pinned managed trace adapter forwards numeric and string records only. The
full C++ tracing interface also has backing/ownership hooks that are not exposed
by this adapter; those relationships are not synthesized by this binding.

## Capture execution and safety

The existing 0.77a collector and its process-global callback table are reused.
No second provider is installed. Callbacks run synchronously in atomic mode and
only copy bounded memory into private data. They perform no port I/O, waiting,
application callback, or nested Skia call. Errors are saved and raised only after
the native dump has returned and the temporary managed object has been deleted.

As with 0.77a, native diagnostic calls reject live-port callback execution and
active live-stream operations. This avoids waiting on native cache locks while
the Racket thread is needed to service a foreign stream callback. Reading an
already detached report is unrestricted by those native-operation guards.

One trace provider/module/place per process is supported. A foreign component
must not replace Skia's managed trace callback table. The separate live-stream
and incremental-input callback provider is not replaced or reconfigured.

**Diagnostics do not flush, submit, wait for GPU completion, upload, read back
pixels, or change cache limits.** To diagnose a completed workload, request the
completion boundary explicitly before capturing. The test harness does exactly
that, then records an empty I/O ledger around each diagnostic operation.

## GL interface choice at construction

```racket
(make-gpu-context provider
                  #:options [options #f]
                  #:gl-interface [mode 'default])

(make-egl-gpu-context #:options [options #f]
                      #:gl-interface [mode 'default])
```

All existing options and backend keywords remain available. `#:gl-interface`
accepts:

| Mode | Factory / behavior |
| --- | --- |
| `default` | Existing native-first behavior, with desktop assembly fallback. EGL always bypasses the native GLX factory and uses its supplied resolver. |
| `auto` | Pinned `gr_glinterface_assemble_interface`, detecting the current host's standard. |
| `desktop` | Explicit `gr_glinterface_assemble_gl_interface`. |
| `gles` | Explicit `gr_glinterface_assemble_gles_interface`, only with a matching host. |
| `webgl` | Explicit `gr_glinterface_assemble_webgl_interface`, subject to native WebGL build support and a matching host. |

Selecting a mode does **not** create or convert the host context. Except for the
preserved native default path, the provider must supply a nonblocking,
atomic-safe `#:get-proc-address` resolver for an already-current native host.
Resolver callbacks must not perform port I/O or call arbitrary drawing code.
Their native-facing exceptions, including a raised `#f`, are caught; native
assembly returns before the error is re-raised and any returned interface freed.

Before assembly, the binding reads a bounded `GL_VERSION` string through the
provider and classifies it using the pinned native categories. An explicit GLES
or WebGL request on a desktop host is rejected **before** assembly; it cannot
silently build a table with the wrong standard. Unrecognized standards and null
factory results raise `exn:fail:gpu:unavailable`. An explicit route never falls
back to a different standard.

**Owned EGL remains desktop OpenGL.** It accepts `default`, `auto` and `desktop`;
GLES/WebGL requests are rejected before loading the platform. An external host
can use the generic provider route with a matching standard. This stage does not
add an EGL ES host factory, a browser host, or browser presentation support.
The pinned WebGL implementation is conditional on `SK_USE_WEBGL`; a desktop
binary can export its constructor while returning null unconditionally. A symbol
is not evidence of a usable WebGL backend.

Metal and Direct3D accept the omitted/default keyword but reject explicit GL
interface selection. Their existing default/options factories are unchanged.

## Querying the retained interface

```racket
(gpu-gl-interface-info context)
(gpu-gl-has-extension? context "GL_ARB_framebuffer_object")
```

These require a matching active **OpenGL** context. They reject non-GL backends,
expired contexts, and mismatched owners/scopes rather than returning an
ambiguous false. Extension names must be ASCII identifiers of 1–255 characters,
beginning with a letter and containing only letters, digits, and underscores.
Spaces, NULs and lists of several extensions are rejected. Unknown well-formed
names return `#f`.

`gpu-gl-interface-info` returns a detached immutable hash:

```racket
#hasheq((requested . "auto")
        (factory . "assembled-auto")
        (validated . #t)
        (extension_source . "context-owned-skia-interface"))
```

Each GL driver now retains the **actual interface supplied to native context
creation**, instead of reconstructing a possibly different interface at query
time. It releases its reference after the native context reference, including
constructor-description failure and final closure of an abandoned domain.
Existing 0.77b resource-release/abandon semantics remain unchanged.

Extension membership describes that validated input interface. Skia may apply
additional internal workarounds or disable an extension-based implementation;
membership alone does not guarantee that a particular rendering operation uses
that extension or is supported. The requested mode and selected factory are
configuration provenance, not an effective-feature readback.

## Example and acceptance

`examples/gpu-diagnostics.rkt` creates the explicitly selected backend, draws a
small surface, submits with an explicit completion request, and prints context,
budgeted-cache and bounded-memory diagnostics. It uses public APIs only.

```bash
python tools/validate-gpu-diagnostics.py \
  --racket "$RACKET" --require-gpu --backend metal
```

Use `--backend egl` on Linux or `--backend direct3d --adapter warp` for Windows
software acceptance. No document renderer is required. Global regressions are
`full` by default; `--regressions none` still runs all focused tests, the example,
the selected GPU harness, and independent inspection.

The suite contains 38 native-free tests, 13 real symbol/callback tests (without a
GPU context), and 20 selected-GPU cases. The native-only collector tests use an
explicitly identified global dump; only the selected GPU harness supplies GPU
memory evidence. It checks real allocated resource sizes, bounded omissions,
unchanged cache limits/pixels, immutable detached results, guard failures,
retained GL extension queries and teardown. Linux compares extension membership
with an independent indexed host GL query and renders default/auto/desktop
assembly paths. GLES/WebGL mismatch and null-factory tests are **not positive
GLES/WebGL rendering evidence**.

The existing `gpu-context-controls.yml` runs diagnostics after controls with
`--regressions none`, retains both artifacts, and remains under `Acceptance
required`. No new automatic top-level workflow is added. Required hosted GPU
execution is Linux EGL and Windows WARP; selected Metal execution is a separate
local validation. CPU installed-package lanes also run the native-only suite.

## Pinned implementation references

- `mono/skia`, revision `40f75dc0051d141913c07c20d4c19590c7da0cb7`,
  `include/c/gr_context.h` and `src/c/gr_context.cpp`: C signatures and factories.
- Same revision, `src/gpu/ganesh/GrGpuResource.cpp`: resource records and
  overlapping `size` / `purgeable_size` semantics.
- Same revision, `src/gpu/ganesh/gl/GrGLUtil.cpp` and
  `GrGLAssembleInterface.cpp`: version classification and automatic assembly.
- Same revision, `GrGLAssembleGLESInterfaceAutogen.cpp` and
  `GrGLAssembleWebGLInterfaceAutogen.cpp`: explicit standard/build restrictions.
- Existing `docs/GLOBAL-CACHES.md` and `docs/GPU-CONTEXT-CONTROLS.md`: retained
  global collector and 0.77b lifetime/configuration contracts.
