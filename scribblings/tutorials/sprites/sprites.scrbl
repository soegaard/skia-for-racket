#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia skia/gpu))
@(define-runtime-path atlas-source "atlas.rkt")
@(define-runtime-path model-source "model.rkt")
@(define-runtime-path drawing-source "scene.rkt")
@(define-runtime-path program-source "balls.rkt")
@(define-runtime-path assets-source "../support/sprite-assets.rkt")
@(define-runtime-path host-source "../support/sprite-window.rkt")
@(define-runtime-path math-source "../support/sprite-math.rkt")

@title[#:tag "sprite-atlases"]{Sprite Atlases — Animate Bouncing Balls on the GPU}

@section[#:tag "finished-result"]{The Finished Animation}

@(tutorial-figure
   (string-append
    "Thirty colored balls of different sizes appear inside a bounded playfield. Each "
    "moving ball selects a cell from the same atlas.")
   (balls-pict))

Thirty colored balls move, spin, and bounce inside a window. Each ball is a
placement of one small image from a shared @emph{sprite atlas}. A sprite atlas
is one image containing several pieces of artwork, selected by source rectangles.

The CPU prepares the atlas once. The GPU version uploads that image once to
its window's context and uses the resulting GPU image on later frames.
Positions change; the atlas pixels do not.

@centered{@bold{Keep one image. Change which rectangle to draw and where to put it.}}

Run the complete program from the repository root:

@verbatim{
racket scribblings/tutorials/sprites/balls.rkt --renderer gpu
}

The window includes Pause, Restart, and Close controls. The status line shows
how many times this program has called the atlas upload function. Restart
resets the balls without uploading again. Use @command-text["--renderer raster"] for the
explicit CPU version, or add @command-text["--count 300"] to draw more balls.

If GPU drawing is new to you, the
@tutorial-link["gpu"]
tutorial introduces GPU canvases. For frame scheduling and GUI controls, see
@tutorial-link["animation"].

@tutorial-entry["sprites"]

@section{Look Inside the Atlas}

@(tutorial-figure
   (string-append
    "Eight ball sprites occupy four columns and two rows in a 224-by-112 atlas. The cell "
    "numbers, outlines, and checkerboard are guides outside the stored artwork.")
   (ball-atlas-pict))

The atlas is shown at twice its natural size with nearest-neighbor sampling.
The numbered frames and
checkerboard are explanatory overlays; they are not baked into the atlas.
The checkerboard reveals its transparent pixels.

The atlas is 224 by 112 pixels. There are four columns and two rows. Every
sprite occupies a 48-by-48 source rectangle, with four transparent pixels
on each side. Each cell therefore takes 56 by 56 pixels in the sheet.
The first source rectangle is @racket['(4 4 48 48)], not the whole first cell.

The source-rectangle helper converts a cell index into atlas coordinates:

@codeblock[(source-definition math-source 'sprite-source)]

@sprites-interaction[
(sprite-source 0)
(sprite-source 4)
]

The gaps help isolate neighboring sprites during linear sampling. They are
not a general solution for arbitrary mipmap levels or extreme minification.
This example uses the default non-mipmapped upload and modest sprite sizes.

@section{Generate the Artwork Once}

The atlas starts as an ordinary CPU surface. The generator translates to each
cell, clips drawing to its source rectangle, and draws a colored ball. A radial
gradient gives the sphere volume. An off-center highlight makes rotation visible.

@codeblock[(source-definition atlas-source 'make-ball-atlas)]

The @racket[surface-snapshot] function returns an immutable image of the
surface contents. That image survives the deterministic release of the
construction surface. No surface is created for an individual moving ball.
The CPU image can also be saved as PNG or used by the raster version.

The program generates the artwork with Skia; no external sprite sheet is needed.

@section{Place One Sprite}

An atlas placement has two independent parts: a source rectangle in the
image, and a transform that places that rectangle on the canvas.

@racketblock[
(define placement
  (make-atlas-transform 140 76 #:scale 2 #:anchor '(24 24)))
(draw-atlas canvas atlas
            (list placement)
            (list (sprite-source 2))
            #:sampling 'linear)
]

@(tutorial-figure
   (string-append
    "Cell 2 is placed at scale 2 with its local center (24, 24) mapped to canvas point "
    "(140, 76). The cross marks this fixed anchor.")
   (one-ball-pict))

Here, @racket[canvas] is the current Skia canvas and @racket[atlas] is the image
being drawn. The complete image-producing and window programs appear below.

The dark cross marks the anchor on the displayed sprite. The point
@racket['(24 24)] is the center of a 48-by-48 source rectangle, @emph{not}
a position in the full atlas. The transform maps this local anchor to
@racket['(140 76)] on the canvas. Rotation and scale act around this anchor:
they do not move its canvas position.

@section{Reuse a Sprite at Different Sizes and Angles}

@(tutorial-figure
   (string-append
    "Three placements use cell zero at scale 1 and zero degrees, scale 1.5 and 40 "
    "degrees, and scale 2 and minus 35 degrees. The off-center highlight makes rotation "
    "visible.")
   (placements-pict))

All three placements select cell zero. Only their transforms differ. Positive
rotation angles are clockwise in the default downward-y coordinate system.
The scale changes the drawn size, not the source image's pixel dimensions.

The complete example creates a transform from each ball's data:

@codeblock[(source-definition drawing-source 'ball-transform)]

A transform is a small Racket value. Making another transform does not create
another image, copy atlas pixels, or upload a new texture.

@section{Upload Once, Then Keep the GPU Image}

The GPU presenter supplies an active context inside each frame callback.
The first frame uploads the CPU atlas into that context:

@racketblock[
(unless gpu-atlas
  (set! gpu-atlas
        (gpu-upload-image (gpu-frame-context frame) cpu-atlas)))
]

The uploaded image must be retained @emph{outside} the callback's local
resource scope. Closing it with @racket[with-skia] at the end of that frame
would defeat reuse. The borrowed canvas, in contrast, is used only during
its frame callback and must not be retained.

The following helper retains the uploaded image across frames and is also used
by @tutorial-link["squadron"]:

@codeblock[(source-definition assets-source 'sprite-texture-for-frame!)]

Its first call stores the GPU image and owning context. Later calls return the
same image. A different context is rejected; even another window on the same
physical GPU needs its own upload. The helper does not silently migrate textures.

The image is bound to its GPU context. A software graphics driver can implement
the same API, so this ownership rule does not imply hardware acceleration.

@section{Submit a Batch}

The drawing function builds parallel lists of transforms and source rectangles:

@racketblock[
(draw-atlas canvas atlas
            (map ball-transform sprites)
            (map (lambda (sprite) (sprite-source (ball-cell sprite))) sprites)
            #:sampling 'linear)
]

Both lists have one entry for every sprite, in the same order. The same image
can appear many times. There is no need to call @racket[image-subset] or make
one GPU image per ball.

This is one Skia atlas call for the sprite batch, not a promise of exactly one
hardware draw call. The background and labels are separate drawings. A larger
sprite count also increases Racket work to construct the placement lists and
native work to process the batch.

The renderer receives either the CPU atlas or its GPU counterpart. Its drawing
code is otherwise unchanged:

@codeblock[(source-definition drawing-source 'draw-balls)]

@section{Make the Balls Bounce}

The simulation keeps positions, velocities, angles, and cell indices as plain
Racket data. It contains no surfaces, canvases, or GPU handles.

@racketblock[
(struct ball (x y vx vy angle spin cell scale) #:transparent)
(struct ball-world (balls ticks) #:mutable #:transparent)
]

Consider a ball at position 9 moving right at 4 units per second inside the
interval from 0 to 10. After one second it has reached the wall and traveled
3 units back, ending at 7 with velocity -4. The supplied motion helper returns
that position and velocity:

@sprites-interaction[
(call-with-values (lambda () (reflect-axis 9 4 0 10 1)) list)
]

@subsection{The Supplied Motion Helper}

The helper preserves travel beyond a wall instead of stopping at the boundary.
Its formula also handles an update that crosses several walls. Atlas placement
only needs the resulting positions; deriving this formula is not a prerequisite
for drawing the sprites.

@codeblock[(source-definition model-source 'reflect-axis)]

@codeblock[(source-definition model-source 'step-balls!)]

@(tutorial-figure
   (string-append
    "The balls at simulation time zero and one second have different positions and "
    "angles. Their cell selections and atlas pixels are unchanged.")
   (balls-motion))

The two images are exactly 120 simulation steps apart. The ball cell indices
stay the same. The radius used for wall tests covers each circular sprite,
including its halo. Balls do not collide with one another; that would add
unrelated physics to a tutorial about drawing sprites.

@section{Use the Same Window on CPU and GPU}

The shared window advances simulation in fixed 1/120-second steps. A monotonic
clock determines how many steps are due. At most 0.1 seconds is accepted from
one clock update, so a long stall does not cause minutes of catch-up work.
This favors responsiveness over preserving real time during severe overload.

A one-shot timer requests a later frame. After painting, a low-priority
callback rearms the timer. Pause stops it and Resume resets the time reference.
Resizing and exposure redraw the current model without advancing it.

@verbatim{
CPU: CPU atlas -> draw-atlas on a CPU surface -> bitmap -> window
GPU: CPU atlas -> one upload -> draw-atlas on GPU frames -> presentation
}

The GPU route performs no per-frame PNG encoding, bitmap bridge, or explicit
pixel readback. The CPU route copies the completed surface for presentation.
Both use the same simulated scene and preserve its aspect ratio when resized.
GPU backing scale is applied separately from that scene-to-window transform.

Both window modes need a graphical session. GPU initialization errors are
reported rather than retried on the CPU. Select @command-text["--renderer raster"]
to use the CPU explicitly.

@section{Close in Ownership Order}

The atlas helper owns both its CPU image and the optional GPU image:

@codeblock[(source-definition assets-source 'close-sprite-texture!)]

The window first stops the timer, then closes those images, then closes its
GPU presenter. The presenter drains queued GPU releases before destroying the
context. The native close control and the Close button share this path.

The upload counter should read one after the first GPU frame, remain one during
animation and Restart, and read zero throughout a raster run. The counter is
an application diagnostic; it does not count driver-internal allocations.

@section[#:tag "try-it"]{Try It}

Try 30, 300, and 1000 balls. Watch the upload counter as the count and number
of placements change. Do not interpret a smooth-looking animation as a
benchmark; the scene, window size, driver, and machine all matter.

Try selecting the same cell for every ball. Then set all spins to zero, or
replace one atlas drawing with a different shape. A change to the artwork
requires a new atlas; changing a placement does not.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now retain one atlas across frames and change its placements without uploading it again.
The game lesson adds simulation and input while keeping that ownership model.

@tutorial-next["sprites"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["sprites"]

Run @filepath{balls.rkt} from the repository or installed collection. Its
relative imports include the shared helpers in @filepath{../support/}; keep
those files when copying the example. The GUI module is loaded only when a
window is opened. Saving a still image does not initialize the GUI:

@verbatim{
racket scribblings/tutorials/sprites/balls.rkt --snapshot balls.png
}

@subsection{The Atlas}
@codeblock[(file->string atlas-source)]

@subsection{The Simulation}
@codeblock[(file->string model-source)]

@subsection{The Drawing Function}
@codeblock[(file->string drawing-source)]

@subsection{The Entry Point}
@codeblock[(file->string program-source)]

@subsection{The Shared Atlas Lifetime}
@codeblock[(file->string assets-source)]

@subsection{The Shared Coordinates and Clock}
@codeblock[(file->string math-source)]

@subsection{The Shared Window}

The @tutorial-link["squadron"] game reuses this
window host. Its construction, input, timing, and teardown are separate from
the application's drawing and simulation.

@codeblock[(file->string host-source)]
