#lang scribble/manual

@(require (for-label racket/base skia/gpu-gui skia/canvas skia/gpu-canvas
                     skia/render-canvas))

@title[#:tag "skia-reference-presentation-gui" #:style 'toc]{Presentation and GUI}

Use these interfaces to display Skia drawing in a Racket GUI window. Choose
first whether your drawing code calls Skia functions directly or uses Racket
drawing-context methods:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Use} @bold{Interface} @bold{Callback receives})
  (list "Direct Skia drawing on the GPU"
        @racket[gpu-canvas%]
        @elem{A @tech{GPU frame} with a borrowed Skia canvas})
  (list "Drawing-context methods on the CPU"
        @racket[skia-canvas%]
        "The widget and a persistent drawing context")
  (list "Drawing-context methods on the GPU"
        @racket[skia-canvas-on-gpu%]
        "The widget and a callback-scoped drawing context")
  (list "Drawing-context methods with a selectable renderer"
        @racket[make-skia-render-canvas]
        "The widget and the selected renderer's drawing context"))]

The corresponding convenience windows are @racket[gpu-window%],
@racket[skia-window-on-gpu%], and @racket[skia-render-window%]. A raster
@racket[skia-canvas%] can be placed in an ordinary Racket GUI frame.

For direct Skia drawing, start with @secref["skia-gpu-widgets"]. For
drawing-context methods, see @secref["skia-gui-canvases"] or
@secref["skia-render-canvases"]. The GPU widgets manage a lower-level
@tech{GPU presenter}, which acquires a drawing target for each frame and
requests its display. Use the presenter interface when you need its rendering
state or more direct control over redraw requests.

The interfaces share backend selection and close-method names, but differ in
drawing-context lifetime and when cleanup can run. See
@secref["skia-gui-backend-options"] for backend choices and
@secref["skia-gui-cleanup"] for cleanup states. Raw frame
canvases use physical pixels; the drawing-context interfaces apply the
window's logical-to-pixel scaling, as explained in
@secref["skia-gpu-frame-geometry"].

@local-table-of-contents[]

@include-section["gpu-presentation.scrbl"]
@include-section["gpu-widgets.scrbl"]
@include-section["gui-canvases.scrbl"]
@include-section["render-canvases.scrbl"]
