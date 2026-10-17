#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/canvas-primitives
                     skia/layer-options skia/advanced-layers))

@title[#:tag "skia-layers"]{Canvas Layers}

@(declare-exporting skia skia/canvas-primitives skia/layer-options skia/advanced-layers
                    #:use-sources (skia/canvas-primitives skia/layer-options skia/advanced-layers))

A @deftech{canvas layer} saves canvas state and redirects drawing to an intermediate
compositing target. Restoring the layer composites that target into its parent.
This differs from an ordinary state save, which does not establish a separate
compositing group. Layer creation does not return an independently owned image.

Layer bounds use local coordinates, width, and height. They are not an explicit
canvas @tech{clip}, but Skia can restrict a layer's extent to them. Supply conservative
bounds for all intended content and effects; do not rely on pixels outside a
bound being retained. Use an explicit clip when exact clipping is needed.

Layer creation, drawing, and discard require a live canvas on its owning thread
and, where applicable, its current GPU context. PDF and SVG need not preserve
every layer effect. @tech{Raster fallback} must contain the backdrop
needed by the operation; an isolated group does not capture an outer document's
existing pixels automatically.

@bold{Conceptual diagram.} Per-draw opacity and layer opacity are different
routes. Drawing each translucent rectangle directly on the parent accumulates
coverage in their overlap. A layer instead receives opaque child draws in a
transparent intermediate target, then applies group opacity once when the layer
is restored and composited. A normal state save has no intermediate target.

@reference-figure["concept-layer-compositing.png"
                  "Two checkerboard-backed overlap panels compare separately translucent blue rectangles, whose overlap darkens, with opaque children drawn in a transparent layer and composited once at group opacity, whose overlap stays the same opacity. An arrow labels layer restore/composite."]

@local-table-of-contents[#:style 'immediate-only]

@section{Simple Layers}

@defproc[(call-with-canvas-layer [canvas canvas?]
          [thunk (-> any)]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          any]{
Calls @racket[thunk] inside a layer and returns its results. The protected save
floor prevents the callback from restoring state outside the layer. A
continuation barrier prevents reentry after the scope ends. The prior save
count is restored on return or escape.

The optional paint supplies the compositing settings used when the layer is
restored, not for each drawing operation inside it. Bounds are four drawing
scalars: x, y, width, and height. Width and height must be nonnegative, and the
computed right and bottom edges must also be drawing scalars. A false bound
leaves bounds selection to Skia.

Cleanup composites the layer even when the callback raises. It is state cleanup,
not pixel rollback. An enclosing document helper can separately abort the document.

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

A @deftech{layer-options value} is detached immutable data. It stores bounds and
flags, not a paint, filter, canvas, or GPU object. Construction validates data
without loading Skia. Optional paints and backdrop filters are supplied when
the layer is actually created.

@defproc[(layer-options? [v any/c])
          boolean?]{
Returns @racket[#t] for detached layer options and @racket[#f] otherwise.
}

@defproc[(make-layer-options [#:bounds bounds (or/c #f list? vector?) #f]
          [#:preserve-lcd-text? preserve-lcd-text? boolean? #f]
          [#:initialize-with-previous? initialize-with-previous? boolean? #f]
          [#:f16? f16? boolean? #f])
          layer-options?]{
Copies optional layer bounds and three boolean flags. Preserve-LCD requests
retention of LCD text information where the backend permits it. Initialize-with-previous
requests initialization from the previous layer's content. The F16 flag requests
higher-precision floating-point intermediate storage. These are native requests,
not guarantees of LCD output, a particular allocation, or a vector representation.
All flags default to false.
}

@defproc[(layer-options-bounds [options layer-options?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns the immutable copied bounds or @racket[#f] for unspecified bounds.
}

@defproc[(layer-options-flags [options layer-options?])
          (or/c 0 2 4 6 16 18 20 22)]{
Returns the native flag mask: mask value 2 requests LCD preservation, value 4
requests initialization with previous content, and value 16 requests F16 storage.
The constructor, not an arbitrary integer mask, is the public options interface.
}

@defproc[(layer-options-preserve-lcd-text? [options layer-options?])
          boolean?]{
Reports whether the LCD-preservation flag was requested, not whether a backend fulfilled it.
}

@defproc[(layer-options-initialize-with-previous? [options layer-options?])
          boolean?]{
Reports whether the previous-content initialization flag was requested, not whether a backend
fulfilled it.
}

@defproc[(layer-options-f16? [options layer-options?])
          boolean?]{
Reports whether the F16-storage flag was requested, not whether a backend fulfilled it.
}

@section{Backdrop Filters and Protected Layers}

@defproc[(call-with-canvas-layer-rec [canvas canvas?]
          [thunk (-> any)]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f]
          [#:clip clip (or/c #f list? vector?) #f])
          any]{
Calls @racket[thunk] inside a protected layer and returns its results.
The function must not require keyword arguments. The canvas owner is kept alive
and cannot be closed during the scope. The protected save floor prevents
restoring state outside the layer, and continuation reentry is prohibited.

The @racket[backdrop] filter processes existing destination content used to
initialize the layer, not new drawing inside it. The options' bounds are not
an explicit clip. The canvas, paint, and filter must satisfy their native-use
and GPU-context requirements.

A supplied clip is an explicit local-coordinate rectangular intersection applied
in an outer saved state before layer creation. This is distinct from the bounds
stored in options. Cleanup restores the prior state and composites even after a
callback exception; it does not undo previously drawn pixels.

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

All three panels use the same layer bounds and explicit clip.  The bounds are a
conservative allocation/culling hint; the orange rectangle is present because
@racket[#:clip] is what restricts the visible result.  The backdrop operates on
the already-drawn pattern before the callback, whereas
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
Saves a layer and returns the save count from before the push. Restore to that
count to composite and remove the layer. Bounds and paint follow the rules of
@racket[call-with-canvas-layer]. The caller must balance this operation, including on exceptions;
prefer @racket[call-with-canvas-layer] for a protected scope.
}

@defproc[(canvas-save-layer-rec! [canvas canvas?]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f])
          exact-positive-integer?]{
Saves a layer using the options, optional compositing paint, and optional
backdrop filter, as described for @racket[call-with-canvas-layer-rec]. The result
is the previous save count. Referenced native inputs are checked with the canvas
and must satisfy their GPU-context requirements.

The options' bounds are not an explicit clip. The caller must balance this
low-level save; @racket[call-with-canvas-layer-rec] provides protected cleanup.
}

@section{Discarding Target Contents}

@defproc[(canvas-discard! [canvas canvas?])
          void?]{
Discards the validity of existing target content as an optimization hint.
The operation does not clear the canvas to transparent pixels. Completely
overwrite the discarded pixels before reading, blending with, or otherwise using them.
This is not a portable recorded drawing operation or a memory-release guarantee.
}
