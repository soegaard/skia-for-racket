#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title{Animation — Orbiting Lights in a Window}

@(require racket/file
          racket/runtime-path
          "eval.rkt"
          (for-label racket
                     skia
                     skia/bitmap
                     skia/gpu))

@(define-runtime-path scene-source "scene.rkt")
@(define-runtime-path animation-source "orbiting-lights.rkt")

@section[#:tag "finished-result"]{The Finished Animation}

@(tutorial-figure
 (string-append
  "At 0, 1.2, and 2.4 seconds, two moving lights change position around a fixed central "
  "light.")
 (animation-frame-strip))

The three frames show the scene at 0, 1.2, and 2.4 seconds. In the complete
program, a blue light and a violet light move around the central amber light.
The window has Pause, Resume, and Close controls. It can render through either
the CPU or a GPU without changing the scene's drawing function.

@centered{@bold{Describe one frame with Skia drawing functions. Change time,
then request another frame.}}

@tutorial-entry["animation"]

From a checkout with Skia installed, run either command from the repository root.
The first selects the CPU:

@verbatim{
racket scribblings/tutorials/animation/orbiting-lights.rkt \
  --renderer raster
}

The second selects the GPU:

@verbatim{
racket scribblings/tutorials/animation/orbiting-lights.rkt \
  --renderer gpu
}

If GPU mode is unavailable, use @command-text["--renderer raster"].
The program reports GPU failures instead of silently retrying on the CPU.

@section{Draw a Frame with Skia}

The @filepath{scene.rkt} file uses the familiar @racketmodname[skia] API from
@tutorial-link["quick"]. Its drawing function receives an ordinary Skia canvas:

@racketblock[
(draw-scene canvas seconds width height)
]

The time selects the positions of the lights. The width and height determine
the center and scale of the scene. Nothing in this function knows whether the
canvas belongs to a CPU surface or a GPU frame.

A still image needs only an ordinary CPU surface:

@racketblock[
(require skia "scene.rkt")

(define surface
  (make-surface scene-width scene-height
                #:background scene-background))
(draw-scene (surface-canvas surface) 0.0 scene-width scene-height)
(save-png surface "orbiting-lights.png" #:exists 'replace)
]

@(tutorial-figure
 "At time zero, two lights sit at their initial positions on the elliptical orbits."
 (animation-frame-pict 0.0 #:scale 0.68))

The background is cleared with @racket[canvas-clear!]. The grid uses
@racket[draw-line]; the paths use @racket[draw-oval]; and the lights use
@racket[draw-circle] with translucent Skia paints. The final labels use
@racket[draw-simple-text]. The paints and fonts are defined once in
@filepath{scene.rkt} and reused by every frame.

This is the same style of drawing introduced in @tutorial-link["quick"].
Animation will change the @racket[seconds] argument, not the drawing API.

@section{Make the Lights Move}

The lights follow elliptical orbits. Given a center, two radii, and an angle,
their positions are:

@racketblock[
(define (orbit-position center-x center-y radius-x radius-y angle)
  (values (+ center-x (* radius-x (cos angle)))
          (+ center-y (* radius-y (sin angle)))))
]

For example, an orbit centered at (100, 80), with horizontal radius 40 and
vertical radius 20, starts at (140, 80):

@animation-interaction[
(call-with-values
 (lambda () (orbit-position 100 80 40 20 0))
 list)
]

The blue light's angle is @racket[(* 0.85 seconds)]. The violet light uses
@racket[(+ 1.4 (* -1.15 seconds))]. These numbers are in radians: the initial
1.4 is an offset, and the negative speed makes the second light move in the
opposite direction. In a y-down canvas, increasing angles move clockwise.

@(tutorial-figure
 (string-append
  "At 1.2 seconds, both moving lights have advanced while the center and elliptical paths "
  "stay fixed.")
 (animation-frame-pict 1.2 #:scale 0.68))

At 1.2 seconds, the lights have moved while the orbits stay fixed. This is a
fresh rendering: the program neither moves old pixels nor relies on previous
canvas state. The same approach works when a window is resized or exposed.

@section{Put the CPU Scene in a Window}

A normal Racket GUI window can display a Skia CPU surface. Here is a
standalone static-window example using the same @racket[draw-scene] function.
The drawing itself still takes place through @racket[surface-canvas]. Only the
final presentation uses the GUI drawing context.

@racketblock[
(require racket/class
         (only-in racket/gui/base canvas% frame% queue-callback)
         skia skia/bitmap
         "scene.rkt")

(queue-callback
 (lambda ()
   (define window (new frame% [label "Static orbit"]
                       [width 800] [height 550]))
   (new canvas% [parent window]
        [paint-callback
         (lambda (widget dc)
           (define-values (width height) (send widget get-client-size))
           (when (and (positive? width) (positive? height))
             (with-skia ([surface (make-surface width height)])
               (draw-scene (surface-canvas surface) 0.0 width height)
               (send dc draw-bitmap (surface->bitmap surface) 0 0))))])
   (send window show #t)))
]

The @racket[surface->bitmap] function copies pixels from a completed Skia
surface into a Racket bitmap. The GUI's drawing context only displays that
bitmap; the scene's geometry, paints, and text all use Skia. A CPU frame
therefore involves a pixel copy before presentation. This simple example
allocates a new surface each time; it is not a performance benchmark.

The @racket[queue-callback] function creates the window on the eventspace's
handler thread. The paint callback also runs on that thread. The complete
animation uses a custom frame with room for the controls.

@section{Request Another Frame}

The complete application uses one operation for drawing a frame. It holds
the current animation time in @racket[elapsed-seconds]:

@racketblock[
(define (paint-frame canvas width height)
  (draw-scene canvas elapsed-seconds width height)
  (schedule-next-tick))
]

On the CPU, the callback creates a surface, calls @racket[paint-frame] on its
Skia canvas, and displays the bitmap. On the GPU, the callback calls
@racket[paint-frame] on @racket[(gpu-frame-canvas frame)]. Both routes share
the drawing code and the elapsed-time state.

The @racket[request-frame] helper asks whichever window is active to redraw.
The CPU and GPU paths request frames differently, but neither draws inside
this helper:

@racketblock[
(define (request-frame)
  (when (and view (not closed?))
    (if (eq? renderer 'gpu)
        (send view request-gpu-render)
        (send view refresh))))
]

The timer is separate from drawing. Its callback updates elapsed time and
calls this helper:

@racketblock[
(set! ticker
  (new timer%
       [notify-callback
        (lambda ()
          (unless (or paused? closed?)
            (let ([now (current-inexact-monotonic-milliseconds)])
              (set! elapsed-seconds
                    (+ elapsed-seconds (/ (- now previous-ms) 1000.0)))
              (set! previous-ms now)
              (request-frame))))]))
]

The timer never draws. A refresh request asks the GUI scheduler for a paint
callback, but requests may be coalesced or deferred when a window is hidden.
Motion therefore depends on measured elapsed time, not frame count.

@verbatim{
Timer -> update elapsed-seconds -> request repaint
                                         |
Window paint callback <- GUI scheduler <--+
         |
         +-> draw-scene -> schedule next tick
}

@section{Let the Controls Respond}

A repeating timer that immediately schedules another expensive frame can keep
mouse and window events from running promptly. Instead, use a one-shot timer
and rearm it after the current frame has been drawn:

@racketblock[
(define (schedule-next-tick)
  (queue-callback
   (lambda ()
     (when (and ticker (not paused?) (not closed?))
       (send ticker start frame-interval-ms #t)))
   #f))
]

The @racket[#f] argument requests a low-priority queued callback, so input
and window events have an opportunity to run first. The @racket[#t] argument
to @racket[start] makes the 50-millisecond timer fire only once. The interval
is not an exact frame-rate promise: drawing and presentation also take time.

@section{Pause and Resume Without Jumping}

The Pause button stops the timer but leaves @racket[elapsed-seconds] unchanged.
Resuming resets the previous clock reading, so the time spent paused is not
mistaken for animation time:

@racketblock[
(if paused?
    (begin
      (set! paused? #f)
      (set! previous-ms (current-inexact-monotonic-milliseconds))
      (send ticker start frame-interval-ms #t)
      (send button set-label "Pause"))
    (begin
      (set! paused? #t)
      (send ticker stop)
      (send button set-label "Resume")))
]

With the timer stopped, the lights remain at their last positions. Resume
continues from those positions, rather than jumping ahead by the length of
the pause.

@section{Choose a GPU Backend for Your Platform}

The animation can also use a GPU window. Its Skia drawing function stays the
same; only the window backend and presentation path change.

Metal is available on macOS, Direct3D 12 on Windows x64, and desktop OpenGL
is the Linux route. The standalone example selects a backend at startup:

@racketblock[
(define (preferred-gpu-backend)
  (case (system-type 'os)
    [(macosx) 'metal]
    [(windows)
     (and (eq? (system-type 'arch) 'x86_64)
          'direct3d)]
    [(unix) 'opengl]
    [else #f]))
]

The result is a backend name, or @racket[#f] for an unsupported platform.
The program checks for @racket[#f] before creating the GPU widget. Linux needs
a compatible desktop OpenGL context.

This is @emph{platform selection}, not GPU detection. Initialization can still
fail, possibly after the window appears.

An explicit choice matters on Windows: @racket['auto] in
@racket[gpu-canvas%] currently selects OpenGL outside macOS, while this
program chooses Direct3D 12 on Windows x64.

@section{Draw Directly into a GPU Frame}

GPU window presentation needs no intermediate CPU bitmap. The
@racketmodname[skia/gpu-gui] module supplies @racket[gpu-canvas%], while
@racketmodname[skia/gpu] supplies a borrowed Skia canvas for each GPU frame.

GPU frame widths and heights describe physical pixels, while the CPU window
uses logical client dimensions. These sizes may differ on a Retina display.
The frame supplies X/Y scale factors for matching the CPU scene's logical
coordinates:

@racketblock[
(define (paint-gpu-frame frame)
  (define canvas (gpu-frame-canvas frame))
  (with-canvas-state canvas
    (canvas-scale! canvas (gpu-frame-scale-x frame) (gpu-frame-scale-y frame))
    (paint-frame canvas
                 (gpu-frame-logical-width frame)
                 (gpu-frame-logical-height frame))))
]

Inside the complete window program, after creating @racket[panel], the GPU
widget uses that callback:

@racketblock[
(require skia/gpu skia/gpu-gui)

(new gpu-canvas% [parent panel]
     [backend gpu-backend]
     [render paint-gpu-frame])
]

The scene receives the same logical window size as in CPU mode. The
@racket[with-canvas-state] form restores the transform when drawing ends.
The GPU canvas is borrowed and expires when the render callback returns;
do not retain it. The presenter submits the frame and displays it directly.

@section{Compare the Rendering Routes}

The two run commands at the start select different presentation routes:

@verbatim{
CPU:  Skia surface -> draw-scene -> surface->bitmap -> GUI window
GPU:  GPU frame     -> draw-scene -> GPU presentation -> GUI window
}

Both routes use the same Skia drawing function. The GPU route retains its
presenter and context between frames, unlike the one-shot helper in
@tutorial-link["gpu"].

GPU presentation avoids a complete-frame CPU readback. Whether it is faster
for this scene depends on the machine and window size; measure before choosing
it for performance.

@section{Close the Window Cleanly}

A window close must stop the timer before retiring its GPU presenter. The
window's native close control and the visible Close button use the same
cleanup function:

@racketblock[
(define (close-animation)
  (unless closed?
    (when ticker (send ticker stop))
    (when (and view (eq? renderer 'gpu))
      (send view close-gpu))
    (set! closed? #t)
    (send window show #f)))
]

The CPU window has no persistent Skia surface to close: each frame's surface
is released promptly by @racket[with-skia]. The GPU presenter, in contrast,
owns a live context and must be closed when the animation ends.

@section[#:tag "try-it"]{Try It}

Try increasing the blue light's angular speed from 0.85 to 1.6. Then reverse
the violet light's direction by changing its -1.15 speed to 1.15. The paths
remain the same; only positions change with time.

Try resizing the animation window. The orbits should remain centered because
@racket[draw-scene] receives the current target dimensions on each frame.
Pause, resume, and close using both the button and the window's close control.

Finally, run both renderers and compare the results at the same window size.
On a high-density display, the GPU uses the frame's backing scale so orbit
positions remain in the same logical coordinates as CPU mode. Exact pixels
can still differ across renderers and drivers.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now draw a frame from elapsed time, request another frame, and stop the renderer cleanly.

@tutorial-next["animation"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["animation"]

The @filepath{orbiting-lights.rkt} file contains the window, timer, Pause/Resume
and Close buttons, and the CPU/GPU adapters. It includes the physical-to-logical
GPU scaling shown above. Save this file alongside @filepath{scene.rkt} to run it:

@codeblock[(file->string animation-source)]

The @filepath{scene.rkt} file contains the Skia paints, orbital calculations,
and drawing functions shared by the CPU and GPU windows:

@codeblock[(file->string scene-source)]
