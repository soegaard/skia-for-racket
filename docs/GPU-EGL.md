# EGL contexts without a window system

Import `skia/gpu-egl` together with `skia` and `skia/gpu`.
Importing `gpu-egl` does not load EGL,
OpenGL, or a GUI; construction loads the native adapter explicitly.

```racket
(require skia skia/gpu skia/gpu-egl)
(define context (make-egl-gpu-context))
```

The result is the existing `gpu-context?`, with backend `opengl`. Its provider
is `egl-owned`, not GLX, and its surfaces, images, drawing operations, explicit
transfers, context affinity, and close guards are the ordinary GPU interfaces.
`make-surface` remains a CPU constructor. The GUI widgets and Metal constructor
are unchanged.

## Owned construction

```racket
(make-egl-gpu-context
  #:platform [platform 'surfaceless]
  #:device-index [device-index 0]
  #:surface [surface 'surfaceless])
```

The built-in adapter targets Linux, a matching pinned SkiaSharp library, and
**desktop OpenGL 3.3 or newer**. OpenGL ES is not selected. Missing libraries,
extensions, matching configurations, context creation, or Ganesh support fail
explicitly. A successful library/symbol lookup is not proof of rendering.
There is no automatic GUI, Xvfb, GLX, pbuffer, different-device, or CPU fallback.

`platform` is `surfaceless` or `device`. The first requests
`EGL_MESA_platform_surfaceless`, which is independent of a native window
system. The second requests `EGL_EXT_platform_device` and selects the given
nonnegative enumeration index through `eglQueryDevicesEXT`. An enumeration
index is a selection for this process/run, not a persistent physical-device
identifier. A nonzero index with the surfaceless platform is rejected.

`surface` is `surfaceless` or `pbuffer`. Surfaceless activation passes
`EGL_NO_SURFACE` for draw and read; it requires the corresponding EGL 1.5/core
or extension capability. There is no usable default framebuffer in this mode:
render into a GPU surface or an explicitly borrowed nonzero framebuffer.
The pbuffer option explicitly requests a one-by-one EGL pbuffer as the context's
binding surface. That pbuffer is not the image render target and is not a
native window. Selecting it does not change the chosen EGL platform.

```racket
(define context
  (make-egl-gpu-context #:platform 'device #:device-index 0 #:surface 'pbuffer))
```

The adapter assembles Skia's GL interface using the EGL procedure resolver;
it does not try Skia's platform-native GLX interface first. Driver strings and
queried limits are preserved in `gpu-context-info`. Software drivers remain
labelled `software`; the package does not set `LIBGL_ALWAYS_SOFTWARE` or turn
that classification into a hardware claim.

## Ownership and execution

An owned context is created, used, and closed on its creating Racket thread.
Independent EGL activations are serialized within the adapter, including when
an application callback yields. Nested activation of the same GPU domain uses
the existing inner lease rule instead of rebinding EGL. Do not synchronously wait for another
EGL activation while holding one; that other activation must wait for the
current scope to return. The adapter preserves
the previously current desktop-GL context, draw/read surfaces, and bound EGL
client API. It never calls `eglReleaseThread`, which would discard other
client-API state.

Closing a context first drains its queued Skia references and destroys Ganesh,
then unbinds/destroys its owned EGL context and optional pbuffer. The previous
foreign binding is restored independently. Live GPU children still prevent
normal closure. Abandonment invalidates use but does not retire child wrappers;
close those wrappers and drain them on the owner before closing the domain.
GC/custodian callbacks request/queue cleanup, never destroy EGL objects on a
finalizer thread. A failed, indeterminate native teardown is not retried.

`eglInitialize`/`eglTerminate` are not treated as a per-context reference count.
The adapter keeps one initialization record per native display handle and
terminates only after its last owned context closes. It rejects a display
already initialized outside that registry, even when no context is current.
Do not race external initialization or termination against owned construction.
The checks cannot coordinate arbitrary third-party native code: the caller
must give this adapter exclusive lifetime control of its owned display.
Use a borrowed current provider when another library owns that lifetime.

The native initialization registry is deliberately restricted to **one adapter
module instance/place per process**. A process-global, non-GC one-byte token
claims that registry for the process lifetime. It is not reclaimed at context
closure and is not an EGL/GPU allocation. A second independent namespace/place
instance fails explicitly; use separate processes for independent EGL workers.
This restriction avoids independently terminating the same process-wide native
display from unrelated Racket registries.

## Borrowing a current EGL host

```racket
(make-current-egl-gpu-provider) ; -> gpu-provider?
```

Call this while the host has bound the desktop OpenGL API and made its EGL
context and surfaces current. Then use the returned provider with the existing
constructor:

```racket
(define provider (make-current-egl-gpu-provider))
(define context (make-gpu-context provider))
```

Capture and GPU construction must be on the intended owner thread. Construction
must be outside another GPU execution scope. The provider saves and restores
native binding state on each activation. It does not initialize/terminate the
display, create/destroy the context, or own either surface. Closing Ganesh does
not destroy any of those host objects. The host must keep all captured objects
valid until its GPU domain has closed and must not mutate their native-current
state while the package is drawing. Re-capturing a package-owned context as a
second Ganesh domain is rejected.

This is the integration route for an **existing host-managed EGL/Wayland
context**. It does not create a Wayland connection, `wl_surface`, EGL window
surface, event loop, or Wayland presenter. Capturing a provider conservatively
makes no headless/display-server-free claim about the external host.

## Native contracts and validation

The relevant specifications are
[EGL_MESA_platform_surfaceless](https://registry.khronos.org/EGL/extensions/MESA/EGL_MESA_platform_surfaceless.txt),
[EGL_EXT_platform_device](https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_platform_device.txt),
and [EGL_KHR_surfaceless_context](https://registry.khronos.org/EGL/extensions/KHR/EGL_KHR_surfaceless_context.txt).
The process registry uses Racket's
[process-global registration](https://docs.racket-lang.org/foreign/unsafe-global.html).

See [headless and interop validation](GPU-HEADLESS-TESTING.md). A complete gate
requires actual Racket/Ganesh rendering with `DISPLAY` and `WAYLAND_DISPLAY`
absent, not merely a native EGL initialization probe.
