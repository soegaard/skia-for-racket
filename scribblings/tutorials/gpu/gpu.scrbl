#lang scribble/manual

@title{GPU Rendering — Render the Same Scene on the GPU}

@(require "eval.rkt"
          (for-label racket
                     skia
                     skia/gpu))

@section{The Finished Comparison}

@(gpu-comparison-pict)

The two pictures use the same @racket[draw-scene] function. The left picture is
rendered on a normal CPU surface while the documentation is built. The right
picture is a checked-in PNG produced by the offscreen Metal renderer on macOS.

If @filepath{metal-reference.png} has not been generated yet, the right side
shows an explicit placeholder instead.

The main idea is:

@centered{@bold{The drawing API can stay the same while the surface changes
from CPU-backed to GPU-backed. GPU execution and CPU readback remain explicit.}}

The two routes are:

@verbatim{
CPU:
  make-surface
      -> surface-canvas
      -> draw-scene
      -> CPU pixels

Metal:
  make-gpu-context
      -> call-with-gpu-context
      -> make-gpu-surface
      -> surface-canvas
      -> draw-scene
      -> gpu-surface->raster-image
      -> CPU image
}

Most of the drawing code is shared. The GPU route adds context activation,
GPU-target lifetime rules, and an explicit transfer when pixels must return to
the CPU.

@section{Keep the Scene Backend-Neutral}

The scene in @filepath{scene.rkt} requires only @racketmodname[skia]. It does
not import @racketmodname[skia/gpu].

The scene is 760 by 420 drawing units:

@racketblock[
(define scene-width 760)
(define scene-height 420)
(define scene-background "#0B1024")
]

Its top-level drawing function receives only a canvas:

@racketblock[
(define (draw-scene canvas)
  (draw-background canvas)
  (draw-grid canvas)
  (draw-orbit canvas)
  (draw-nodes canvas)
  (draw-center canvas))
]

The helpers use ordinary gradients, paths, lines, ovals, and circles. Nothing in
@racket[draw-scene] asks how the canvas is backed.

That is the reuse boundary for this tutorial.

@section{Render the CPU Route}

An ordinary surface gives us the CPU version:

