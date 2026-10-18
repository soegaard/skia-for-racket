#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/canvas-primitives
                     skia/layer-options skia/advanced-layers))

@title[#:tag "skia-layers"]{Canvas Layers}

@(declare-exporting skia skia/canvas-primitives skia/layer-options skia/advanced-layers
                    #:use-sources (skia/canvas-primitives skia/layer-options skia/advanced-layers))

A @deftech{canvas layer} groups drawing operations so that opacity, blending,
or a filter can be applied to the group. Creating a layer saves the canvas state
and directs subsequent drawing to a temporary target. Restoring the layer draws
the completed group onto the previous target and restores the saved state.
An ordinary state save does not create such a group.

Layer bounds specify x, y, width, and height in @tech{local coordinates}.
They are not a canvas @tech{clip}, but Skia may omit drawing outside them.
Choose bounds large enough to contain all intended drawing and effects.
Use an explicit clip to restrict drawing to an exact region.

Canvas access follows the rules in @secref["skia-resources"] and, for GPU
canvases, @secref["skia-gpu-surfaces"]. PDF and SVG may not preserve every layer
effect. If an effect uses @tech{raster fallback}, the fallback must include any
previous drawing needed by the effect. Drawing an isolated group does not copy
the document's existing content into the group.

@bold{Conceptual diagram.} Drawing two translucent rectangles directly onto a
surface makes their overlap more opaque. Drawing two opaque rectangles in a
layer, then applying opacity to the completed group, gives the overlap the
same opacity as the rest of the group.

@reference-figure["concept-layer-compositing.png"
                  "Two checkerboard-backed overlap panels compare separately translucent blue rectangles, whose overlap darkens, with opaque children drawn in a transparent layer and composited once at group opacity, whose overlap stays the same opacity. An arrow labels layer restore/composite."]

@local-table-of-contents[#:style 'immediate-only]

@section{Simple Layers}

@defproc[(call-with-canvas-layer [canvas canvas?]
          [thunk (-> any)]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          any]{
Calls @racket[thunk] with no arguments inside a new layer and returns its results.
When the function returns, exits early, or raises an exception, the layer is
drawn onto the previous target and the saved canvas state is restored.

The @racket[paint] argument controls how the completed layer is drawn, not each
drawing operation inside it. The @racket[bounds] argument is a list or vector
of four real numbers: x, y, width, and height. Width and height must be
nonnegative.
The default, @racket[#f], lets Skia choose the bounds.

Restoring past the state saved by this call raises an exception. A continuation
cannot reenter the callback after the call ends.

An exception does not undo drawing in the layer, although an enclosing document
helper may still abort the document. If @racket[thunk] releases the canvas's
target, the layer is not drawn and the saved state is not restored.

@racketblock[
(with-skia ([surface (make-surface 160 100 #:background 'white)]
            [group-paint (make-paint #:color (rgba 0 0 0 128))]
            [ink (make-paint #:color 'red)])
  (define canvas (surface-canvas surface))
  (with-canvas-layer canvas #:paint group-paint #:bounds '(0 0 160 100)
    (draw-rect canvas 20 20 80 60 ink)
    (draw-rect canvas 60 20 80 60 ink))
  (canvas-save-count canvas))
]

Opacity applies to the completed group rather than separately reducing each
rectangle's opacity. The canvas save count returns to 1.

@reference-figure["canvas-layer.png"
                  "Two overlapping red rectangles composited together at half opacity on a white background; the overlap is not darker than the rest of the group."]
}

@defform[(with-canvas-layer canvas-expr options body ...+)
         #:grammar [(options code:blank
                             (code:line #:bounds bounds-expr)
                             (code:line #:paint paint-expr)
                             (code:line #:bounds bounds-expr #:paint paint-expr)
                             (code:line #:paint paint-expr #:bounds bounds-expr))]]{
Like @racket[call-with-canvas-layer], with the body supplying the callback.
Each optional clause may appear at most once, in either order, before the body.
The body is nonempty, may contain internal definitions, and ends with an expression.
}

@section{Layer Options}

The simple layer interface accepts bounds and a paint. Some layers need
additional setup: initial content copied from the current target, F16 color
storage, or preservation of LCD text information.

For these settings, use @racket[call-with-canvas-layer-rec]. Like
@racket[call-with-canvas-layer], it runs a callback inside a layer and restores
the canvas state afterward. Its @racket[#:options] argument accepts a
@tech{layer-options value} describing the requested setup.

A @deftech{layer-options value} describes layer bounds and rendering flags. It
is immutable. Creating an options value does not itself create a layer.
Supply any paint or backdrop filter separately when creating the layer. A
backdrop filter can initialize the layer from filtered existing content.
For manual layer management, pass the same options to
@racket[canvas-save-layer-rec!].

The flags record requests. Whether Skia fulfills a request depends on the
drawing backend.

@defproc[(layer-options? [v any/c])
          boolean?]{
Returns @racket[#t] for a @tech{layer-options value} and @racket[#f] otherwise.
}

@defproc[(make-layer-options [#:bounds bounds (or/c #f list? vector?) #f]
          [#:preserve-lcd-text? preserve-lcd-text? boolean? #f]
          [#:initialize-with-previous? initialize-with-previous? boolean? #f]
          [#:f16? f16? boolean? #f])
          layer-options?]{
Creates a @tech{layer-options value} with the given bounds and rendering flags.
The bounds follow the rules of @racket[call-with-canvas-layer] and are copied
into the result.

The boolean arguments request the following settings:

@itemlist[
 @item{@racket[preserve-lcd-text?] requests preservation of LCD text information.
       @deftech{LCD text rendering} smooths text using separate coverage for
       the red, green, and blue subpixels described by the surface's
       @tech{pixel geometry}.}
 @item{@racket[initialize-with-previous?] requests a copy of the current target's
       pixels as the layer's initial content.}
 @item{@racket[f16?] requests storage with a 16-bit floating-point value for
       each red, green, blue, and alpha component.}]
}

@defproc[(layer-options-bounds [options layer-options?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns the bounds as an immutable vector containing x, y, width, and height,
or @racket[#f] if the bounds are unspecified.
}

@defproc[(layer-options-preserve-lcd-text? [options layer-options?])
          boolean?]{
Reports whether the request to preserve @tech{LCD text rendering} is set.
}

@defproc[(layer-options-initialize-with-previous? [options layer-options?])
          boolean?]{
Reports whether the request to initialize the layer with previous content is set.
}

@defproc[(layer-options-f16? [options layer-options?])
          boolean?]{
Reports whether the request for 16-bit floating-point storage is set.
}

@defproc[(layer-options-flags [options layer-options?])
          (or/c 0 2 4 6 16 18 20 22)]{
Returns the rendering requests as a bit mask: @racket[2] for LCD text
preservation, @racket[4] for initialization with previous content, and
@racket[16] for 16-bit floating-point storage. The mask is the sum of the
requested flags. Use the boolean accessors above to test individual requests.
}

@section{Backdrop Filters and Protected Layers}

@defproc[(call-with-canvas-layer-rec [canvas canvas?]
          [thunk (-> any)]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f]
          [#:clip clip (or/c #f list? vector?) #f])
          any]{
Calls @racket[thunk] with no arguments inside a new layer configured by
@racket[options], and returns its results. The function must not require
keyword arguments. As with @racket[call-with-canvas-layer], the layer is drawn
onto the previous target and the saved state is restored when the function
returns, exits early, or raises an exception.

The @racket[paint] argument controls how the completed layer is drawn.
The @racket[backdrop] filter processes the target's existing content to
initialize the layer. It does not filter new drawing inside the layer.

The @racket[clip] argument restricts drawing to a rectangle in
@tech{local coordinates}. It uses the same x, y, width, and height format as
layer bounds. The rectangle is intersected with the current clip before
creating the layer, and the original clip is restored afterward. The bounds
in @racket[options] do not provide this exact clipping.

The canvas's target cannot be released during the callback. Restoring past
the state saved by this call raises an exception. A continuation cannot
reenter the callback after the call ends.

@racketblock[
(with-skia ([surface (make-surface 16 16)]
            [ink (make-paint #:color 'blue)])
  (define canvas (surface-canvas surface))
  (call-with-canvas-layer-rec
   canvas
   (lambda () (draw-rect canvas 0 0 16 16 ink))
   #:options (make-layer-options #:bounds '(0 0 16 16))
   #:clip '(2 2 12 12)))
]

The clip, rather than the layer bound, excludes the two-pixel border.

@reference-figure["layer-options-clip.png"
                  "A nearest-neighbor enlargement of the actual transparent 16 by 16 layer result. The blue interior follows the explicit clip from two, two through thirteen, thirteen; the two-pixel checkerboard border is only a preview background."]

The layer bounds cover the whole target. Only the explicit clip creates the transparent border.

@racketblock[
(with-skia ([surface (make-surface 420 155 #:background 'white)]
            [base (make-paint #:color "#DCEAF8")]
            [stripe-a (make-paint #:color "#326DE6")]
            [stripe-b (make-paint #:color "#EFA02B")]
            [dot (make-paint #:color "#7D5BA6")]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")]
            [clip-outline (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
            [border (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
  (define (draw-pattern canvas)
    (draw-paint canvas base)
    (for ([x (in-range -10 130 20)])
      (draw-rect canvas x 0 10 85 (if (even? (quotient (+ x 10) 20)) stripe-a stripe-b)))
    (draw-circle canvas 78 42 21 dot))
  (define zone '(25 20 70 46))
  (define (render-panel kind)
    (with-skia ([page (make-surface 120 85)]
                [replace (make-paint #:blend-mode 'src)])
      (define layer-canvas (surface-canvas page))
      (draw-pattern layer-canvas)
      (case kind
        [(empty)
         (call-with-canvas-layer-rec layer-canvas void #:paint replace
                                     #:options (make-layer-options #:bounds zone)
                                     #:clip zone)]
        [(initialized)
         (call-with-canvas-layer-rec layer-canvas void #:paint replace
                                     #:options (make-layer-options #:bounds zone
                                                                   #:initialize-with-previous? #t)
                                     #:clip zone)]
        [(backdrop)
         (with-skia ([blur (make-blur-image-filter 4 4)])
           (call-with-canvas-layer-rec layer-canvas void #:paint replace #:backdrop blur
                                       #:options (make-layer-options #:bounds zone)
                                       #:clip zone))])
      (surface-snapshot page)))
  (with-skia ([empty-image (render-panel 'empty)]
              [initialized-image (render-panel 'initialized)]
              [backdrop-image (render-panel 'backdrop)])
    (define canvas (surface-canvas surface))
    (for ([title '("empty src layer" "initialize previous" "backdrop blur")]
          [x '(12 150 290)])
      (draw-simple-text canvas title x 17 font label))
    (for ([image (list empty-image initialized-image backdrop-image)]
          [x '(12 150 290)])
      (draw-image canvas image x 30)
      (draw-rect canvas x 30 120 85 border)
      (draw-rect canvas (+ x 25) 50 70 46 clip-outline))
    (draw-simple-text canvas "same striped-and-circle backdrop; orange is the explicit clip" 12 135 font label)
    surface))
]
@reference-figure["layer-backdrop-initialization.png"
                  "Three identical striped blue-orange backgrounds with a purple circle are compared inside the same orange explicit clip. An empty source-replace layer clears the middle region, initialize-with-previous preserves it, and a backdrop blur replaces it with a softened view of the previous content."]

All three panels use the same layer bounds and explicit clip. The orange
rectangle marks the clip that restricts the visible result. The backdrop
filters the already-drawn pattern before the callback, whereas
@racket[#:initialize-with-previous?] requests an unfiltered copy of that
previous content.
}

@section[#:tag "skia-layer-manual-state"]{Manual Layer Management}

Use @racket[with-canvas-layer] or @racket[call-with-canvas-layer] for a simple
layer, and @racket[call-with-canvas-layer-rec] for layer options and backdrop
filters. These helpers restore the canvas state automatically. The save
operations in this section leave the layer active after returning. The caller
must restore the returned save count with @racket[canvas-restore-to-count!],
including when drawing raises an exception or exits early.

@defproc[(canvas-save-layer! [canvas canvas?]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          exact-positive-integer?]{
Creates a layer and returns the previous @tech{save count}. Pass the result to
@racket[canvas-restore-to-count!] to draw the completed layer onto the previous
target and restore the saved state. Bounds and paint follow the rules of
@racket[call-with-canvas-layer].
}

@defproc[(canvas-save-layer-rec! [canvas canvas?]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f])
          exact-positive-integer?]{
Creates a layer using the options, paint, and backdrop filter described for
@racket[call-with-canvas-layer-rec]. Returns the previous @tech{save count}.
Pass the result to @racket[canvas-restore-to-count!] to draw the completed layer
onto the previous target and restore the saved state.
}

@section{Discarding Target Contents}

@defproc[(canvas-discard! [canvas canvas?])
          void?]{
Allows Skia to discard the target's current pixels. Use this operation only
when the pixels will be completely overwritten before being read or blended
with new drawing. It does not clear the target to transparent pixels or
guarantee that memory is released. Its effect is not preserved by all recording
backends.
}
