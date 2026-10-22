#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "model.rkt"
          "../support/source.rkt"
          (for-label racket skia skia/bitmap skia/gpu
                     (only-in racket/gui/base canvas% mouse-event% key-event%)))
@(define-runtime-path model-source "model.rkt")
@(define-runtime-path scene-source "scene.rkt")
@(define-runtime-path window-source "navigate.rkt")

@title[#:style (tutorial-feedback-style)]{Zoom and Pan — Navigate an Interactive Canvas}
@(tutorial-navigation "navigation")

@section[#:tag "finished-result"]{The Finished Editor}

@(tutorial-figure
   (string-append
    "A cubic curve with two endpoints and two control handles appears over a grid. The "
    "heading and footer stay outside the movable drawing region.")
   (navigation-pict))

This editor lets you move around a Bézier drawing without changing its control
points. Drag a point to reshape the curve. Hold Shift while dragging to move the
view. Scroll to zoom around the pointer, or use the Zoom in and Zoom out buttons.
The Reset view button restores the view without undoing edits to the curve.

@centered{@bold{Change the view, not the geometry. Convert input back into model coordinates.}}

The drawing uses the same Skia paths, paints, and canvases as
@tutorial-link["interaction"]. The model, drawing, and window are separate files
in this example; the complete source set includes all three.

@tutorial-entry["navigation"]

@section{Separate Model Coordinates from Window Coordinates}

The control points belong to the drawing, so they are stored in @emph{model
coordinates}. Mouse positions and the editor's controls use @emph{logical window
coordinates}. Here, window coordinates mean the GUI canvas's client area,
not the desktop or the outer frame. Mouse events report positions relative to
that receiving widget. The view maps model coordinates into this space:

@verbatim{
window-x = pan-x + zoom * model-x
window-y = pan-y + zoom * model-y
}

The @hyperlink["https://docs.racket-lang.org/gui/mouse-event_.html"]{mouse event reference}
describes the client-area coordinates returned by the x and y accessors.
The pan offset is measured in logical window units. The zoom is a positive
scale factor. At zoom 2, a distance of 40 model units occupies 80 logical window
units. Moving the view does not alter either endpoint of that model distance.

The @filepath{model.rkt} file represents the view with ordinary Racket data:

@racketblock[
(struct view-state (zoom pan-x pan-y) #:transparent)
(define home-view (view-state 1 0 0))
]

The conversion functions implement the two directions:

@codeblock[(source-definition model-source 'model->screen)]
@codeblock[(source-definition model-source 'screen->model)]

For a zoom of 2 and pan offset (40, -30), the model point (120, 150) appears at
(280, 270). Converting it back recovers the original point:

@navigation-interaction[
(define view (view-state 2 40 -30))
(call-with-values (lambda () (model->screen view 120 150)) list)
(call-with-values (lambda () (screen->model view 280 270)) list)
]

@(tutorial-figure
   (string-append
    "The model point (120, 150) maps to logical window point (280, 270) with zoom 2 and "
    "pan (40, -30). The inverse mapping recovers the original point.")
   (navigation-coordinate-pict))

The two grids show that same point in the two coordinate systems. Neighboring
grid lines are 50 units apart; the view calculation changes the point's displayed
coordinates. The right-hand coordinates are the ones a mouse event supplies.
The inverse calculation tells the editor which model position that event refers to.

@section{Move the View}

Holding Shift while dragging the drawing region changes the pan offset. The
movement is already in window coordinates, so it must not be multiplied by the
zoom. A 40-unit pointer movement pans by 40 window units even at zoom 2:

@codeblock[(source-definition model-source 'pan-view)]

The following view moves the drawing 50 units right and 30 units down. The title
and instructions remain fixed, while the grid and curve move together:

@(tutorial-figure
   (string-append
    "The grid, curve, and handles move 50 logical units right and 30 down. The heading "
    "and instructions stay fixed.")
   (navigation-pict (pan-view home-view 50 30) #:scale 0.7))

The renderer clips the drawing below the header and above the footer. That keeps
point labels and curve fragments out of the instructions, even after a large pan.

@section{Apply Pan and Zoom to the Canvas}

Inside the drawing region, install the translation and then the scale:

@racketblock[
(with-canvas-state canvas
  (canvas-translate! canvas (view-state-pan-x view) (view-state-pan-y view))
  (canvas-scale! canvas (view-state-zoom view) (view-state-zoom view))
  (draw-path canvas path paint))
]

This composes the model-to-window mapping shown above. Reversing the two calls
would scale the pan offset as well. The @racket[with-canvas-state] form restores
the receiving canvas when drawing finishes.

@(tutorial-figure
   (string-append
    "At zoom 1 the complete curve is visible. At zoom 1.5 around the window origin, the "
    "curve grows and extends beyond the drawing region.")
   (navigation-views))

The left image uses the original view. The right image changes only the zoom
from 1 to 1.5, keeping the pan at zero. The drawing grows around the window
origin, so part of it intentionally moves outside the drawing region. Zooming
around the pointer will be more convenient.

@section{Keep the Point under the Pointer Fixed}

Before changing the zoom, convert the pointer position into model coordinates.
After choosing the new zoom, solve for the pan that puts that model point back
under the same pointer:

@verbatim{
model-point = inverse(old-view, pointer)
new-pan     = pointer - new-zoom * model-point
}

The complete operation is small:

@codeblock[(source-definition model-source 'zoom-at)]

The zoom is clamped before calculating the new pan. Otherwise the anchor could
move when the user reaches a zoom limit. This editor allows zoom from one
quarter to four times the model size.

@(tutorial-figure
   (string-append
    "Zooming from 1 to 2 around P1 keeps that point at (240, 150). The curve and grid "
    "expand away from the stationary pointer ring.")
   (navigation-anchor-pair))

The coral ring marks the pointer at P1. The point and ring stay together at
(240, 150) in both images; the curve and neighboring grid lines move away from
them. Compare this with zooming around (0, 0) in the previous section:

@navigation-interaction[
(define zoomed (zoom-at home-view 240 150 2))
zoomed
(call-with-values (lambda () (screen->model zoomed 240 150)) list)
]

The new pan is (-240, -150). Multiplying P1's model position by 2 would put it
at (480, 300); adding that pan brings it back to (240, 150). The zoom changes
without changing either P1's model position or the pointer's window position.

@section{Keep Handles Easy to Click}

A handle should not become a tiny target when zoomed out or a huge target when
zoomed in. This editor draws its markers and labels @emph{after} leaving the
model transform. Their positions are transformed, but their sizes remain in
logical window units.

@(tutorial-figure
   (string-append
    "Crops around P1 at zoom 1/2, 1, and 2 show the same marker radius of 10 and hit "
    "radius of 18. Grid spacing and the curve stroke change with zoom.")
   (navigation-handle-sizes))

These are equal-sized crops around P1 at zoom 1/2, 1, and 2, shown without further
magnification. The cyan marker still has radius 10, and the coral guide still
has radius 18. The grid spacing and control-point distances change, while the curve's
model-space stroke grows with the zoom. The guide strokes stay thin.
The coral hit-radius guide is explanatory; the editor does not draw it.

Hit testing uses the inverse mapping. An 18-unit clickable radius in the window
corresponds to @racket[(/ 18 zoom)] model units:

@codeblock[(source-definition model-source 'hit-point)]

The visible marker radius is 10 logical units; the hit radius is 18. At zoom 2,
the model-space hit radius is 9, not 18:

@navigation-interaction[
(define close-view (view-state 2 40 -30))
(hit-point initial-points close-view 538 270)
(hit-point initial-points close-view 539 270)
]

The first query is exactly 18 logical units from P1 and selects it. The second is
19 units away and misses. The closest eligible point wins; ties select the later
point in the list, matching the drawing order.

@section{Drag in the Appropriate Coordinate System}

A Shift-drag pans by the difference between successive mouse positions. A point
drag first converts the mouse position into model coordinates, then edits that
point. The two cases therefore use different arithmetic:

@codeblock[(source-definition window-source 'drag-to!)]

The press handler remembers where inside the marker the user grabbed it. Adding
that model-space offset prevents a small jump on the first movement. Control
points are not clamped to the window: panning can reveal points that lie outside
the current view.

The excerpts in this section are local functions from @filepath{navigate.rkt}.
They use that window's @racket[points], @racket[view], and drag state; they are
not standalone programs. The complete window listing below includes the press
handler that initializes those bindings.

The same small class extension attaches event handling to either GUI widget:

@codeblock[(source-definition window-source 'interactive-class)]

Racket sends wheel input to @racket[on-char] as a @racket[key-event%], not to
@racket[on-event] as a @racket[mouse-event%]. The handler uses the wheel event's
pointer coordinates as the zoom anchor. The buttons offer the same operation
around the center of the drawing region. See Racket's
@hyperlink["https://docs.racket-lang.org/gui/key-event_.html"]{keyboard and wheel event reference}.

The program ends a drag on release, on Escape, or when a later event reports
that the left button is no longer held. Zooming also ends an active drag. This
avoids reusing an offset from an earlier view.

@section{Use the Same Coordinates on CPU and GPU}

The CPU adapter draws on a logical-sized Skia surface and presents its bitmap.
The GPU adapter receives a physical framebuffer. It first applies the frame's
backing scale so the editor still receives logical dimensions:

@codeblock[(source-definition window-source 'paint-gpu)]

There are two distinct transformations:

@verbatim{
model coordinates -> pan and zoom -> logical window coordinates
logical window coordinates -> display backing scale -> physical pixels
}

Mouse positions need the inverse of the first mapping only. Dividing them by
the Retina scale again would make dragging incorrect. The CPU bitmap route and
GPU route can have different raster sharpness; this example shares logical
geometry, not a guarantee of identical pixels.

The program selects Metal on macOS, Direct3D on Windows x64, and OpenGL on a
compatible Linux desktop. A selected but unavailable GPU raises an error;
@command-text["--renderer raster"] selects the CPU route explicitly. Both window modes still
require a working graphical session. Run either mode from the directory holding
the three source files:

@verbatim{
racket navigate.rkt --renderer raster
racket navigate.rkt --renderer gpu
}

No animation timer is needed: edits and
view changes request redraws, while normal window exposure can redraw too.

@section[#:tag "try-it"]{Try It}

Zoom to the maximum, then drag both a handle and the background. The two gestures
should still track the pointer. Reset the view and check that your point edit
remains. Then reset the curve and check that this operation does not reset the view.

Try changing the maximum zoom to 8. The handle size and hit radius should remain
unchanged on screen. A useful next exercise is a Fit to Window command that
calculates a view from the control-point bounds.

@section[#:tag "next-steps"]{Where to Go From Here}

This editor used translation and one uniform scale. A rotated or sheared view
needs a general inverse matrix, but the principle is unchanged: invert the view mapping for input.

@tutorial-next["navigation"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["navigation"]

@subsection{The Model: model.rkt}

The model contains the coordinate arithmetic and editable points:

@codeblock[(file->string model-source)]

@subsection{The Drawing: scene.rkt}

The scene uses ordinary Skia drawing and keeps interface labels outside the
model transform:

@codeblock[(file->string scene-source)]

@subsection{The Window: navigate.rkt}

The window contains the input handlers, CPU/GPU adapters, and cleanup:

@codeblock[(file->string window-source)]
