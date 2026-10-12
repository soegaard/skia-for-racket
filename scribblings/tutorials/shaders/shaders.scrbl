#lang scribble/manual

@(require racket/file racket/runtime-path "eval.rkt" "waves.rkt"
          "../support/source.rkt" (for-label racket skia skia/gpu))
@(define-runtime-path program-source "waves.rkt")
@(define-runtime-path window-source "waves-window.rkt")

@title{Runtime Shaders — Animate Prismatic Waves in a Window}

@section{The Finished Animation}

@(wave-animation-strip)

The three pictures show the same animated shader at 0, 0.75, and 1.5 seconds.
The complete program opens a window, animates the waves, and lets you adjust
frequency, bend, and hue while the animation is running.

The pictures are real Skia renderings of three moments in the animation, not
screenshots of the window. The application reuses the same drawing function.

You can run the complete animated window now, from the repository root:

@verbatim{
racket scribblings/tutorials/shaders/waves-window.rkt --renderer gpu
}

If the machine has no supported GPU backend, choose @tt{--renderer raster}.
The following sections explain how the shader and window work.

@centered{@bold{Compile the SkSL program once. Change uniforms to animate the shader.}}

A runtime shader is a small SkSL program. Skia compiles it into an effect and
then creates shader instances by supplying uniform values.

@section{Start with a Constant Color}

A shader does not need geometry of its own. It computes a color for each point
in the shape that uses it. The smallest possible shader ignores its input:

