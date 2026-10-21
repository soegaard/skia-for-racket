#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-surfaces"]{GPU Surfaces}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

Use a GPU surface for an intermediate drawing that will feed later GPU
operations, such as rendering an offscreen scene and then filtering or
compositing it. Create the target with @racket[make-gpu-surface] and obtain
a reusable image of its content with @racket[gpu-surface-snapshot]. To draw
directly into a window frame, use the @seclink["skia-gpu-presentation"]{presentation API}.

A @deftech{GPU surface} is an owned offscreen drawing target associated with
one @tech{GPU context}. It also satisfies @racket[surface?]. Use the ordinary
Skia drawing operations on the canvas returned by @racket[surface-canvas];
there is no separate GPU canvas drawing language. Creating a GPU surface does
not create a window or present its contents.

Native surface operations require the creating Racket thread and a live
@tech{GPU activation} for the owning context. A @tech{borrowed canvas}
expires with the activation that supplied its @tech{GPU lease}, even when the surface
remains open. Obtain a fresh canvas in each later activation. Close the surface
with @racket[skia-close!] before closing its context. Closing the wrapper queues
native release; it is not a pixel transfer or a completion fence.

@section{Construction}

@defproc[(gpu-surface? [v any/c]) boolean?]{
Returns whether @racket[v] is a GPU-surface wrapper. A closed GPU surface still
satisfies the predicate. The predicate does not activate or test its context.
}

@defproc[(make-gpu-surface
          [context gpu-context?] [width (integer-in 1 32768)] [height (integer-in 1 32768)]
          [#:background background color? 'transparent]
          [#:color-space space (or/c color-space? #f) #f]
          [#:sample-count samples (integer-in 0 64) 0]
          [#:opaque? opaque? boolean? #f] [#:budgeted? budgeted? boolean? #t]
          [#:color-type color-type
           (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565
                 'rgba-1010102 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'premul 'opaque #f) #f]
          [#:surface-properties properties surface-properties? (make-surface-properties)])
         gpu-surface?]{
Creates and initializes an owned surface in @racket[context]. The context must
already be active. The surface keeps a reference to its context and its own
native reference to @racket[space], when supplied. The caller may close the
original color-space wrapper after successful construction. The surface origin is top-left.

The @racket[properties] argument supplies the surface's @tech{pixel geometry} and
rendering flags; see @secref["skia-surface-properties"]. The default leaves pixel
geometry unspecified and all flags unset.

The omitted alpha type selects @racket['opaque] when @racket[opaque?] is true,
and @racket['premul] otherwise. An explicit @racket['premul] conflicts with
@racket[opaque?] set to true. Opaque targets require an opaque background.
RGBX8888, Gray8, and RGB565 require opaque alpha; Alpha8 has no color-space
interpretation and rejects a nonfalse @racket[space]. @tech{Unpremultiplied alpha} is
not a supported drawing-target format.

The format-aware storage estimate must fit @racket[current-skia-byte-limit].
The dimensions must also fit the context's render-target limit. The requested
format must report a positive maximum sample count, and @racket[samples] must
not exceed it. Zero requests no multisampling; Skia may round a positive
request to a supported count. The actual count is not exposed for this owned
target. A supported query does not guarantee that allocation will succeed.

The @racket[budgeted?] argument selects native cache accounting, not a hard
memory limit. Setting it to false does not bypass the wrapper's size checks.
If Skia returns a surface that does not belong to the requested GPU context or
does not match the requested surface properties, dimensions, or color/alpha
format, the constructor releases it and raises an exception. It does not
substitute a CPU target or a different pixel format, or return an uninitialized
or partially constructed surface.

The following helper returns a GPU image of a red tile. The surface and paint
are closed before it returns; the image remains owned by the caller and its
context must remain open.

@racketblock[
(require skia skia/gpu)
(define (gpu-red-tile context)
  (call-with-gpu-context context
    (lambda ()
      (with-skia ([surface (make-gpu-surface context 4 3 #:background 'white)]
                  [paint (make-paint #:color 'red #:antialias? #f)])
        (draw-rect (surface-canvas surface) 0 0 4 3 paint)
        (gpu-surface-snapshot surface)))))
]
}

@section{Format Support and Metadata}

@defproc[(gpu-surface-format-info
          [context gpu-context?]
          [color-type (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565
                           'rgba-1010102 'rgba-f16 'rgba-f32)])
         (and/c hash? immutable?)]{
Queries the active context's native format limits. The returned hash table identifies
its backend and generation, the color type, @racket['max_sample_count], and
@racket['max_render_target_size]. The @racket['renderable] field is true exactly
when the maximum sample count is positive.

This is a capability query, not an allocation test. The
@racket['allocation_verified] and @racket['actual_sample_count] fields are false.
It performs no pixel readback. Context creation and this query must still
succeed on the selected machine before the report is available.
}

@defproc[(gpu-surface-info [surface gpu-surface?]) (and/c hash? immutable?)]{
Returns metadata after checking the live surface's native context and
backend association. The surface must be used in its owning activation.
The hash table records dimensions, color and alpha types, top-left origin, backend,
context generation, budgeted status, surface properties, and the requested and
maximum sample counts. The actual sample count remains false, not a copy of
the request. The report does not read pixels or certify visible presentation.
}

@defproc[(gpu-surface->image-info [surface gpu-surface?]) image-info?]{
Returns a @tech{pixel description}. The dimensions and color/alpha type are
read from a temporary texture-backed snapshot, and the surface's color space
is copied into a descriptor. The snapshot is released before returning.
The owning activation is required, but no CPU pixel readback occurs.
}
