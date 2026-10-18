#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/drawables))

@title[#:tag "skia-drawables"]{Recorded Drawables}

@defmodule[skia/drawables #:no-declare]
@(declare-exporting skia skia/drawables #:use-sources (skia/drawables))

For ordinary recording and replay, the @tech{picture} interface is sufficient.
Use a recorded drawable when you need @racket[draw-drawable]'s choice between
storing a reference to a drawable in another recording and immediately replaying
its commands into that recording. Create one with @racket[call-with-drawable] or
convert an existing picture with @racket[picture->drawable].

A @deftech{recorded drawable} owns native drawing content captured from a
@tech{picture}. Playback does not invoke a Racket callback. This API exposes recorded
content, not an application-defined native callback or an editable scene.
A drawable is an @tech{owned resource}; native operations require it to be open
on its owning thread with any GPU resources it uses in their proper context.

The drawable's drawing data remain valid after the source picture is closed.
Conversion does not turn a raster image into vector geometry or discard the
output restrictions of captured resources.

@section{Construction}

@defproc[(drawable? [v any/c])
          boolean?]{
Returns @racket[#t] for a drawable wrapper, including a closed one, and
@racket[#f] otherwise.
}

@defproc[(picture->drawable [picture picture?])
          drawable?]{
Returns an owned recorded drawable capturing the picture's content, culling
bounds, and nominal dimensions. The caller may close the original picture after
successful construction without invalidating the drawable.
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
             (call-with-drawable 40 30
               (lambda (canvas)
                 (set! calls (add1 calls))
                 (with-skia ([ink (make-paint #:color 'red)])
                   (draw-rect canvas 5 5 30 20 ink))))]
            [surface (make-surface 120 50 #:background 'white)])
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-translate 5 10))
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-translate 65 10)
                 #:mode 'immediate)
  calls)
]

@reference-figure["drawable.png"
                  "Two red rectangles replayed from one recorded drawable, once with retained playback and once with immediate playback."]

The callback count is 1 despite two playbacks.
}

@section{Playback and Inspection}

@defproc[(draw-drawable [canvas canvas?]
          [drawable drawable?]
          [#:matrix matrix (or/c matrix? #f) #f]
          [#:mode mode (or/c 'retained 'immediate) 'retained])
          void?]{
Draws the recorded content with an optional affine transform. Retained mode
uses the canvas drawable operation, allowing a recording to keep a native reference
to the drawable for later playback.
Immediate mode executes the drawable's native drawing on the current canvas.
Neither mode calls back into the original Racket authoring function.

The current canvas state and restrictions on resources used by the drawable
still apply. The optional transform is not a projective matrix, and mode does
not choose CPU versus GPU execution.

@racketblock[
(with-skia ([surface (make-surface 120 50 #:background 'white)]
            [drawable
             (call-with-drawable 40 30
               (lambda (canvas)
                 (with-skia ([paint (make-paint #:color 'red)])
                   (draw-rect canvas 5 5 30 20 paint))))])
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-translate 5 10))
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-translate 65 10)
                 #:mode 'immediate))
]

}

@defproc[(drawable->picture [drawable drawable?])
          picture?]{
Creates a picture of the drawable's recorded content.

The picture has the drawable's nominal dimensions and is independently owned.
Closing the drawable afterward does not invalidate it.


@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([drawable
               (call-with-drawable 60 40
                 (lambda (dc)
                   (with-skia ([blue (make-paint #:color "#326DE6")]
                               [orange (make-paint #:color "#EFA02B")])
                     (draw-rounded-rect dc 0 0 60 40 10 10 blue)
                     (draw-circle dc 30 20 10 orange))))]
              [picture (drawable->picture drawable)])
    (draw-picture canvas picture #:x 25 #:y 20)
    (draw-picture canvas picture #:x 120 #:y 35 #:width 80 #:height 54)))
]
@reference-figure["drawable-to-picture-stage10.png"
                  "A drawable is converted to a picture, then replayed once at native size and once scaled."]
}

@defproc[(drawable-bounds [drawable drawable?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns native bounds as a vector of coordinates, width, and height. They are
not a proof of exact visible ink or a replacement for effect padding.
}

@defproc[(drawable-generation-id [drawable drawable?])
          exact-nonnegative-integer?]{
Returns the native generation identifier. It is process-local metadata, not
a persistent content hash or a count of authoring callbacks.
}

@defproc[(drawable-approximate-bytes-used [drawable drawable?])
          exact-nonnegative-integer?]{
Returns the native storage estimate. It is not the total memory used by
all referenced images, typefaces, or other resources.
}

@defproc[(drawable-notify-drawing-changed! [drawable drawable?])
          void?]{
Invalidates generation metadata. It does not edit or replace captured commands,
rerun the authoring callback, or revive a closed resource. The next generation
query can report a new identifier while the recorded drawing remains the same.
}

@section{Additional Visual Example}

@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)]
            [drawable
             (call-with-drawable 50 35
               (lambda (canvas)
                 (with-skia ([paint (make-paint #:color "#326DE6")])
                   (draw-rounded-rect canvas 5 5 40 25 7 7 paint))))])
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-compose (matrix-translate 40 45)
                                          (matrix-rotate-degrees -18)))
  (draw-drawable (surface-canvas surface) drawable
                 #:matrix (matrix-compose (matrix-translate 120 30)
                                          (matrix-scale 1.25 1.25)
                                          (matrix-rotate-degrees 18))
                 #:mode 'immediate))
]
@reference-figure["drawable-transformed.png"
                  "The same recorded blue rounded rectangle replayed twice with different affine transforms and playback modes."]