@codeblock[(source-definition program-source 'solid-source)]

@shaders-racketblock+eval[
(define solid-effect (make-runtime-effect solid-source))
(define solid-shader (runtime-effect->shader solid-effect #:uniforms (hash)))
]

@(shader-pict solid-source (hash))

The result is one flat color because the SkSL program returns the same value
for every point.

@section{Use Coordinates}

The @tt{main} function receives the point being shaded. The next program turns
that point into a visible color gradient:

@codeblock[(source-definition program-source 'coordinate-source)]

@shaders-racketblock+eval[
(define coordinate-effect (make-runtime-effect coordinate-source))
(define coordinate-shader
  (runtime-effect->shader coordinate-effect
                          #:uniforms (hash 'extent '(320 180))))
]

@(shader-pict coordinate-source (hash 'extent '(320 180)))

The red channel increases from left to right; the green channel increases from
top to bottom. The @tt{extent} uniform tells the shader how large the panel is,
so that @tt{p / extent} can normalize the coordinates to the 0–1 range.

@section{Make Repeating Bands}

Begin with a simpler shader that draws grayscale stripes. The sine function
produces repeating values between 0 and 1 as its input changes:

@codeblock[(source-definition program-source 'bands-source)]

@(bands-pict)

The factor 6.2831853 is approximately two pi. The @tt{frequency} uniform
controls how many cycles appear across the normalized field. There is no
animation or rainbow yet: changing the shader coordinates changes the gray
value at each position.

The colorful shader reuses the same coordinate normalization and frequency.
For its first variation, set @tt{bend} to zero so that the stripes stay straight:

@shaders-racketblock+eval[
(define effect (make-runtime-effect wave-source))
(define straight-shader (make-wave-shader effect 480 210 #:bend 0))
]

@(waves-pict #:bend 0)

The shader uses the smaller panel dimension to scale both axes equally.
Frequency counts cycles per that normalized distance, so the visible number of
bands depends on both frequency and the panel's proportions.

@(frequency-variants)

These three panels use the same dimensions, bend, hue, and phase. Only frequency
changes. The colorful source is assembled in the following sections.

@section{Bend the Bands}

The field adds a horizontal displacement that varies with vertical position:

@verbatim{
float field = q.x + bend * (
    sin(4.7 * q.y + 0.55 * phase)
  + 0.30 * sin(7.0 * q.x - 3.0 * q.y - 0.35 * phase));
}

The next examples change only @tt{bend}. They all use instances of the same
compiled effect:

@(wave-variants)

The Racket helper supplies the complete set of uniforms:

@codeblock[(source-definition program-source 'make-wave-shader)]

Every reflected uniform needs a value. An instance copies those values, so
changing a Racket hash later does not change an already-created shader.

@section{Turn One Value into Many Colors}

The shader converts one angle into three color channels by shifting a cosine
wave by one third of a turn for green and blue:

@verbatim{
float3 rainbow = 0.5 + 0.5 * cos(
    angle + float3(0.0, 2.0943951, 4.1887902));
}

This produces a smooth rainbow palette without a table of explicit color stops.
The @tt{hue} uniform is measured in turns, not radians: adding 0.5 moves
halfway around the color wheel. The wave field stays fixed while hue changes.

@(hue-pair)

Both panels use the same geometry and phase. Only @tt{hue} changes, from
0.08 to 0.58. Notice how different colors occupy the same bends.

@section{Animate the Phase}

The SkSL source uses @tt{phase} in more than one place. It changes the shape
of the bent field and it also shifts the color pattern. A new phase therefore
produces a new frame without recompiling the shader.

@(phase-pair)

Both panels keep frequency at 5 and bend at 0.30. Only phase changes. The
animation derives phase from elapsed seconds:

@codeblock[(source-definition program-source 'phase-at)]

For example, after 0.5 seconds, the phase is 1 radian when
@racket[phase-speed] is 2 radians per second:

@shaders-interaction[
(phase-at 0.5)
]

The @racket[draw-wave-scene] function uses this phase to make a new shader
instance for the current frame:

@codeblock[(source-definition program-source 'draw-wave-scene)]

@(wave-scene-pict 1.2 #:scale 0.73)

The animation does not move old pixels. Every frame draws a new result from
the current time. Frame rates can vary, but elapsed time makes the motion
independent of the number of frames drawn.

@section{Add a Glow to the Crests}

The rainbow gives each band a different color. The shader can also add a narrow
highlight at each wave crest. The @tt{glow} uniform controls its strength:

@verbatim{
float crest = pow(max(0.0, sin(angle)), 16.0);
color += 0.24 * glow * crest * float3(0.9, 0.95, 1.0);
}

@(glow-pair)

The two panels use the same wave geometry, phase, frequency, and hue. The
left panel sets @tt{glow} to zero, removing only the crest highlights; the
right uses the default strength of one. The narrow white highlights are most
noticeable near the brightest parts of the colored bands.

The shader also darkens its edges with a vignette. It returns an opaque color,
so its RGB channels already satisfy the premultiplied-alpha requirement.

Here is the complete SkSL program, including the two wave distortions,
rainbow channels, and lighting:

@codeblock[(source-definition program-source 'wave-source)]

@section{Reuse the Compiled Effect}

The application compiles @racket[wave-source] once when the GUI window opens.
Each drawing callback then creates a shader instance with the current uniforms.
The compiled effect is reused; the instance is new for that frame.

@codeblock[(source-definition program-source 'draw-wave-panel)]

This function closes the temporary shader and paint promptly through
@racket[with-skia]. That matters in an animation, where every frame creates
new native resources. Changing an input hash after instance creation cannot
change an existing shader, because Skia copies the uniform values.

@section{Pay Attention to Local Coordinates}

The animated pattern begins at the local origin of its rounded rectangle.
Moving only a rectangle and moving the canvas origin are different operations:

@(origin-pair)

Both panels use identical uniforms and a rectangle beginning at (48, 32). The
right-hand panel translates the canvas first, so the shader samples the pattern
relative to the new local origin. The animated scene uses that same approach
inside @racket[draw-wave-panel].

@section{Show the Animation in a Window}

The complete @filepath{waves-window.rkt} program supplies a GUI window. Its
GPU paint callback obtains the live Skia canvas for the current frame:

@codeblock[(source-definition window-source 'paint-gpu-frame)]

GPU framebuffer dimensions are physical pixels. The frame's scale factors map
our scene's logical coordinates onto those pixels, so the same drawing works
on high-density displays. The CPU mode instead renders into a Skia raster
surface and presents its @racket[surface->bitmap] through Racket's window
system. That GUI drawing context only displays the finished bitmap; the shader
itself always draws through Skia's canvas API.

The two routes are:

@verbatim{
CPU: Skia surface -> animated shader -> bitmap -> GUI window
GPU: GPU frame    -> animated shader -> GPU presentation
}

Neither route recompiles SkSL on every frame. The GPU mode also avoids
bringing every finished frame back to CPU memory.

@section{Change Uniforms While It Runs}

The window has three sliders. @bold{Frequency} changes the number of bands.
@bold{Bend} changes their curvature. @bold{Hue} rotates the rainbow palette.
Moving any slider requests a redraw using the existing compiled effect. The
timer changes only elapsed time. The crest glow is fixed at one; it is an
optional shader parameter rather than a fourth window control.

The timer uses a one-shot interval. A paint schedules the next tick at low
priority, leaving time for button and slider events. The Pause button stops the
timer; Resume resets the time reference so the waves do not jump forward by the
duration of the pause. Both the Close button and the window's native close
control stop the timer and retire the renderer.

The application does not perform rendering in the timer callback. It requests a
later frame, preserving the separation between state changes and drawing that
we introduced in Tutorial 14.

@section{Choose CPU or GPU}

The @tt{--renderer gpu} mode selects Metal on macOS, Direct3D 12 on Windows
x64, and OpenGL on Linux with a suitable graphical desktop. It does not
silently fall back if a native GPU backend is unavailable. Use
@tt{--renderer raster} to draw the same scene on the CPU.

Both modes use Skia's runtime shader implementation. A GPU is not automatically
faster for a small scene; persistent drawing and avoiding readback are the
reasons to consider it here, not a performance claim.

@section{The Complete Programs}

The @filepath{waves.rkt} file contains the shader sources, the uniform helper,
and the backend-neutral drawing function. Running it alone saves
@filepath{wave-frame.png}, a still frame at time zero:

@codeblock[(file->string program-source)]

The @filepath{waves-window.rkt} file creates the CPU/GPU window, sliders,
Pause/Resume and Close controls. Save it beside @filepath{waves.rkt}:

@codeblock[(file->string window-source)]

@section{Try It}

Try raising the frequency and then the bend while the animation is running.
They modify different parts of the pattern. Pause and use the sliders to
compare two frames without the time changing.

Try changing @racket[phase-speed] from 2 to 0.5 or reversing its sign. The
waves will travel more slowly or reverse direction. Then try changing the hue.
A different hue rotates the same color wheel without changing the geometry.

Try reducing @racket[#:bend] to zero. The bands become straight, but their
colors still move because phase still appears in the angle expression.

@section{Where to Go From Here}

Runtime effects are compiled application code, not a sandbox for untrusted
shader source. Compilation can fail, and complex programs can be expensive to
render. The Guide covers diagnostics, child shaders, runtime color filters,
and custom blenders.

The upstream @hyperlink["https://skia.org/docs/user/sksl/"]{SkSL and Runtime Effects}
guide explains how runtime shaders fit into Skia's drawing pipeline.
