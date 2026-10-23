#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title[#:style (tutorial-feedback-style)]{GPU Rendering — Render the Same Scene on the GPU}
@(tutorial-navigation "gpu")

@(require racket/file
          racket/runtime-path
          "eval.rkt"
          (for-label racket
                     skia
                     skia/gpu
                     skia/gpu-egl
                     skia/gpu-racket-gl
                     skia/dc skia/gpu-dc
                     (only-in racket/gui/base canvas%)))

@(define-runtime-path scene-source "scene.rkt")
@(define-runtime-path linux-source "linux-opengl.rkt")

@section[#:tag "finished-result"]{The Finished Comparison}

@(tutorial-figure
 (string-append
  "The same 760 by 420 scene appears on the CPU at left and after Metal rendering and "
  "readback at right.")
 (gpu-comparison-pict))

Both pictures come from the same @racket[draw-scene] function. The left picture
uses a CPU raster surface. The right one was rendered with Metal on macOS and
read back into an ordinary image. Both are 760 by 420 pixels before display
scaling.

The geometry should match, although backends can differ in individual pixels.
The comparison shows appearance, not rendering speed.

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

Measure the complete workflow, including readbacks, when choosing a renderer.
For vector PDF or SVG, use @tutorial-link["pdf-svg"] instead: a GPU-rendered image
is still raster content.

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

@(tutorial-figure
 "The Metal-rendered scene after CPU readback, displayed at 72 percent of its natural size."
 (gpu-metal-reference-pict #:scale 0.72))

The figure is the Metal result, displayed at 72 percent of its natural size.
The helper returns a CPU-owned image; it has already closed the GPU surface
and context. Save the result with the ordinary image encoder:

@racketblock[
(save-image metal-image "scene-metal.png" 'png #:exists 'replace)
]

No separate GPU activation or submission is needed for this one-shot call.

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

A headless Linux application can instead call @racket[make-egl-gpu-context]
from @racketmodname[skia/gpu-egl]. It returns an owned GPU context, recognized by
@racket[gpu-context?], not an OpenGL provider for this one-shot helper. The
@api-link[] describes the lower-level drawing and readback operations for an
owned context.

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

For an animation, keep the GPU context and images between frames rather than
calling the one-shot helper for each frame.

For several operations within one computation, use
@racket[call-with-new-gpu-context]. Supply a constructor callback and a drawing
callback; the context is activated for drawing and closed after that callback
exits. Close child resources inside the callback with @racket[with-skia]:

@racketblock[
(call-with-new-gpu-context
 (lambda () (make-gpu-context #:backend 'metal))
 (lambda (context)
   (with-skia ([surface (make-gpu-surface context 760 420)])
     (draw-scene (surface-canvas surface))
     (gpu-surface->raster-image surface))))
]

This example requires Metal on macOS. On headless Linux, the constructor callback
can instead call @racket[make-egl-gpu-context]. The returned CPU image has its
own lifetime; close it after saving or otherwise using it.

For repeated rendering across separate callbacks, create a context once with @racket[make-gpu-context],
activate it with @racket[call-with-gpu-context], and reuse GPU surfaces and
images across frames. The @racket[gpu-surface-snapshot] function can keep an
image GPU-resident for later drawing. The lower-level
@racket[gpu-surface->raster-image] function is available when a CPU copy is
actually needed. The @api-link[] specifies the corresponding resource lifetimes.

@subsection{Reusing Racket Draw Code}

Code written for Racket's drawing-context methods can use @racket[call-with-skia-dc]
for a scoped CPU target, @racket[call-with-gpu-surface-dc] for an existing GPU
surface, or @racket[call-with-gpu-frame-dc] for a presenter frame. All three
default to smoothed drawing and close their temporary DC when the callback
exits. A GPU surface supplied by the caller remains open.

GPU DCs already scale logical coordinates to the target's physical pixels.
Their @tt{get-backing-scale} reports the larger pixel density of the two axes;
@tt{get-device-scale} reports the remaining X/Y factors. Multiply the backing
scale by the corresponding device scale when locating a physical pixel, but
do not apply those scales again to drawing commands.

Both @racket[make-gpu-surface] and @racket[call-with-gpu-frame-dc] accept
@racket[#:color-space 'srgb], @racket[#:color-space 'linear-srgb], ICC bytes, an
open color-space resource, or @racket[#f] for no color-space tag. Profile bytes
are copied; supplying a resource does not transfer its ownership.

@section[#:tag "linux-opengl-host"]{Linux: A Complete OpenGL Host Example}

Save this program as @filepath{linux-opengl.rkt} alongside @filepath{scene.rkt}.
It needs a Linux graphical session with OpenGL/GLX, such as X11 or XWayland;
this is not a headless recipe. The small window supplies the OpenGL host, while
Skia draws into a separate 760-by-420 offscreen GPU surface.

@codeblock[(file->string linux-source)]

The @racket[gl-provider] value borrows @racket[gl-context]; it cannot create
an OpenGL context on its own. Keep the frame, canvas, and context alive until
after @racket[render-gpu->raster-image] returns. The helper closes its Skia
context but does not destroy the GUI host. The program hides the host window
when rendering finishes or raises an exception. The short @racket[sleep/yield]
allows a GUI event cycle before the context check; the check still fails
explicitly if an OpenGL host is unavailable.

@section[#:tag "try-it"]{Try It}

Try moving one of the glowing nodes in @filepath{scene.rkt}. Render the scene
on the CPU and GPU again. The two images should reflect the same change.

Try adding a rectangle to @racket[draw-scene]. Nothing in the drawing function
should need to change between CPU and GPU execution.

Try saving the CPU-owned image returned by your chosen backend a second time.
In the platform snippets, use @racket[metal-image] on macOS or
@racket[windows-image] on Windows. In @filepath{linux-opengl.rkt}, add another
save immediately after the existing @racket[save-image] call, while
@racket[linux-image] is in scope. For example, the Linux call is:

@racketblock[
(save-image linux-image "scene-opengl-again.png" 'png #:exists 'replace)
]

Each additional save uses the already returned CPU pixels. It creates no new
GPU context and performs no further readback.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now use one drawing function with CPU and GPU surfaces and keep a CPU image
after GPU readback. A window that draws repeatedly should retain its renderer across frames.

@tutorial-next["gpu"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["gpu"]

Here is the full @filepath{scene.rkt} program. It requires only
@racketmodname[skia], so the CPU and GPU examples use exactly these functions.

@codeblock[(file->string scene-source)]