@gpu-racketblock+eval[
(define cpu-surface
  (make-surface
   scene-width scene-height
   #:background scene-background))

(define cpu-canvas
  (surface-canvas cpu-surface))

(draw-scene cpu-canvas)
]

The surface reports its backing kind:

@gpu-interaction[
(surface-backend cpu-surface)
]

The result is @racket['raster].

The left side of the opening comparison is generated from this route every time
the manual is built. It is executable documentation rather than a screenshot.

@section{Import the GPU Operations}

The Metal route needs the GPU resource API:

@racketblock[
(require skia
         skia/gpu)
]

The ordinary drawing functions still come from @racketmodname[skia]. The GPU
module adds context, activation, GPU-surface, submission, and transfer
operations.

Requiring @racketmodname[skia/gpu] does not create a GPU context or a window.

@section{Create and Activate a Metal Context}

On compatible 64-bit macOS systems, an owned offscreen Metal context is created
with:

@racketblock[
(define context
  (make-gpu-context #:backend 'metal))
]

The constructor does not silently fall back to OpenGL or CPU rendering.
Unsupported Metal configuration raises an exception.

GPU work then runs inside a matching activation:

@racketblock[
(call-with-gpu-context
 context
 (lambda ()
   ...))
]

The context is an execution domain. It is not a second set of drawing
functions.

@section{Change the Surface, Not the Scene}

Inside the activation, create a GPU-backed surface and obtain its canvas:

@racketblock[
(with-skia
    ([surface
      (make-gpu-surface
       context
       scene-width scene-height
       #:background scene-background)])
  (define canvas
    (surface-canvas surface))

  (draw-scene canvas)

  ...)
]

The important line is still:

@racketblock[
(draw-scene canvas)
]

The GPU surface is deterministic-lifetime code. It must be closed before its
context is closed, so @racket[with-skia] is appropriate here.

A GPU canvas is also activation-scoped. Do not save @racket[canvas] and use it
after @racket[call-with-gpu-context] returns. Obtain a fresh canvas in a later
activation.

@section{Verify the Execution Backend}

The standalone generator checks more than the requested constructor.

The context itself must report Metal:

@racketblock[
(eq? (gpu-context-backend context)
     'metal)
]

Inside the active scope, both the surface backing and the live canvas execution
backend must also report Metal:

@racketblock[
(and
 (eq? (surface-backend surface)
      'metal)
 (eq? (canvas-execution-backend canvas)
      'metal))
]

The generator raises an exception if those checks fail. This makes the static
reference image harder to confuse with a CPU rendering produced by the same
scene.

The checks establish which Skia backend was used for the target. They are not
a benchmark or a claim about a particular physical GPU model.

@section{Submission and Readback Are Different}

A GPU application does not have to bring pixels back to the CPU after every
draw.

When later work will remain on the GPU, pending commands can be flushed and
submitted explicitly:

@racketblock[
(gpu-flush-and-submit! context)
]

That is a GPU execution boundary. It does not create a CPU image.

This tutorial needs a PNG file, so it uses a different operation:

@racketblock[
(define image
  (gpu-surface->raster-image surface))
]

The @racket[gpu-surface->raster-image] function performs an explicit
synchronous readback and returns a CPU-owned image.

The distinction is:

@verbatim{
stay on GPU:
  GPU surface
      -> flush / submit
      -> later GPU work

return to CPU:
  GPU surface
      -> gpu-surface->raster-image
      -> detached CPU image
      -> ordinary image encoder
}

Readback already waits for the required GPU work. The complete example does not
need a separate @racket[gpu-flush-and-submit!] immediately before the transfer.

@section{Detach Before Closing the Context}

The CPU image returned by @racket[gpu-surface->raster-image] no longer depends
on the GPU context.

The complete renderer therefore uses this lifetime order:

@itemlist[
 @item{Create the GPU context.}
 @item{Activate the context.}
 @item{Create and draw the GPU surface.}
 @item{Read the surface back into a detached CPU image.}
 @item{Close the GPU surface before leaving the activation.}
 @item{Close the GPU context.}
 @item{Encode the detached CPU image.}
]

The context is protected with @racket[dynamic-wind] so teardown also happens
when drawing or readback raises an exception:

@racketblock[
(define context
  (make-gpu-context #:backend 'metal))

(define detached-image
  (dynamic-wind
    void
    (lambda ()
      (call-with-gpu-context
       context
       (lambda ()
         (with-skia
             ([surface
               (make-gpu-surface
                context
                scene-width scene-height
                #:background scene-background)])
           (define canvas
             (surface-canvas surface))
           (draw-scene canvas)
           (gpu-surface->raster-image
            surface)))))
    (lambda ()
      (gpu-context-close! context))))
]

A GPU context uses @racket[gpu-context-close!], not @racket[skia-close!].

After the context has closed, the detached image can use the ordinary encoder:

@racketblock[
(save-image detached-image
            "gpu-metal.png"
            'png
            #:exists 'replace)
]

@section{Keep the Manual Portable}

The manual should build on systems that do not provide Metal. The Scribble
evaluator therefore runs only the CPU route.

The Metal result is generated separately on macOS and checked into the
repository as:

@filepath{scribblings/tutorials/gpu/figures/metal-reference.png}

From the repository root, generate it with:

@verbatim{
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" scribblings/tutorials/gpu/gpu-offscreen.rkt \
  scribblings/tutorials/gpu/figures/metal-reference.png

python3 tools/update-source-sums.py
python3 tools/update-source-sums.py --check
}

The generation program uses the same @racket[draw-scene] function and verifies
that its context, surface, and live canvas all report the Metal backend.

Once the PNG is checked in, Linux and Windows documentation builds can display
that actual Metal result without initializing Metal themselves.

The placeholder exists only so the source manual remains buildable before the
reference image has been generated.

@section{GPU Snapshot or CPU Detachment?}

A GPU surface has two useful image routes.

The @racket[gpu-surface-snapshot] function returns a GPU-resident image:

@racketblock[
(define gpu-image
  (gpu-surface-snapshot surface))
]

That image remains tied to the same GPU context. It is useful when later
shaders, filters, or drawings continue on that context.

The @racket[gpu-surface->raster-image] function instead returns an independent
CPU image:

@racketblock[
(define cpu-image
  (gpu-surface->raster-image surface))
]

The difference is:

@verbatim{
gpu-surface-snapshot
    -> GPU image
    -> stays context-bound

gpu-surface->raster-image
    -> CPU image
    -> can outlive the GPU context
}

The tutorial chooses CPU detachment because its final artifact is a PNG file.

@section{The Complete Renderer}

The complete @filepath{gpu-offscreen.rkt} file combines the pieces:

@racketblock[
(define (render-metal-scene output-path)
  (define context
    (make-gpu-context #:backend 'metal))

  (define detached-image
    (dynamic-wind
      void
      (lambda ()
        (call-with-gpu-context
         context
         (lambda ()
           (with-skia
               ([surface
                 (make-gpu-surface
                  context
                  scene-width scene-height
                  #:background scene-background)])
             (define canvas
               (surface-canvas surface))
             (draw-scene canvas)
             (gpu-surface->raster-image
              surface)))))
      (lambda ()
        (gpu-context-close! context))))

  (save-image detached-image
              output-path
              'png
              #:exists 'replace))
]

The actual standalone file also normalizes the output path, creates its parent
directory, and verifies the Metal backend before publishing the image.

@section{What the Comparison Does Not Prove}

The opening comparison demonstrates that the same scene can be drawn through
two different surface backings.

It does not establish that GPU rendering is faster. A tutorial-sized scene is
not a benchmark.

It also does not promise universal pixel-for-pixel identity across every
driver, color configuration, sample count, or GPU backend. The project's GPU
validation suites are the appropriate place for controlled parity, lifetime,
and synchronization checks.

@section{Try It}

Try moving one of the nodes in @filepath{scene.rkt}. Rebuild the manual to
regenerate the CPU side, then rerun the Metal command to update the static
reference image.

Try changing the background gradient. The edit should affect both routes
because both use @racket[draw-scene].

Try replacing the immediate CPU detachment with
@racket[gpu-surface-snapshot]. Use that GPU image in a second drawing on the
same context before performing one final readback.

Try adding @racket[gpu-flush-and-submit!] before another GPU-only operation.
Keep the final readback separate and observe the two different boundaries.

@section{Where to Go From Here}

This tutorial reused one drawing function across CPU and Metal surfaces. It
introduced GPU context activation, activation-scoped canvases, explicit
submission, explicit CPU detachment, and deterministic GPU teardown.

Window presentation, redraw scheduling, GPU-resident image graphs, backend
interop, cache controls, and performance measurement belong in the Guide.

The complete @filepath{scene.rkt} and @filepath{gpu-offscreen.rkt} files contain
the shared scene and the offscreen Metal renderer.
