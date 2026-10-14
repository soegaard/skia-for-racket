#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/canvas-primitives
                     skia/layer-options skia/advanced-layers))

@title[#:tag "skia-layers"]{Canvas Layers}

@(declare-exporting skia skia/canvas-primitives skia/layer-options skia/advanced-layers
                    #:use-sources (skia/canvas-primitives skia/layer-options skia/advanced-layers))

A @deftech{canvas layer} saves canvas state and redirects drawing to an intermediate
compositing target. Restoring the layer composites that target into its parent.
This differs from an ordinary state save, which does not establish a separate
compositing group. Layer creation does not return an independently owned image.

Layer bounds use local coordinates, width, and height. They are not an explicit
canvas clip, but Skia can restrict a layer's extent to them. Supply conservative
bounds for all intended content and effects; do not rely on pixels outside a
bound being retained. Use an explicit clip when exact clipping is needed.

Layer creation, drawing, and discard require a live canvas on its owning thread
and, where applicable, its current GPU context. PDF and SVG need not preserve
every layer effect. Raster fallback must contain the backdrop
needed by the operation; an isolated group does not capture an outer document's
existing pixels automatically.

@section{Simple Layers}

@defproc[(canvas-save-layer! [canvas canvas?]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          exact-positive-integer?]{
Saves a layer and returns the save count from before the push. Restore to that
count to composite and remove the layer. A false bound leaves native bounds
selection to Skia. The paint is optional; its compositing settings are captured
for restore rather than applied as a paint to every drawing command inside.

Bounds are four drawing-scalar values with nonnegative extents and valid computed
edges. The caller must balance this low-level operation, including on exceptions;
prefer @racket[call-with-canvas-layer] for a protected scope.
}

@defproc[(call-with-canvas-layer [canvas canvas?]
          [thunk (-> any)]
          [#:bounds bounds (or/c #f list? vector?) #f]
          [#:paint paint (or/c paint? #f) #f])
          any]{
Calls a zero-argument procedure inside a layer, preserving its return values.
The layer establishes a protected save floor and a continuation barrier, and
restores the prior save count on return or escape.

Cleanup composites the layer even when the callback raises. It is state cleanup,
not pixel rollback. An enclosing document helper can separately abort the document.
The bound and paint meanings are those of @racket[canvas-save-layer!].

@racketblock[
(with-skia ([surface (make-surface 16 16)]
            [group-paint (make-paint #:color (rgba 0 0 0 128))]
            [ink (make-paint #:color 'red)])
  (define canvas (surface-canvas surface))
  (with-canvas-layer canvas #:paint group-paint #:bounds '(0 0 16 16)
    (draw-rect canvas 2 2 8 8 ink)
    (draw-rect canvas 6 2 8 8 ink))
  (canvas-save-count canvas))
]

Opacity applies to the completed group rather than separately reducing each
rectangle's opacity. The canvas save count returns to 1.
}

@defform[(with-canvas-layer canvas-expr option ... body ...+)
         #:grammar [(option (code:line #:bounds bounds-expr)
                            (code:line #:paint paint-expr))]]{
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

@defproc[(canvas-save-layer-rec! [canvas canvas?]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f])
          exact-positive-integer?]{
Saves a layer using the options, optional composite paint, and optional
backdrop filter. Returns the previous save count. The backdrop operates on the
previous destination content used to initialize the layer, not on drawing that
will occur later inside it. Referenced native inputs are validated with the
canvas and their required context affinity.

The options' bounds are not an explicit clip. The caller must balance this
low-level save; @racket[call-with-canvas-layer-rec] provides protected cleanup.
}

@defproc[(call-with-canvas-layer-rec [canvas canvas?]
          [thunk (-> any)]
          [#:options options layer-options? (make-layer-options)]
          [#:paint paint (or/c paint? #f) #f]
          [#:backdrop backdrop (or/c image-filter? #f) #f]
          [#:clip clip (or/c #f list? vector?) #f])
          any]{
Calls the zero-argument procedure inside a protected advanced layer and
preserves its return values. The procedure must not require keyword arguments.
The canvas owner is pinned during the layer scope, its save floor is protected,
and continuation reentry is prohibited.

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
}

@defproc[(canvas-discard! [canvas canvas?])
          void?]{
Discards the validity of existing target content as an optimization hint.
The operation does not clear the canvas to transparent pixels. Completely
overwrite the discarded pixels before reading, blending with, or otherwise using them.
This is not a portable recorded drawing operation or a memory-release guarantee.
}
