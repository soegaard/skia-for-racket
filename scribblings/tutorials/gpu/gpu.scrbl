#lang scribble/manual

@(require "../support/reader.rkt")

@title{GPU Rendering — Render the Same Scene on the GPU}

@(require racket/file
          racket/runtime-path
          "eval.rkt"
          (for-label racket
                     skia
                     skia/gpu
                     skia/gpu-egl
                     skia/gpu-racket-gl
                     (only-in racket/gui/base canvas%)))

@(define-runtime-path scene-source "scene.rkt")
@(define-runtime-path linux-source "linux-opengl.rkt")

@section{The Finished Comparison}

@(gpu-comparison-pict)

Both pictures come from the same @racket[draw-scene] function. The left picture
uses a CPU raster surface. The right one was rendered with Metal on macOS and
read back into an ordinary image. Both are 760 by 420 pixels before display
scaling.

They are supposed to look alike. Different backends can produce small pixel
differences; this comparison is not a test of byte-for-byte equality or speed.

@centered{@bold{Keep the drawing function. Change the surface backing.}}

@tutorial-entry["gpu"]

@section{Why Use the GPU?}

For a small diagram or an occasional PNG, CPU rendering is usually simpler.
Creating a GPU context and transferring its output back to the CPU takes work.
The one-shot helper used here performs both operations for every image, so it
is not automatically faster than drawing on the CPU.

A GPU becomes more useful when an application draws repeatedly, displays
frames in a GPU-backed window, or reuses GPU-resident images, shaders, and
effects without reading intermediate results back into CPU memory. A complex
scene may also benefit, depending on the hardware and workload.

@verbatim{
One-off PNG:
  CPU:       draw -> encode
  GPU:       create context -> draw -> read back -> encode

Repeated frames:
  GPU:       create context once -> draw / present many frames -> close
}

For a static PNG, start with the CPU. For sustained rendering, consider a
persistent GPU context and measure the complete workflow, including any
readbacks. If the goal is a vector PDF or SVG, use the document-output API
from @tutorial-link["pdf-svg"]: a GPU-rendered image is still raster content.

@section{Keep the Drawing Function}

The shared @filepath{scene.rkt} file requires only @racketmodname[skia]. It
draws a background, a grid, an orbit, and three glowing nodes. Load it with
the drawing API and the GPU helper:

@racketblock[
(require skia
         skia/gpu
         "scene.rkt")
]

Inside @filepath{scene.rkt}, the drawing function has this shape:

@racketblock[
(define (draw-scene canvas)
  (draw-background canvas)
  (draw-grid canvas)
  (draw-orbit canvas)
  (draw-nodes canvas)
  (draw-center canvas))
]

The file already provides @racket[draw-scene]; the definition above is an
excerpt, not another definition to paste after the @racket[require] form.
The complete source appears at the end of this tutorial.

A canvas carries drawing state. The function does not need to know whether
the surface behind it is backed by CPU or GPU storage.

@section{Render the Scene on the CPU}

First, create an ordinary surface and draw into its canvas:

