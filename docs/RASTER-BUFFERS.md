# Owned raster buffers and scoped pixmaps

`raster-buffers.rkt` (also exported by `main.rkt`) provides mutable CPU pixel
storage with an explicit row stride. The storage is native-allocated RGBA8888
with premultiplied alpha. A buffer is an ordinary `skia-resource?`; use
`with-skia`, `call-with-skia-resource`, `skia-close!`, and `skia-closed?`.

`raster-buffer?` recognizes the owned buffer type, including after explicit close.
It does not imply that the resource is still live.

A **buffer owns memory**. A **pixmap describes a temporary view** of that memory.
A **canvas scope wraps the same memory in a temporary native surface**. An
**image snapshot owns a separate copy**. These roles are deliberately distinct.

## Example

Run from the repository root:

```racket
#lang racket/base
(require "main.rkt")

(with-skia ([buffer (make-raster-buffer 160 96 #:row-bytes 704)])
  (call-with-raster-buffer-pixmap
   buffer
   (lambda (view)
     (pixmap-fill! view (rgb 14 149 142))
     (pixmap-fill! (pixmap-subset view 12 12 40 32) (rgb 240 160 32)))
   #:writable? #t)

  (call-with-raster-buffer-canvas
   buffer
   (lambda (canvas)
     (with-skia ([paint (make-paint #:color 'white #:stroke-width 3)])
       (draw-line canvas 80 32 140 32 paint)
       (draw-line canvas 80 48 140 48 paint))))

  (with-skia ([snapshot (raster-buffer->image buffer)])
    (save-image snapshot "raster-card.png" 'png #:exists 'replace)))
```

The temporary SkSurface draws directly into the buffer: there is no pixel copy
on canvas entry or exit. This is **not** a promise to retain arbitrary Racket
byte strings, expose an address, or perform zero-copy image publication.

## Storage layout

`(make-raster-buffer width height #:row-bytes [row-bytes #f]
                                 #:color-space [color-space #f])`

Width and height are exact integers from 1 through 32768, matching the existing
CPU image limits. The default stride is `4 * width`. An explicit stride must
be an exact multiple of four at least that large. Rows run top to bottom.
The active bytes of each row are R, G, B, A; they are **not** packed ARGB words
or platform-dependent N32/BGRA bytes. All storage, including padding after the
last row, starts at zero (transparent black).

The full allocation is `row-bytes * height`; its minimum pixel extent is
`row-bytes * (height - 1) + 4 * width`. Allocation checks charge the full size
against `current-skia-byte-limit` and against the native signed pointer range.
This is a per-allocation/copy limit, not a process-wide memory or Skia-cache quota.

An optional live `color-space?` is retained by native reference. Closing its
original Racket wrapper does not invalidate the buffer. Omitting the space
means untagged storage, like the existing default raster surface. Writing RGBA
samples does not perform gamut conversion or attach a different profile: the
samples are interpreted in the buffer's declared space.

`raster-buffer-width`, `raster-buffer-height`, `raster-buffer-row-bytes`, and
`raster-buffer-byte-size` require a live buffer on its creator thread. Metadata
queries are allowed during a borrow; pixel-copy, snapshot, and mutation entry
points on the buffer are not.

## Copies and byte transfers

* `(raster-buffer->storage-bytes buffer)` returns a detached mutable byte string
  containing the full **premultiplied**, padded allocation. Changing it does not
  change the buffer. Padding is initialized and is not exposed as writable memory.
* `(raster-buffer->rgba-bytes buffer #:premultiplied? [#f])` returns detached,
  tightly packed bytes. The default is straight/unpremultiplied RGBA. With `#t`,
  it returns the stored premultiplied channels without unpremultiplying.
* `(raster-buffer-write-rgba! buffer bytes #:row-bytes [#f]
  #:premultiplied? [#f])` replaces active pixels, not padding. Source stride
  defaults to `4 * width`. The last source row need not include trailing padding;
  the source must cover the minimum pixel extent and fit the byte limit.
  Extra source padding is ignored.
* `(raster-buffer-copy buffer #:row-bytes [#f])` makes an independent buffer,
  preserving stored pixel values and the color-space reference. It defaults to
  tight rows; new padding is zero, not copied from the original allocation.
* `(raster-buffer->image buffer)` returns an ordinary immutable owned `image?`.
  It remains valid after buffer mutation or closure. It currently uses tight
  premultiplied Racket staging followed by Skia's raster-copy constructor:
  **two explicit copies**, with no retained mutable backing store.

Straight input is premultiplied once using `(channel * alpha + 127) / 255` with
integer quotient. Already-premultiplied input must satisfy R, G, B <= A for every
pixel. The entire input is checked and copied before destination mutation, so a
late invalid pixel cannot cause a partially committed upload. Callers must not
concurrently mutate an input byte string while it is being copied.
Unpremultiplication of low-alpha pixels is necessarily lossy at 8-bit precision.

