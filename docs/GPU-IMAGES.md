# GPU images and retained resource ownership

Import `skia/gpu` alongside `skia`. GPU images use the existing `image?` type,
so the ordinary image drawing, shader, paint, filter, and picture APIs accept
them. The image's execution context is part of its ownership contract.
`make-surface` and existing CPU image constructors remain CPU operations.

## Creating and inspecting images

```racket
(gpu-upload-image context image
                  #:mipmapped? [mipmapped? #f]
                  #:budgeted? [budgeted? #t])
(gpu-surface-snapshot surface)
(gpu-image-subset image x y width height)
(gpu-image? value)
(image-residency image) ; 'cpu or 'gpu
(skia-resource-gpu-context resource) ; gpu-context? or #f
(gpu-image-info image) ; detached diagnostic hash
```

Creation, native inspection, and drawing of GPU-dependent resources require
`call-with-gpu-context` on their owning context and creator Racket thread.
Uploads accept a CPU image or an existing image from that same context. The
result owns an independent native reference; closing either input wrapper
never closes the returned wrapper. Skia may reuse a same-context texture rather
than allocate another one. The mipmap and budget flags are requests to the
pinned native API, not a promise of a fresh allocation or a residency measurement.
GPU factories reject a null, invalid, or non-texture-backed result. They do not
silently return a CPU image.

A GPU surface snapshot is immutable. Later drawing into or closing the source
surface must not change it. Snapshotting requires a balanced canvas save/layer
stack. A subset is a nonempty, exact-integer rectangle fully inside the source;
it stays on the same GPU context. Out-of-range rectangles are rejected rather
than clipped. Native storage may be shared or copied by Skia.

`gpu-image?` is a wrapper-classification predicate, also usable after close.
`image-residency` and `skia-resource-gpu-context` reject closed resources but do
not call native code. Residency describes the library's ownership contract:
a CPU/lazy encoded image remains `cpu` even if Skia internally caches an upload
while drawing it. Existing CPU-image drawing on GPU surfaces remains supported;
it does not turn the source wrapper into a GPU-resident image.

`gpu-image-info` requires a live owning activation and verifies native texture
backing and validity. Its immutable hash reports `storage`, `backend`, `width`,
`height`, `context_generation`, `context_matches`, `texture_backed`, `unique_id`,
and `readback_path`. The native unique ID need not change on same-context reuse.
No texture identifier, driver pointer, or external ownership callback is exposed.

## Retained graphs follow their GPU inputs

A GPU image used by an image shader makes that shader GPU-dependent. Affinity
then propagates through composed/local-matrix shaders, image-filter graphs,
valid runtime-effect child graphs, paint attachments/copies/getters, recorded
pictures, nested pictures, and picture shaders/filters. The native objects
retain their own inputs; the affinity record does **not** consult the original
mutable or explicitly closed Racket wrapper during later drawing.

Mutable paints track each attachment separately. Replacing or clearing one
slot does not erase another slot's GPU dependency. Clearing the last GPU slot
under its owning activation makes the paint CPU-independent again, after the
native setter has released that attachment. A clone retains its own attachment
snapshot. A retained getter inherits only the selected slot: a CPU shader
returned from a paint with an unrelated GPU image filter stays independent.
A native setter failure leaves conservative ownership rather than allowing an
unsafe CPU-side destructor.

Recording captures affinity before a retaining native draw. A finished picture
inherits it; the now-empty recorder becomes independent and can be reused.
Mutating the original paint or closing an original image after recording does
not change the recorded picture's ownership. A recorder that still contains
GPU-dependent commands must be finished/closed in accordance with that domain.

Affine resources keep the public GPU context reachable. Explicit close and GC
invalidate their handles and queue native destruction for the domain's owner.
They never enter a GL provider from a finalizer. A live affine image **or a
retained parent graph** prevents premature context closure. Queue draining,
shutdown requests, and abandonment retain the foundation's existing semantics.
A context with a dead owner is not destroyed on an arbitrary thread.

Two contexts may not be mixed, even when they refer to the same device or an
application believes their textures are shared. CPU, PDF, and SVG destinations
also reject GPU-dependent images and graphs, even inside the correct GPU
activation. These checks occur before a retaining/drawing native operation;
ordinary temporary CPU allocations may already have occurred.

