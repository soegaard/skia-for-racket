#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-images"]{GPU Images and Filtering}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

Use a GPU image when an image will remain in GPU drawing or filtering without
an intermediate CPU pixel copy. Upload a CPU image with @racket[gpu-upload-image]
or capture GPU drawing with @racket[gpu-surface-snapshot], then reuse the result
in the same context. For encoding or direct CPU pixel access, first use an
explicit @tech{GPU readback}.

A @deftech{GPU image} is an owned @tech{image} tied to one @tech{GPU context}. It also satisfies
@racket[image?]. Draw a GPU image with the ordinary canvas image-drawing
functions, such as @racket[draw-image] and @racket[draw-image-rect], while
its context is active. CPU-only image operations require an explicit transfer.
GPU images can also be used to construct image @tech{shaders}. A texture-backed
result is not an independently usable CPU image. Use the explicit operations in
@secref["skia-gpu-transfers"] to cross that boundary.

Native image operations require the owner thread, a live image, and the correct
active context. Resources derived from a GPU image retain their GPU dependency;
closing the source wrapper does not make those derived resources context-free.
Close all such resources before closing the context. Neither image upload nor
snapshot creation implicitly presents a window or returns CPU pixels.

@section{Residency and Context Association}

@defproc[(gpu-image? [v any/c]) boolean?]{
Returns whether @racket[v] is an image whose wrapper has GPU ownership. It remains
true after the image is closed. An ordinary encoded or lazy image does not
become a GPU image merely because Skia caches a texture for it while drawing.
}

@defproc[(image-residency [image image?]) (or/c 'cpu 'gpu)]{
Returns the live wrapper's ownership classification. This query rejects a closed
image, but does not require a @tech{GPU activation} or inspect native texture storage.
The result is not a report of all cached copies or a readiness test.
}

@defproc[(skia-resource-gpu-context [resource skia-resource?]) (or/c gpu-context? #f)]{
Returns the existing context wrapper associated with a live resource, or false
when the resource has no GPU dependency.
@tech[#:key "borrowed canvas"]{Borrowed canvases} are not accepted.
This query requires no GPU activation and creates no new native reference.
The result is not an independently owned context and does not establish that
it is ready for execution. A closed resource raises an exception.
}

@defproc[(gpu-image-info [image gpu-image?]) (and/c hash? immutable?)]{
Returns metadata about the GPU image.

The operation checks that the image is texture-backed and valid for its owning
context, which must be active. The hash table includes @racket['width],
@racket['height], @racket['backend], @racket['context_generation],
@racket['unique_id], @racket['texture_backed], and @racket['context_matches].
The unique identifier is process-local, not a pixel-content hash. This operation
does not read pixels; its readback-path description is informational.
}

@section{Upload, Snapshots, and Subsets}

@defproc[(gpu-upload-image [context gpu-context?] [image image?]
                           [#:mipmapped? mipmapped? boolean? #f]
                           [#:budgeted? budgeted? boolean? #t]) gpu-image?]{
Returns a GPU image for use in @racket[context], uploading the source if needed.

The context must be active. The result is independently owned and backed by a
valid texture. A CPU image is uploaded. A GPU image from that same context
may reuse its native storage; the result still owns its own reference. The
source wrapper is not consumed. An image from another GPU context is rejected;
read it back explicitly before uploading it to a different context.

The image dimensions must fit the reported maximum texture size and the
wrapper's four-byte-per-pixel dimension check. The mipmap and budget flags are
requests, not confirmation of allocation size or effective cache usage.
If Skia cannot create a valid texture-backed image for @racket[context], the
function raises an exception rather than returning a CPU image. An upload
must not narrow F32 storage or reduce F16 storage to an integer format. If the
result violates either precision requirement, the function releases it and
raises an exception.
}

@defproc[(gpu-surface-snapshot [surface gpu-surface?]) gpu-image?]{
Captures the surface's current contents as a GPU image.

The image is independently owned. The native save/layer stack must be balanced
at @tech{save count} 1. Later drawing to or closure of the surface does not alter the
image's captured contents. The
snapshot remains tied to the same context and must be closed before context
closure. This operation performs no CPU pixel readback and does not promise
that preceding GPU commands have completed.
}

@defproc[(gpu-image-subset [image gpu-image?]
                          [x exact-nonnegative-integer?] [y exact-nonnegative-integer?]
                          [width exact-positive-integer?] [height exact-positive-integer?])
         gpu-image?]{
Creates a GPU image from the selected rectangle of @racket[image].

The result is independently owned. The rectangle must be nonempty, use integer
coordinates, and lie fully inside the source image. The dimensions also undergo
the ordinary checked image size and byte-limit checks. The source is unchanged and the result remains
associated with its context. Native storage may be shared; this is not a CPU
copy, a resampling operation, or a transfer to another GPU context.
}

@section{Filtering and Result Placement}

@defproc[(gpu-image-apply-filter
          [image gpu-image?] [filter image-filter?]
          [#:clip clip
           (or/c (list/c exact-integer? exact-integer?
                         (integer-in 1 32768) (integer-in 1 32768))
                 (vector/c exact-integer? exact-integer?
                           (integer-in 1 32768) (integer-in 1 32768)))]
          [#:subset subset
           (or/c #f
                 (list/c exact-integer? exact-integer?
                         (integer-in 1 32768) (integer-in 1 32768))
                 (vector/c exact-integer? exact-integer?
                           (integer-in 1 32768) (integer-in 1 32768))) #f])
         (values gpu-image?
                 (and/c (vector/c exact-nonnegative-integer? exact-nonnegative-integer?
                                  exact-positive-integer? exact-positive-integer?) immutable?)
                 (and/c (vector/c exact-integer? exact-integer?) immutable?))]{
Applies @racket[filter] to the image in its active GPU context.

Returns three values: an owned GPU image, an immutable source-rectangle vector
@racket[#(x y width height)] selecting pixels within that image, and an immutable
offset vector @racket[#(x y)] giving their placement in the input image's
coordinate system. The source rectangle has nonnegative x and y coordinates;
the placement offset can be negative.

Extract the source rectangle and place its upper-left corner at the returned
offset, as with @racket[image-apply-filter]. Do not assume the entire returned
image is valid output or that the offset positions the full image's origin.
See @secref["skia-image-filter-results"] for the shared placement explanation
and diagram.

Both input rectangles use exact x, y, width, and height components. Extents must
be from 1 through 32768, and edges must fit signed 32-bit integers. A false subset
selects the entire input; otherwise it must be inside the image. The required
clip bounds the result in the input image's coordinate system. Intermediate edges
after subtracting the subset origin must also fit signed 32-bit arithmetic. The image
and clip undergo conservative sixteen-byte-per-pixel budget checks, and the clip
and result must fit the context's texture-size limit.

A context-independent filter is accepted. A filter with GPU dependencies must
belong to this same context. The output must be a valid same-context texture and
must not reduce the source's floating-point pixel precision. An empty or failed
native result raises an exception.
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
