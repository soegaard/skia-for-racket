#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "waves.rkt"
          "../support/source.rkt" (for-label racket skia skia/gpu))
@(define-runtime-path program-source "waves.rkt")
@(define-runtime-path window-source "waves-window.rkt")

@title{Runtime Shaders — Animate Prismatic Waves in a Window}

@section[#:tag "finished-result"]{The Finished Animation}

@(tutorial-figure
   (string-append
    "Three frames at 0, 0.75, and 1.5 seconds show curved rainbow bands changing position "
    "and shape as phase advances.")
   (wave-animation-strip))

The three pictures show the same animated shader at 0, 0.75, and 1.5 seconds.
The complete program opens a window, animates the waves, and lets you adjust
frequency, bend, and hue while the animation is running.

You can run the complete animated window now, from the repository root:

@verbatim{
racket scribblings/tutorials/shaders/waves-window.rkt --renderer gpu
}

If the machine has no supported GPU backend, choose @command-text["--renderer raster"].
The following sections explain how the shader and window work.

@centered{@bold{Compile the shader program once. Change uniforms to animate the shader.}}

SkSL is Skia's shading language. A runtime shader is a small SkSL program that
computes colors. Skia compiles the program into an effect, then creates shader
instances by supplying values for its inputs, called uniforms.

@tutorial-entry["shaders"]

@section{Start with a Constant Color}

A shader does not need geometry of its own. It computes a color for each point
in the shape that uses it. The smallest possible shader ignores its input:

@codeblock[(source-definition program-source 'solid-source)]

@shaders-racketblock+eval[
(define solid-effect (make-runtime-effect solid-source))
(define solid-shader (runtime-effect->shader solid-effect #:uniforms (hash)))
]

The shader supplies colors to a paint. Use that paint to fill a rectangle on
a raster surface:

@shaders-racketblock+eval[
(define solid-surface (make-surface 320 180))
(define solid-paint (make-paint #:shader solid-shader))
(draw-rect (surface-canvas solid-surface) 0 0 320 180 solid-paint)
]

The rectangle supplies the geometry; the shader supplies the color at each
point. The same paint can draw on a borrowed GPU canvas during its frame
callback. An ordinary image file can be saved from this CPU surface:

@racketblock[
(save-png solid-surface "solid-shader.png" #:exists 'replace)
]

@(tutorial-figure
   (string-append
    "A rectangle is filled with one cyan color. The constant shader returns the same "
    "color at every point.")
   (shader-pict solid-source (hash)))

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

@(tutorial-figure
   (string-append
    "The red channel increases from left to right and green from top to bottom, producing "
    "a coordinate-dependent gradient across the rectangle.")
   (shader-pict coordinate-source (hash 'extent '(320 180))))

The red channel increases from left to right; the green channel increases from
top to bottom. The @tt{extent} uniform tells the shader how large the panel is,
so that @tt{p / extent} can normalize the coordinates to the 0–1 range.

@section{Make Repeating Bands}

Begin with a shader that draws grayscale stripes. The sine function ranges
from -1 to 1. Multiplying by 0.5 and adding 0.5 maps that range to 0 through 1,
which can be used as a grayscale channel value:

@codeblock[(source-definition program-source 'bands-source)]

@(tutorial-figure
   (string-append
    "Vertical grayscale bands alternate smoothly between black and white. Scaling and "
    "offsetting sine maps its values into the zero-to-one channel range.")
   (bands-pict))

The expression @tt{0.5 + 0.5 * sin(...)} supplies the grayscale value:
the sine values -1, 0, and 1 become 0, 0.5, and 1 respectively.
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

@(tutorial-figure
   (string-append
    "With bend zero, the colorful bands are straight. The rainbow palette and highlights "
    "still vary across the rectangle.")
   (waves-pict #:bend 0))

The shader uses the smaller panel dimension to scale both axes equally.
Frequency counts cycles per that normalized distance, so the visible number of
bands depends on both frequency and the panel's proportions.

@(tutorial-figure
   (string-append
    "Panels with frequencies 3, 5, and 8 have the same dimensions and zero bend. Higher "
    "frequency puts more bands in the panel.")
   (frequency-variants))

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

@(tutorial-figure
   (string-append
    "Panels with bend 0, 0.15, and 0.35 change from straight stripes to increasingly "
    "curved bands while the other inputs stay fixed.")
   (wave-variants))

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
The lighting also uses this angle, so Hue shifts the highlights as well as the
palette. It is not a color-only adjustment.

@(tutorial-figure
   (string-append
    "The same wave field uses hue 0.08 on the left and 0.58 on the right. Colors and "
    "angle-dependent highlights shift; the field is unchanged.")
   (hue-pair))

Both panels use the same geometry and phase. Only @tt{hue} changes, from
0.08 to 0.58. Notice how different colors occupy the same bends.

@section{Animate the Phase}

The SkSL source uses @tt{phase} in more than one place. It changes the shape
of the bent field and it also shifts the color pattern. A new phase therefore
produces a new frame without recompiling the shader.

@(tutorial-figure
   (string-append
    "At phase 0 and phase 1, frequency remains 5 and bend remains 0.30. Advancing phase "
    "changes both the bent field and its color pattern.")
   (phase-pair))

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

@(tutorial-figure
   (string-append
    "The complete shader panel at 1.2 seconds contains curved rainbow bands, narrow crest "
    "highlights, and darkened edges.")
   (wave-scene-pict 1.2 #:scale 0.73))

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

@(tutorial-figure
   (string-append
    "With glow zero the crest highlights are absent. With glow one narrow bright "
    "highlights appear on the same colored bands.")
   (glow-pair))

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
new native resources. The compiled effect remains available for the next frame.

@section{Pay Attention to Local Coordinates}

The animated pattern begins at the local origin of its rounded rectangle.
Moving only a rectangle and moving the canvas origin are different operations:

@(tutorial-figure
   (string-append
    "Both rectangles start at (48, 32). On the left only the geometry moved; on the right "
    "the canvas origin moved too, changing the sampled portion of the pattern.")
   (origin-pair))

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
The @bold{Bend} slider changes their curvature. The @bold{Hue} slider shifts
the palette and angle-dependent lighting without changing the wave field.
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
we introduced in @tutorial-link["animation"].

@section{Choose CPU or GPU}

The @command-text["--renderer gpu"] mode selects Metal on macOS, Direct3D 12 on Windows
x64, and OpenGL on Linux with a suitable graphical desktop. It does not
silently fall back if a native GPU backend is unavailable. Use
@command-text["--renderer raster"] to draw the same scene on the CPU.

Both modes use Skia's runtime shader implementation. A GPU is not automatically
faster for a small scene; persistent drawing and avoiding readback are the
reasons to consider it here, not a performance claim.

@section[#:tag "try-it"]{Try It}

Try raising the frequency and then the bend while the animation is running.
They modify different parts of the pattern. Pause and use the sliders to
compare two frames without the time changing.

Try changing @racket[phase-speed] from 2 to 0.5 or reversing its sign. The
waves will travel more slowly or reverse direction. Then try changing the hue.
A different hue shifts colors and highlights along the same wave field.

Try reducing @racket[#:bend] to zero. The bands become straight, but their
colors still move because phase still appears in the angle expression.

@section[#:tag "next-steps"]{Where to Go From Here}

Runtime effects are compiled application code, not a sandbox for untrusted shader source.
Compilation can fail, and complex programs can be expensive to render. The upstream
@hyperlink["https://skia.org/docs/user/sksl/"]{SkSL and Runtime Effects}
guide explains how runtime shaders fit into Skia's drawing pipeline.

@tutorial-next["shaders"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["shaders"]

The @filepath{waves.rkt} file contains the shader sources, the uniform helper,
and the backend-neutral drawing function. Running it alone saves
@filepath{wave-frame.png}, a still frame at time zero:

@codeblock[(file->string program-source)]

The @filepath{waves-window.rkt} file creates the CPU/GPU window, sliders,
Pause/Resume and Close controls. Save it beside @filepath{waves.rkt}:

@codeblock[(file->string window-source)]