## Explicit CPU transfers

```racket
(gpu-image->rgba-bytes image
                       #:premultiplied? [premultiplied? #f]
                       #:color-space [color-space-or-false #f])
(gpu-image->raster-image image)
(gpu-image-read-raster-buffer! image raster-buffer)
```

These operations require the owning activation and perform a synchronous
transfer. Returned bytes do not alias Skia memory. The CPU `image?` returned by
`gpu-image->raster-image` is independent of the GPU image and context, retains
its color-space metadata, and remains usable for encoding, CPU/PDF/SVG drawing,
or uploading into another context after the original GPU context is closed.
Bytes use straight RGBA by default; `#:premultiplied? #t` requests premultiplied
RGBA. The optional color space requests sample conversion during readback.

The pinned m119 C image readback functions omit a `GrDirectContext` argument.
Consequently, image readback deliberately draws the image 1:1 with Src into a
same-context, same-color-space temporary GPU surface, then uses the existing
explicit surface readback. This costs an additional GPU-side staging allocation
and draw. It is **not** a direct texture mapping or zero-copy download. There
can also be CPU copies when constructing the independent raster image. No
asynchronous transfer or performance claim is made.

Raster-buffer readback requires matching dimensions and an idle exclusive
buffer. It writes premultiplied RGBA using the buffer's stride and color space;
row padding is preserved. An active canvas/pixmap borrow, dimension mismatch,
or closed buffer is rejected. A native transfer failure can leave partial
writes; destination writes are not transactional.

Existing CPU helpers deliberately remain explicit boundaries. `image->rgba-bytes`,
image encoders, `image-convert-color-space`, `image-original-encoded-bytes`, and
`image-subset` reject GPU images. Use the GPU transfer/subset functions above.
`picture->bytes` and `picture->image` reject GPU-dependent pictures; rendering a
picture onto a GPU surface and explicitly detaching the output is the supported
route. Portable drawing helpers that internally construct CPU image subsets
likewise do not implicitly download a GPU image. Ordinary direct image and
subrectangle drawing works on the owning GPU target.

## Example: keep a shader after closing its source

Here `context` is an existing OpenGL context created with `make-gpu-context`.
The returned value is a CPU image, which can be encoded outside the GPU scope.

```racket
(define result
  (call-with-gpu-context context
    (lambda ()
      (with-skia ([cpu (rgba-bytes->image 1 1 (bytes 30 140 210 255))]
                  [texture (gpu-upload-image context cpu)]
                  [shader (make-image-shader texture #:tile-x 'repeat #:tile-y 'repeat)]
                  [paint (make-paint #:shader shader)]
                  [surface (make-gpu-surface context 320 180)])
        (skia-close! texture)
        (skia-close! shader)
        (draw-rect (surface-canvas surface) 20 20 280 140 paint)
        (gpu-surface->raster-image surface)))))

(with-skia ([image result])
  (save-image image "gpu-image-example.png" 'png #:exists 'replace))
```

For snapshot-based processing, replace the upload with
`(gpu-surface-snapshot source-surface)` while its context is active. GPU images
are not canvas leases: they can survive an activation and be used in a later
activation of their owning context. The borrowed canvases themselves still
expire at the end of their original scope.

## Native ABI and scope

This implementation stays on SkiaSharp 3.119.1 / Skia m119, pinned Skia source
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. The separate seven-symbol image group
is lazy; the CPU-required symbol list is unchanged. The context-bearing upload
and subset calls return one owned image reference. Snapshots also return one
owned reference. Native C `bool` uses the existing one-byte `_stdbool` layout.
No new C record layout is introduced.

Pinned primary sources:
- [C image declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_image.h)
  and [C image implementation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_image.cpp).
- [Picture recorder implementation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/core/SkPictureRecorder.cpp):
  successful picture finish moves the record into the returned picture before
  recorder affinity is cleared.

Metal remains a construction probe at this point. GPU image interop, external
texture adoption, share-group access, cross-place transfers, and a finalized
public presenter API are separate work. See [validation](GPU-IMAGE-TESTING.md).
