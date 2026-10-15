#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/drawables))

@title[#:tag "skia-drawables"]{Recorded Drawables}

@defmodule[skia/drawables #:no-declare]
@(declare-exporting skia skia/drawables #:use-sources (skia/drawables))

A @deftech{recorded drawable} owns native drawing content captured from a
picture. Playback does not invoke a Racket callback. This API exposes recorded
content, not an application-defined native callback or an editable scene.
A drawable is an @tech{owned resource}; native operations require it to be open
on its owning thread with any retained GPU dependencies in their proper context.

Conversion retains the necessary native content independently. It does not
turn a raster image into vector geometry or discard the output restrictions
of captured resources.

@section{Construction}

@defproc[(drawable? [v any/c])
          boolean?]{
Returns @racket[#t] for a drawable wrapper, including a closed one, and
@racket[#f] otherwise.
}

@defproc[(picture->drawable [picture picture?])
          drawable?]{
Returns an owned recorded drawable capturing the picture's content, culling
bounds, and nominal dimensions. It retains the native drawing information it
needs, so the caller may close the original picture after successful construction.
No Racket drawing callback runs during later playback.
}

@defproc[(call-with-drawable [width (integer-in 1 32768)]
          [height (integer-in 1 32768)]
          [draw (-> canvas? any)])
          drawable?]{
Calls the drawing function once on a temporary picture-recording canvas,
then returns the captured recorded drawable. Callback results are discarded.
The canvas is borrowed only for the callback; it must not escape for later use.
Temporary recording resources are released on success or escape.

Dimensions and the usual four-bytes-per-pixel logical budget follow
@racket[call-with-picture], although the helper records commands rather than
allocating that raster image.

@racketblock[
(define calls 0)
(with-skia ([drawable
             (call-with-drawable 16 16
               (lambda (canvas)
                 (set! calls (add1 calls))
                 (with-skia ([ink (make-paint #:color 'red)])
                   (draw-rect canvas 2 2 8 8 ink))))]
            [surface (make-surface 16 16)])
  (draw-drawable (surface-canvas surface) drawable)
  (draw-drawable (surface-canvas surface) drawable #:mode 'immediate)
  calls)
]

The callback count is 1 despite two playbacks.
}

@section{Playback and Inspection}

@defproc[(draw-drawable [canvas canvas?]
          [drawable drawable?]
          [#:matrix matrix (or/c matrix? #f) #f]
          [#:mode mode (or/c 'retained 'immediate) 'retained])
          void?]{
Draws the recorded content with an optional affine transform. Retained mode
uses the canvas drawable operation, allowing a recording to retain the drawable.
Immediate mode executes the drawable's native drawing on the current canvas.
Neither mode calls back into the original Racket authoring function.

The current canvas state and retained-resource restrictions still apply. The
optional transform is not a projective matrix, and mode does not choose CPU
versus GPU execution.
}

@defproc[(drawable->picture [drawable drawable?])
          picture?]{
Returns an independently owned native picture snapshot with the drawable's
nominal dimensions. Closing the drawable afterward does not invalidate the picture.
}

@defproc[(drawable-bounds [drawable drawable?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns detached native bounds as coordinates, width, and height. They are
not a proof of exact visible ink or a replacement for effect padding.
}

@defproc[(drawable-generation-id [drawable drawable?])
          exact-nonnegative-integer?]{
Returns the native generation identifier. It is process-local metadata, not
a persistent content hash or a count of authoring callbacks.
}

@defproc[(drawable-approximate-bytes-used [drawable drawable?])
          exact-nonnegative-integer?]{
Returns the native storage estimate. It is not the total memory retained by
all referenced images, typefaces, or other resources.
}

@defproc[(drawable-notify-drawing-changed! [drawable drawable?])
          void?]{
Invalidates generation metadata. It does not edit or replace captured commands,
rerun the authoring callback, or revive a closed resource. The next generation
query can report a new identifier while the recorded drawing remains the same.
}
