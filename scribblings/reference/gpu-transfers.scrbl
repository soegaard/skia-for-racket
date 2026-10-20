#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu))

@title[#:tag "skia-gpu-transfers"]{GPU Readback and One-Shot Rendering}

@(declare-exporting skia/gpu #:use-sources (skia/gpu))

Use readback when GPU-rendered content must be encoded as an image file,
examined pixel by pixel on the CPU, or passed to a CPU-only image operation.
If the result will only be drawn again in the same GPU context, keep it as a
@tech{GPU image} instead. For a single GPU drawing that should return a CPU
image, @racket[render-gpu->raster-image] manages rendering and readback together.

A @deftech{GPU readback} explicitly copies drawing results into CPU memory.
The operations here are synchronous and can wait for submitted work. Except
for the one-shot constructor, they require the owning context to be active.
No readback performs presentation or silently switches failed GPU rendering
to the CPU.

@local-table-of-contents[#:style 'immediate-only]

@section{One-Shot Rendering}

@defproc[(render-gpu->raster-image
          [width (integer-in 1 32768)] [height (integer-in 1 32768)]
          [draw (-> canvas? any)] [#:backend backend (or/c 'opengl 'metal 'direct3d)]
          [#:background background color? 'transparent]
          [#:provider provider (or/c gpu-provider? #f) #f]
          [#:adapter adapter (or/c 'hardware 'warp #f) #f]
          [#:adapter-index index (or/c (integer-in 0 4294967294) #f) #f]) image?]{
Runs @racket[draw] on the GPU and returns the result as an image in CPU memory.

The helper creates a context and an offscreen surface using RGBA8888 pixels
with premultiplied alpha. It calls @racket[draw] once with the surface's borrowed
Skia canvas, then reads back the pixels. The returned image is an owned resource.
The callback must accept one positional argument and no required keywords.
Its zero, one, or multiple results are ignored.

The backend is required; there is no automatic backend selection or CPU fallback.
OpenGL requires a matching provider. Metal and Direct3D create owned native
hosts and reject a supplied provider. Direct3D defaults to hardware adapter zero;
WARP requires index zero. Adapter selection is rejected for other backends.
These choices have the same platform and availability restrictions as
@racket[make-gpu-context]. The call must occur outside existing GPU activations.

The dimensions undergo the ordinary four-byte-per-pixel budget check before
context creation, followed by the native surface limits. The callback must
balance its canvas state and release any GPU-dependent resources it creates.
The supplied canvas expires when its activation ends and must not escape for
later drawing.

The helper closes its surface and context before returning the CPU image.
Drawing, readback, and cleanup failures propagate. If a CPU image has already
been read back but context cleanup fails, the helper closes that image instead
of returning it. Callback side effects are not rolled back, and failed cleanup
is not silently replaced by abandonment or a second rendering attempt.

On macOS with an available Metal backend, calling this helper returns a CPU
image of a blue rectangle. Defining the helper alone does not create a context.

@racketblock[
(require skia skia/gpu)
(define (render-metal-tile)
  (render-gpu->raster-image 8 6
    (lambda (canvas)
      (with-skia ([paint (make-paint #:color 'blue #:antialias? #f)])
        (draw-rect canvas 0 0 8 6 paint)))
    #:backend 'metal #:background 'white))
]
}

@section[#:tag "skia-gpu-existing-readback"]{Readback from Existing GPU Resources}

For one drawing callback and a CPU image result, use @racket[render-gpu->raster-image].
The readback operations in this section use an existing GPU surface or image.
They are useful when a context is reused across drawings or when a particular
pixel format is needed. The caller manages resource lifetimes and must activate
the owning context with @racket[call-with-gpu-context].

A surface readback requires a balanced save/layer stack at @tech{save count} 1.
Reading a GPU image first draws it into a temporary GPU surface in the same
context. This uses one-to-one scaling, nearest sampling, and source replacement.
The temporary surface preserves the source color type and color interpretation.
Opaque images use opaque storage; other images use premultiplied storage.
Creating the temporary surface can fail if its format is unsupported or
allocation fails. This is not a raw texture-memory download.

The byte helpers convert to eight-bit RGBA. The typed buffer and raster-image
helpers preserve the selected format by default, including supported F16/F32
storage. Returned CPU resources are independent of the GPU context, but retain
their ordinary CPU thread and lifetime rules.

@subsection{Eight-Bit Copies}

@defproc[(gpu-surface->rgba-bytes [surface gpu-surface?]
          [#:premultiplied? premultiplied? boolean? #f]
          [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Reads the surface's pixels into a new mutable RGBA byte string in CPU memory.

Each channel occupies eight bits, and rows have no padding. The byte-string
length is four times the surface width times its height. The result uses unpremultiplied
alpha unless requested otherwise. A supplied live color space selects the
readback destination interpretation; false uses the surface's native color
space. The color-space argument accepts a resource, not a color-space descriptor.

The operation performs a @tech{GPU flush}, @tech{GPU submission}, and
@tech{GPU wait} before copying pixels. Float or
higher-bit-depth sources are explicitly converted to eight-bit output.
The output allocation must fit @racket[current-skia-byte-limit]; exceeding it
raises an exception before allocating the output. If GPU synchronization or
pixel readback fails, the function raises an exception without returning a
partial byte string. Later GPU changes do not alter a successful result.
}

@defproc[(gpu-image->rgba-bytes [image gpu-image?]
          [#:premultiplied? premultiplied? boolean? #f]
          [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Like @racket[gpu-surface->rgba-bytes], after drawing the image one-to-one into a
temporary surface in the same context. A false color-space argument preserves
the image's color interpretation through that surface. The image is not consumed.
The temporary GPU resources are retired before the call returns or raises an exception.
}

@subsection{Typed Copies}

@defproc[(gpu-surface->raster-buffer [surface gpu-surface?]
          [#:info info (or/c image-info? #f) #f]
          [#:row-bytes row-bytes (or/c exact-nonnegative-integer? #f) #f]) raster-buffer?]{
Reads the surface's pixels into a new raster buffer in CPU memory.

The buffer is an owned resource, and readback finishes before the call returns.
False @racket[info] uses @racket[gpu-surface->image-info]. An explicit description
selects the destination format and color interpretation, but its dimensions
must equal the surface dimensions. If they differ, the function raises an
exception before allocating the buffer. This is conversion, not scaling.

The stride follows @racket[image-info-storage-layout]; false selects a tight
stride. Row padding is initialized and is not filled from GPU memory. The
source and destination must either both have color-space tags or both be
untagged. If only one is tagged, the function closes the new buffer and raises
an exception before reading pixels. An explicit compatible destination format
permits conversion, including intentional precision reduction. If GPU
synchronization, readback, or pixel conversion fails, the function closes the
new buffer and raises an exception rather than returning it.
}

@defproc[(gpu-image->raster-buffer [image gpu-image?]
          [#:info info (or/c image-info? #f) #f]
          [#:row-bytes row-bytes (or/c exact-nonnegative-integer? #f) #f]) raster-buffer?]{
Like @racket[gpu-surface->raster-buffer], after drawing the image into a temporary
GPU surface in the same context.
A false description uses @racket[image->image-info] for the original image.
Dimensions must match; no resizing is performed. The result owns independent
CPU storage and survives closure of the image and context.
}

@defproc[(gpu-surface->raster-image [surface gpu-surface?]) image?]{
Reads the surface's pixels into an image in CPU memory.

The image is independently owned. The readback preserves the surface's selected
format and color interpretation, rather than always using an intermediate buffer
of eight-bit RGBA pixels. The intermediate CPU buffer is closed after the image
copy. The result is not a GPU image and may outlive the
surface and context.
}

@defproc[(gpu-image->raster-image [image gpu-image?]) image?]{
Like @racket[gpu-surface->raster-image], after drawing the image into a temporary
GPU surface in the same context. Readback preserves the image's format and color
interpretation. The source remains owned by its caller; the result is an
independent CPU image.
}

@subsection{Writing Existing CPU Storage}

For a new CPU image, use @racket[gpu-surface->raster-image] or
@racket[gpu-image->raster-image]. The operations in this section write into
caller-owned storage instead. The caller supplies matching dimensions and
formats, and must observe each operation\'s rules for borrowing and failed writes.

@defproc[(gpu-surface-read-pixmap! [surface gpu-surface?] [destination pixmap?]) void?]{
Reads the full surface into @racket[destination].

The destination must be a live, writable pixmap with exactly matching dimensions.
Its description and stride come from the pixmap, whose exclusive scope must
remain active. The source and destination must agree on whether a
color-space tag is present. Supported tagged conversions are performed by the
native readback; this function does not silently relabel samples.

The operation waits for GPU work, reads into temporary tight storage, and
validates the result before copying pixels to the destination. A failed read or
invalid converted sample leaves the destination unchanged. Destination row padding is never
changed. Native format support can still make a well-formed request fail.
}

@defproc[(gpu-surface-read-raster-buffer! [surface gpu-surface?]
                                        [destination raster-buffer?]) void?]{
Reads the surface's pixels into @racket[destination].

The destination must be an idle, owned CPU buffer with exactly matching dimensions.
This legacy writer accepts only RGBA8888 premultiplied storage. It acquires an exclusive
GPU-transfer scope and uses the destination's color interpretation and stride.
The context must be active and the surface save/layer stack balanced.

Unlike @racket[gpu-surface-read-pixmap!], this writer exposes the destination to
the native readback directly. A native failure can leave partial writes;
rollback is not promised. Use @racket[gpu-surface-read-pixmap!] to check pixels
in temporary storage before changing the destination, or an operation that
returns a new copy when the caller must never receive partially written pixels.
}

@defproc[(gpu-image-read-raster-buffer! [image gpu-image?]
                                      [destination raster-buffer?]) void?]{
Like @racket[gpu-surface-read-raster-buffer!], after drawing the image into a
temporary GPU surface in the same context. The destination must match the original
image's dimensions and use RGBA8888 premultiplied storage. The direct destination write
can leave partial writes after a native failure, just like the surface operation.
}

The following helper fills a typed destination inside its writable pixmap scope.
The buffer remains the caller's resource, rather than being consumed by readback.

@racketblock[
(require skia skia/gpu)
(define (copy-gpu-surface-to-buffer context surface buffer)
  (call-with-gpu-context context
    (lambda ()
      (call-with-raster-buffer-pixmap buffer
        (lambda (destination)
          (gpu-surface-read-pixmap! surface destination))
        #:writable? #t))))
]