@gpu-racketblock+eval[
(define cpu-surface
  (make-surface scene-width scene-height
                #:background scene-background))
(draw-scene (surface-canvas cpu-surface))
]

The surface reports its execution backing:

@gpu-interaction[(surface-backend cpu-surface)]

The result is @racket['raster]. Make an image snapshot of the CPU surface:

@gpu-racketblock+eval[
(define cpu-image (surface-snapshot cpu-surface))
]

The normal image encoder can then save it as a PNG:

@racketblock[
(save-image cpu-image "scene-cpu.png" 'png #:exists 'replace)
]

@section{Choosing a Backend on Your Platform}

The same drawing function can use different GPU backends. The examples below
all use @racket[scene-width], @racket[scene-height], @racket[scene-background],
and @racket[draw-scene] from @filepath{scene.rkt}.

@subsection{macOS: Metal}

On macOS, the one-shot helper can create its own Metal context. Only the
rendering call changes:

@racketblock[
(define metal-image
  (render-gpu->raster-image
   scene-width scene-height draw-scene
   #:backend 'metal
   #:background scene-background))
]

@(gpu-metal-reference-pict #:scale 0.72)

The figure is the Metal result, displayed at 72 percent of its natural size.
The helper returns a CPU-owned image; it has already closed the GPU surface
and context. Save the result with the ordinary image encoder:

@racketblock[
(save-image metal-image "scene-metal.png" 'png #:exists 'replace)
]

No separate GPU activation or submission is needed for this one-shot call.
An unavailable Metal backend raises an exception; it does not silently switch
to CPU rendering.

@subsection{Windows: Direct3D}

On Windows, the same helper uses Direct3D 12:

@racketblock[
(define windows-image
  (render-gpu->raster-image
   scene-width scene-height draw-scene
   #:backend 'direct3d
   #:background scene-background))
]

The default adapter selection is @racket['hardware]. For a deliberately
software-rendered Direct3D test, add @racket[#:adapter 'warp]. WARP is not
hardware acceleration, and the helper never falls back to it automatically.

@subsection{Linux: OpenGL}

On Linux, choose @racket['opengl], but the one-shot helper needs an existing
OpenGL @emph{provider}. Unlike the Metal and Direct3D paths, it cannot create
an OpenGL host by itself. The complete runnable GUI example in
@secref["linux-opengl-host"] shows how a Racket @racket[canvas%] provides a
live context and how @racket[make-racket-gl-provider] wraps it.

A headless Linux application can instead create an owned OpenGL context using
@racket[make-egl-gpu-context] from @racketmodname[skia/gpu-egl]. That is a
@racket[gpu-context?], not a provider accepted by this one-shot helper. Use
the lower-level GPU drawing/readback API for that route; see
@filepath{docs/GPU-EGL.md} and @filepath{examples/gpu-headless.rkt}.

@section{What the Helper Manages}

The @racket[render-gpu->raster-image] function carries out one complete render:

@verbatim{
Create a GPU context
    -> activate it and create a GPU surface
    -> call draw-scene with the surface's canvas
    -> synchronously read back the pixels
    -> close the GPU surface and context
    -> return an independent CPU image
}

The drawing function receives a borrowed canvas. Use it during the callback;
do not save it for later. The helper handles activation, cleanup, and readback.
Readback already completes the GPU work required for the CPU image, so there
is no need to call @racket[gpu-flush-and-submit!] before it.

The returned image can be saved again without involving a GPU. If drawing or
readback fails, the helper does not return a partial image. GPU setup and
teardown errors are reported instead of becoming successful CPU fallbacks.

@section{When One Shot Is Not Enough}

The helper is a convenient way to render an occasional GPU image. Calling it
for every animation frame repeatedly creates and closes contexts and copies
pixels back to the CPU. That often defeats the point of GPU rendering.

For repeated rendering, create a context once with @racket[make-gpu-context],
activate it with @racket[call-with-gpu-context], and reuse GPU surfaces and
images across frames. The @racket[gpu-surface-snapshot] function can keep an
image GPU-resident for later drawing. The lower-level
@racket[gpu-surface->raster-image] function is available when a CPU copy is
actually needed. The @api-link[] specifies the corresponding resource lifetimes.

@section[#:tag "linux-opengl-host"]{Linux: A Complete OpenGL Host Example}

Save this program as @filepath{linux-opengl.rkt} alongside @filepath{scene.rkt}.
It runs in a Linux graphical session with a working OpenGL/GLX context. The
small Racket GUI window supplies the OpenGL host; Skia draws into a separate
760-by-420 offscreen GPU surface.

@codeblock[(file->string linux-source)]

The @racket[gl-provider] value borrows @racket[gl-context]; it cannot create
an OpenGL context on its own. Keep the frame, canvas, and context alive until
after @racket[render-gpu->raster-image] returns. The helper closes its Skia
context but does not destroy the GUI host. The program hides the host window
when rendering finishes or raises an exception. The short @racket[sleep/yield]
allows a GUI event cycle before the context check; the check still fails
explicitly if an OpenGL host is unavailable.

This particular route requires a graphical session with GLX (for example, X11
or XWayland). It is not a portable headless Linux recipe. Drivers, extensions,
and usable GPU support must be checked at runtime.

@section[#:tag "try-it"]{Try It}

Try moving one of the glowing nodes in @filepath{scene.rkt}. Render the scene
on the CPU and GPU again. The two images should reflect the same change.

Try adding a rectangle to @racket[draw-scene]. Nothing in the drawing function
should need to change between CPU and GPU execution.

Try saving @racket[metal-image] a second time. The encoder uses CPU pixels;
there is no new GPU context or readback.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now use one drawing function with CPU and GPU surfaces and keep a CPU image
after GPU readback. A window that draws repeatedly should retain its renderer across frames.

@tutorial-next["gpu"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["gpu"]

Here is the full @filepath{scene.rkt} program. It requires only
@racketmodname[skia], so the CPU and GPU examples use exactly these functions.


@codeblock[(file->string scene-source)]
