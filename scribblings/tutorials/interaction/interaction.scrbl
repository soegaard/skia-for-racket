#lang scribble/manual

@title{Interactive Paths — Drag Bézier Control Points}

@(require racket/file
          racket/runtime-path
          "eval.rkt"
          (for-label racket
                     skia
                     skia/bitmap
                     skia/gpu))

@(define-runtime-path scene-source "scene.rkt")
@(define-runtime-path editor-source "bezier-editor.rkt")

@section{The Finished Editor}

@(editor-frame-pict #:scale 0.72)

This tutorial builds a small interactive editor for one cubic Bézier curve.
The two amber points are its endpoints, and the two cyan points control how
it bends. Drag any point to reshape the curve. The Reset button restores the
original shape, and the Close button ends the session.

The figure is rendered by Skia using the actual @racket[draw-editor] function.
The interactive window uses that same drawing function in both CPU and GPU
modes.

@centered{@bold{Draw the current points. Let mouse events change the points.
Then request a new frame.}}

@section{Draw a Cubic Curve}

A cubic Bézier curve has a start point, two control points, and an end point.
The @racket['cubic] path command takes the coordinates of the two control
points followed by the end point. Start with one fixed curve:

@racketblock[
(require skia "scene.rkt")

(define surface
  (make-surface editor-width editor-height
                #:background editor-background))
(define path
  (make-path
   '((move 120 320)
     (cubic 195 94 548 108 665 324))))
(define curve-paint
  (make-paint #:color "#F1F7FD"
              #:style 'stroke #:stroke-width 5 #:cap 'round))
(draw-path (surface-canvas surface) path curve-paint)
(save-png surface "bezier-curve.png" #:exists 'replace)
]

@(editor-stage-pict 'curve #:scale 0.60)

This picture uses the same curve geometry and paint as the code above. The
curve runs from (120, 320) to (665, 324). The other two points at (195, 94)
and (548, 108) guide its shape; they do not normally lie on the curve itself.

To make the curve editable, the editor must rebuild its path from the current
point coordinates. The @racket[draw-curve] helper in @filepath{scene.rkt}
does exactly this. It uses the same @racket['move] and @racket['cubic]
commands, but reads the coordinates from the model rather than a fixed list.

@section{Keep the Control Points in a Model}

The @filepath{scene.rkt} file represents each point with a small Racket
structure and keeps four of them in a list:

@racketblock[
(struct control-point (x y) #:transparent)

(define initial-control-points
  (list (control-point 120 320)
        (control-point 195 94)
        (control-point 548 108)
        (control-point 665 324)))
]

The @racket[draw-editor] function accepts the entire list and draws the curve,
its straight control polygon, and four draggable markers. Its curve helper
builds a path from the current values, using the same @racket['move] and
@racket['cubic] commands as above.

Instead of mutating a native path, we can replace one point in the list:

@racketblock[
(define (move-control-point points index x y)
  (unless (and (exact-nonnegative-integer? index) (< index (length points)))
    (raise-argument-error 'move-control-point "valid control-point index" index))
  (for/list ([point (in-list points)] [i (in-naturals)])
    (if (= i index) (control-point x y) point)))
]

The function returns a new list. All points except the selected one remain
unchanged; it does not mutate a Skia path. For example, moving @tt{P1}
changes only the second point:

@interaction-interaction[
(second (move-control-point initial-control-points 1 302 150))
(second initial-control-points)
]

The editor also draws a thin control polygon connecting P0 to P1 to P2 to P3.
It helps us see which points influence the curve. The geometry and colored
point markers come from the @racket[draw-guides], @racket[draw-curve], and
@racket[draw-points] helpers in @filepath{scene.rkt}:

@(editor-stage-pict 'guides #:scale 0.60)

The editor stores the latest list in @racket[points]. The drawing function
reads it; it does not own or modify it. The full editor adds the heading and
instructions shown in the opening figure.

@section{Find a Point Under the Mouse}

When the user presses the mouse button, the editor must decide whether the
pointer is near one of the four points. A marker should be easy to select,
even when the pointer is not exactly over its center.

The @racket[hit-control-point] function uses an 18-unit hit radius, larger
than the 10-unit visible marker. The diagram enlarges both radii by a factor
of three so you can compare them. The outer ring is explanatory: it does not
appear in the interactive editor.

@(editor-hit-area-pict #:scale 0.92)

We can compare squared distances instead of taking square roots:

@racketblock[
(define (squared-distance point x y)
  (+ (sqr (- x (control-point-x point)))
     (sqr (- y (control-point-y point)))))
]

The nearest point inside the hit radius wins. The function returns its list
index, or @racket[#f] when no point is close enough:

@racketblock[
(define (hit-control-point points x y [radius hit-radius])
  (for/fold ([chosen #f] [nearest (* radius radius)]
             #:result chosen)
            ([point (in-list points)] [index (in-naturals)])
    (define distance (squared-distance point x y))
    (if (<= distance nearest)
        (values index distance)
        (values chosen nearest))))
]

The following calls exercise the actual helper from @filepath{scene.rkt}:

@interaction-interaction[
(hit-control-point initial-control-points 120 320)
(hit-control-point initial-control-points 548 108)
(hit-control-point initial-control-points 400 410)
(hit-control-point initial-control-points 213 94)
(hit-control-point initial-control-points 214 94)
]

The last two positions are 18 and 19 units from P1 respectively. Notice
that @racket[0] is a valid selected index in Racket: only @racket[#f]
means that no point was selected.

@section{Receive Mouse Events}

Racket GUI canvases receive mouse input through their @racket[on-event]
method. A small subclass forwards each event to our handler:

@racketblock[
(define (with-mouse-events base%)
  (class base%
    (define/override (on-event event)
      (handle-pointer-event this event))
    (super-new)))
]

Both the ordinary Racket @racket[canvas%] and Skia's @racket[gpu-canvas%]
extend the same GUI canvas interface. The handler can therefore be reused
without rewriting the editor for each backend.

A mouse event supplies its position through @racket[(send event get-x)] and
@racket[(send event get-y)]. These are @emph{logical window coordinates};
they are not GPU framebuffer pixel coordinates.

@section{Drag a Control Point}

The editor keeps one extra piece of state, @racket[selected-index]. Initially
it is @racket[#f]: no point is being dragged.

On a left-button press, hit testing selects a point. During a drag, we
replace that point's coordinates. Releasing the left button ends the drag:

@racketblock[
(cond
  [(send event button-down? 'left)
   (set! selected-index (hit-control-point points x y))
   (request-frame)]
  [(send event button-up? 'left)
   (move-selected! widget x y)
   (set! selected-index #f)
   (request-frame)]
  [(and selected-index (send event dragging?))
   (move-selected! widget x y)])
]

The @racket[move-selected!] helper obtains the current client size and keeps
points inside the window before calling @racket[move-control-point]. The
selected point gets a bright outline so the drag is visible. A mouse-down
chooses an index, mouse motion replaces that point in the model, and mouse-up
clears the index.

@(editor-before-and-after-pict)

The two illustrations are produced by @racket[draw-editor]. Only @tt{P1}
moved, from (195, 94) to (302, 150). The endpoints, other handle, control
polygon, and visible curve are then drawn again from the new list.

@section{Request Another Frame}

Mouse handling changes the model. Drawing happens later, when the GUI asks
for a frame. The editor has one redraw helper for both window types:

@racketblock[
(define (request-frame)
  (when (and view (not closed?))
    (if (eq? renderer 'gpu)
        (send view request-gpu-render)
        (send view refresh))))
]

The @racket[refresh] and @racket[request-gpu-render] methods request a later
drawing callback. Repeated requests can be combined. A mouse event should not
try to draw directly or keep a canvas from an earlier frame.

This also explains the difference from Tutorial 14: animation requests frames
as time passes. This editor requests them when its points change, or when the
window needs repainting. It needs no animation timer.

@section{Display the CPU Editor}

The CPU window creates an ordinary Skia surface inside its paint callback.
The drawing is still done with @racket[surface-canvas]:

@racketblock[
(define (paint-cpu-frame widget dc)
  (define-values (width height) (send widget get-client-size))
  (when (and (positive? width) (positive? height))
    (with-skia ([surface (make-surface width height)])
      (draw-editor (surface-canvas surface)
                   points width height selected-index)
      (send dc draw-bitmap (surface->bitmap surface) 0 0))))
]

The Racket GUI drawing context copies the finished bitmap to the window;
it is not used to draw the curve. This is the same separation used in
Tutorial 14. The @racket[with-skia] form promptly releases the per-frame
surface after its pixels have been copied.

@section{Draw Directly into a GPU Frame}

The GPU version changes where the Skia canvas comes from. There is no CPU
bitmap and no per-frame readback:

@racketblock[
(define (paint-gpu-frame frame)
  (define canvas (gpu-frame-canvas frame))
  (with-canvas-state canvas
    (canvas-scale! canvas
                   (gpu-frame-scale-x frame)
                   (gpu-frame-scale-y frame))
    (draw-editor canvas points
                 (gpu-frame-logical-width frame)
                 (gpu-frame-logical-height frame)
                 selected-index)))
]

A GPU framebuffer has physical pixel dimensions, while mouse coordinates
use logical dimensions. Scaling the canvas makes the same point coordinates
work on ordinary and Retina displays. The @racket[draw-editor] function
remains unchanged.

The complete program chooses Metal on macOS, Direct3D 12 on Windows x64, and
OpenGL on Linux. The choice determines the backend, not whether that backend
will work on a particular computer. To run without GPU support, select
@racket['raster] explicitly; drawing failures are not silently retried on
the CPU.

@section{Reset, Close, and Run the Editor}

The Reset button restores @racket[initial-control-points] and requests a
fresh frame. The Close button and the native window close control both call
@racket[close-editor]. That function closes the GPU presenter, when present,
before hiding the window. A CPU surface is already released after each paint.

From a checkout with Skia installed, start the CPU version:

@verbatim{
racket scribblings/tutorials/interaction/bezier-editor.rkt --renderer raster
}

For a supported GPU backend, use:

@verbatim{
racket scribblings/tutorials/interaction/bezier-editor.rkt --renderer gpu
}

Click near one of the four colored points, hold the left mouse button, and
drag. The curve should follow the pointer. The coordinates stay logical on
both renderers, so dragging should behave the same at different display
scales. Small rendering differences between CPU and GPU are possible.

@section{The Complete Programs}

The @filepath{bezier-editor.rkt} file contains the GUI, mouse events, CPU/GPU
presentation, Reset button, and window cleanup:

@codeblock[(file->string editor-source)]

The @filepath{scene.rkt} file contains the data model, hit testing, cubic
curve, paints, and the actual drawing functions. It also saves a static
@filepath{bezier-editor.png} when run directly:

@codeblock[(file->string scene-source)]

@section{Try It}

Try dragging @tt{P1} and @tt{P2} to opposite sides of the straight
line between the endpoints. Can you make an S-shaped cubic? Try moving an
endpoint instead, and see how the entire curve changes.

Try changing the 18-unit hit radius in @filepath{scene.rkt}. What changes
about selecting a point? Then change the marker radius while leaving the hit
radius unchanged. The displayed marker and clickable region are separate
choices.

Try the editor with both renderers and resize the window. The point positions
remain logical coordinates; only the available drawing area changes.

@section{Where to Go From Here}

This tutorial combined Skia paths, a small data model, hit testing, GUI mouse
events, and redraw requests. No new drawing API was needed to make a path
interactive.

The next natural step is zooming and panning. That requires mapping mouse
positions between window coordinates and a transformed drawing coordinate
system. Keyboard controls, undo/redo, snapping, and multi-segment paths also
belong in more advanced editors.
