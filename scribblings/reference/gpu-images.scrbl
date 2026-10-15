#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-images"]{GPU Images and Filtering}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

A @deftech{GPU image} is an owned image tied to one GPU context. It also satisfies
@racket[image?]. Draw a GPU image with the ordinary canvas image-drawing
functions, such as @racket[draw-image] and @racket[draw-image-rect], while
its context is active. CPU-only image operations require an explicit transfer.
GPU images can also be used to construct image shaders. A texture-backed
result is not an independently usable CPU image. Use the explicit operations in
@secref["skia-gpu-transfers"] to cross that boundary.

Native image operations require the owner thread, a live image, and the correct
active context. Resources derived from a GPU image retain their GPU dependency;
closing the source wrapper does not make those derived resources context-free.
Retire all such resources before closing the context. Neither image upload nor
snapshot creation implicitly presents a window or returns CPU pixels.

@section{Residency and Context Association}

@defproc[(gpu-image? [v any/c]) boolean?]{
Returns whether @racket[v] is an image whose wrapper has GPU ownership. It remains
true after the image is closed. An ordinary encoded or lazy image does not
become a GPU image merely because Skia caches a texture for it while drawing.
}

@defproc[(image-residency [image image?]) (or/c 'cpu 'gpu)]{
Returns the live wrapper's ownership classification. This query rejects a closed
image, but does not require a GPU activation or inspect native texture storage.
The result is not a report of all cached copies or a readiness test.
}

@defproc[(skia-resource-gpu-context [resource skia-resource?]) (or/c gpu-context? #f)]{
Returns the existing context wrapper associated with a live resource, or false
when the resource has no GPU dependency. Borrowed canvases are not accepted.
This query requires no GPU activation and creates no new native reference.
The result is not an independently owned context and does not establish that
it is ready for execution. A closed resource raises an exception.
}

@defproc[(gpu-image-info [image gpu-image?]) (and/c hash? immutable?)]{
Returns detached metadata after verifying native texture backing and validity
for the owning active context. The hash includes @racket['width],
@racket['height], @racket['backend], @racket['context_generation],
@racket['unique_id], @racket['texture_backed], and @racket['context_matches].
The unique identifier is process-local, not a pixel-content hash. This operation
does not read pixels; its readback-path description is informational.
}

@section{Upload, Snapshots, and Subsets}

@defproc[(gpu-upload-image [context gpu-context?] [image image?]
                           [#:mipmapped? mipmapped? boolean? #f]
                           [#:budgeted? budgeted? boolean? #t]) gpu-image?]{
Returns an independently owned, valid texture-backed image for the active
@racket[context]. A CPU image is uploaded. A GPU image from that same context
may reuse its native storage; the result still owns its own reference. The
source wrapper is not consumed. An image from another GPU context is rejected;
read it back explicitly before uploading it to a different context.

The image dimensions must fit the reported maximum texture size and the
wrapper's four-byte-per-pixel dimension check. The mipmap and budget flags are
requests, not confirmation of allocation size or effective cache usage.
Native failure raises rather than returning a CPU image. An implicit upload
must not narrow F32 storage, or reduce F16 storage to an integer format; an
incompatible native result is released and rejected.
}

@defproc[(gpu-surface-snapshot [surface gpu-surface?]) gpu-image?]{
Returns an independently owned GPU image of the surface's current contents.
The native save/layer stack must be balanced at save count 1. Later drawing to
or closure of the surface does not alter the image's captured contents. The
snapshot remains tied to the same context and must be retired before context
closure. This operation performs no CPU pixel readback and does not promise
that preceding GPU commands have completed.
}

@defproc[(gpu-image-subset [image gpu-image?]
                          [x exact-nonnegative-integer?] [y exact-nonnegative-integer?]
                          [width exact-positive-integer?] [height exact-positive-integer?])
         gpu-image?]{
Returns an independently owned GPU image of a nonempty integer rectangle fully
inside @racket[image]. The dimensions also undergo the ordinary checked image
size and byte-limit checks. The source is unchanged and the result remains
associated with its context. Native storage may be shared; this is not a CPU
copy, a resampling operation, or a transfer to another GPU context.
}

@section{Filtering and Result Placement}

@defproc[(gpu-image-apply-filter
          [image gpu-image?] [filter image-filter?]
          [#:subset subset (or/c list? vector? #f) #f]
          [#:clip clip (or/c list? vector?)])
         (values gpu-image?
                 (and/c (vector/c exact-nonnegative-integer? exact-nonnegative-integer?
                                  exact-positive-integer? exact-positive-integer?) immutable?)
                 (and/c (vector/c exact-integer? exact-integer?) immutable?))]{
Applies @racket[filter] in the image's active context. Returns an owned GPU image,
a valid source rectangle within that image, and its destination offset. The
last two results are detached immutable vectors. They have the same placement
convention as @racket[image-apply-filter]: extract the valid rectangle and place
its upper-left corner at the returned offset. Do not assume the entire returned
image is the filter's valid output.

Both input rectangles use exact x, y, width, and height components. Extents must
be from 1 through 32768, and edges must fit signed 32-bit integers. A false subset
selects the entire input; otherwise it must be inside the image. The required
clip bounds the result in filter coordinates. Intermediate edges after
subtracting the subset origin must also fit signed 32-bit arithmetic. The image
and clip undergo conservative sixteen-byte-per-pixel budget checks, and the clip
and result must fit the context's texture-size limit.

A context-independent filter is accepted. A filter with GPU dependencies must
belong to this same context. The output must be a valid same-context texture and
must not narrow the source's floating-point storage precision. An empty or failed
native result raises; it is not fabricated into a successful empty image.
Neither CPU fallback nor an implicit readback occurs.

This helper applies an offset filter and uses both placement results. It expects
the receiver and image to belong to the same active context.

@racketblock[
(require skia skia/gpu)
(define (draw-shifted-gpu-image canvas image)
  (with-skia ([filter (make-offset-image-filter 2 1)])
    (define-values (filtered valid offset)
      (gpu-image-apply-filter image filter #:clip '(0 0 12 12)))
    (call-with-skia-resource filtered
      (lambda (owned)
        (with-skia ([part (gpu-image-subset owned
                           (vector-ref valid 0) (vector-ref valid 1)
                           (vector-ref valid 2) (vector-ref valid 3))])
          (draw-image canvas part (vector-ref offset 0) (vector-ref offset 1)
                      #:sampling 'nearest))))))
]
}