## Pixmap scope

`(call-with-raster-buffer-pixmap buffer proc #:writable? [#f])`

Calls `proc` once with a `pixmap?`. The borrow is exclusive even in read-only
mode. It preserves multiple return values. All subsets share the same lease and
permission. On normal return, exception, or continuation escape, the lease is
retired. Retained views cannot be used in a later scope. A retired lease drops
its reference to the buffer; saving an expired view does not keep its pixels
alive. Captured continuations cannot reenter the scope across its barrier.

`pixmap?` remains a type predicate after retirement. All view operations,
including metadata, require an active lease on the creator thread:

| Operation | Meaning |
|---|---|
| `pixmap-width`, `pixmap-height` | Active view dimensions in pixels. |
| `pixmap-row-bytes` | Parent stride; a subset does not become tightly packed. |
| `pixmap-writable?` | Boolean permission of this lease. |
| `(pixmap-subset view x y width height)` | Nonempty integer rectangle completely inside the view. Does not silently clip. Nested offsets accumulate. |
| `(pixmap-pixel view x y)` | Native unpremultiplied `rgba` color at a checked pixel. |
| `(pixmap-set-pixel! view x y color)` | Native erase of one checked pixel. Requires a writable lease. |
| `(pixmap-fill! view color)` | Native erase of the whole view. Does not fill parent padding. |
| `(pixmap->rgba-bytes view #:premultiplied? [#f])` | Detached tight bytes for the view. |
| `(pixmap-write-rgba! view bytes #:row-bytes [#f] #:premultiplied? [#f])` | Validated replacement of the view's pixels. Same input rules as buffer upload. |
| `(pixmap-scale! destination source #:sampling ['linear])` | Native pixmap scaling; sampling is `'linear` or `'nearest`. Destination must be writable and source/destination must belong to distinct buffers. |

Scaling rejects all same-allocation aliases, including apparently disjoint
subsets. Skia's scaling operation is not treated as `memmove`; use an independent
buffer copy when necessary. Native color conversion can occur between differently
tagged source and destination buffers. No raw pointers or mutable native byte
views are returned.

## Canvas scope

`(call-with-raster-buffer-canvas buffer proc)`

Calls `proc` once with an ordinary borrowed `canvas?`. Each invocation creates a
fresh native direct raster surface with the full clip and identity transform.
Existing pixel contents are not cleared. Standard paths, text, shaders, filters,
transforms, and scoped layers draw through the existing canvas API.

The direct surface is destroyed before the buffer borrow ends. Saved canvas
state/layers are unwound before that destruction. An escaped canvas is invalid;
calling it after the scope raises instead of dereferencing freed native memory.
Multiple values and exceptions/continuation escapes follow the same scoped
resource protocol as the rest of the library.

Cleanup **does not roll pixels back**. Earlier writes remain, and restoring an
unfinished layer can composite its partial contents. Closing the buffer, opening
another view/canvas on that buffer, copying pixels through the owner, or taking an
image snapshot during either kind of borrow is rejected. Independent buffers
may have nested scopes. All native accesses are synchronous and revalidate
resource liveness/thread ownership; user callbacks are not held inside a blanket
atomic section.

## Documents, snapshots, and limits

Publish a copied image to PDF/SVG using `draw-image`, `draw-image-rect`, or an
output group. These remain existing raster source images with `embedded-raster`
classification, not vector art. A compatible output group can replay natively
without generating a second panel-sized bitmap; `vector-only` still rejects it.
Images may be retained by pictures or shaders after the mutable buffer is closed.

A pixel snapshot carries pixels and its color-space tag, not recorded text,
links, destinations, or a drawing-command history. Do not use it as a semantic
substitute for a recorded vector picture. No general borrowed views over existing
surfaces/images are exposed in this pass: that would also need to coordinate
Skia copy-on-write and mutation notifications. Arbitrary external pointers,
retained Racket byte strings, foreign release callbacks, general mutable bitmap
wrappers, F16/F32 formats, GPU surfaces, and performance claims are out of scope.

## Native references

The implementation targets the SkiaSharp m119 C ABI at mono/skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:

- `include/c/sk_surface.h` and `src/c/sk_surface.cpp`: the direct raster call wraps
  caller-owned pixels through `SkSurfaces::WrapPixels`.
- `include/c/sk_pixmap.h`: temporary descriptors, color reads/erase, readback,
  and scaling. `SkPixmap` does not own pixel storage.

Six native callouts are added; existing image-info and sampling layouts are
reused. Public mutable storage always uses RGBA8888 + premultiplied alpha.
