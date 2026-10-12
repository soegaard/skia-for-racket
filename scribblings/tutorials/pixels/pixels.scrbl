#lang scribble/manual

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia))
@(define-runtime-path program-source "pixel-lab.rkt")

@title{Working with Pixels — Build a Two-Ink Image Processor}

@section{The Finished Image Study}

@(pixel-study-pict)

This program draws a small source image, maps its colors between two inks, and
stamps a rectangle directly into a selected pixel region. Here, the two inks
are palette endpoints: intermediate colors are allowed, not just two possible
pixel colors. The three images are snapshots taken at successive stages.
The checkerboard behind them reveals
transparency; it is not part of their stored pixels.

@centered{@bold{A buffer owns mutable pixels. A view borrows them. An image preserves a copy.}}

The example deliberately uses one format: eight-bit RGBA with premultiplied
storage. The goal is to understand ownership and layout, not enumerate every
pixel format. Save the complete @filepath{pixel-lab.rkt} file from the end to use
its helpers below.

@section{Draw into a Pixel Buffer}

A raster buffer owns CPU memory. A canvas scope lets ordinary Skia drawing
functions draw into that memory:

@pixels-racketblock+eval[
(require skia "pixel-lab.rkt")
(define buffer (make-source-buffer))
(define original (raster-buffer->image buffer))
]

@(source-pict)

The source is 192 by 128 pixels, shown here at twice its size with nearest
sampling over a checkerboard. The lower orange strip is translucent, and
the gap above it is transparent. In the gap, the checkerboard is unchanged;
under the orange strip, it is tinted. The checkerboard is not stored in the image.

Here is the source constructor:

@codeblock[(source-definition program-source 'make-source-buffer)]

The buffer starts at transparent black. The canvas scope does not clear its
contents automatically. It borrows the buffer during drawing, then releases the
borrow before @racket[raster-buffer->image] takes a snapshot. The image is a
separate copy; it does not share writable storage with the buffer.

@section{Understand a Row of Pixels}

A pixel has four consecutive channel bytes in R, G, B, A order. A row stride
specifies how many bytes separate the beginnings of successive rows. It can be
larger than the active pixels in a row.

The following tiny example has three pixels per row, but reserves 16 bytes for
each row: 12 active bytes and four padding bytes.

@codeblock[(source-definition program-source 'make-tiny-buffer)]

@pixels-racketblock+eval[(define tiny (make-tiny-buffer))]

@(tiny-pixel-pict)

The actual six-pixel image is enlarged 48 times with nearest sampling. The
constructor's input contains two tight 12-byte rows; the upload's
@racket[#:row-bytes 12] describes that input, not the destination buffer.
Skia copies the pixels into the buffer's 16-byte rows and leaves the padding alone.

@(tiny-layout-pict)

Each cell shows one byte read from the actual buffer storage. The second row
starts at byte 16, not byte 12. The four gold cells in each row are padding,
not pixels in the six-pixel image.

The padding is not another pixel. A pixel's storage offset is
@racket[(+ (* y row-bytes) (* 4 x))]. This differs from the offset into a tightly
packed copy, @racket[(* 4 (+ x (* y width)))].

@pixels-interaction[
(bytes-length (raster-buffer->storage-bytes tiny))
(bytes-length (raster-buffer->rgba-bytes tiny))
(raster-buffer-row-bytes buffer)
]

The small buffer has 32 storage bytes but only 24 active bytes. Our source
buffer's stride is 800: 768 active bytes and 32 padding bytes per row.

@section{Copy Straight RGBA Samples}

The default RGBA readback returns a detached, tightly packed byte string with
@emph{straight}, or unpremultiplied, RGB channels:

@pixels-racketblock+eval[
(define source-pixels (raster-buffer->rgba-bytes buffer))
]

Changing this byte string does not change the buffer. A separate copy of the
tiny example makes that distinction testable:

@pixels-racketblock+eval[
(define detached-copy (raster-buffer->rgba-bytes tiny))
(bytes-fill! detached-copy 0)
]
@pixels-interaction[
(bytes->list (subbytes (raster-buffer->rgba-bytes tiny) 0 4))
]

The buffer's first pixel is still opaque red. The upload at a later step will
make our processed byte string affect the buffer explicitly.

Stored RGB channels are multiplied by alpha. Check both representations of
one half-transparent red pixel using the real buffer operations:

@pixels-racketblock+eval[
(define alpha-sample (make-raster-buffer 1 1))
(raster-buffer-write-rgba! alpha-sample (bytes 255 0 0 128))
]
@pixels-interaction[
(bytes->list (raster-buffer->rgba-bytes alpha-sample))
(bytes->list (raster-buffer->storage-bytes alpha-sample))
]

The straight readback contains red 255, while stored red is 128. Alpha is 128
in both. These are two representations of the same pixel, not two different
levels of transparency. Our processor works on straight channels so it can
recolor a translucent pixel without treating premultiplication as a darker
source color.

Use @racket[#:premultiplied? #t] only when an algorithm deliberately operates on
stored premultiplied channels. The storage-byte function always includes that
representation and the padding. Unpremultiplying low-alpha eight-bit pixels can
lose precision; transparent pixels do not preserve hidden RGB reliably.

@section{Map Each Pixel between Two Inks}

The processor calculates a simple score from the three encoded channels, then
interpolates between navy and gold. It preserves the alpha byte:

@codeblock[(source-definition program-source 'duotone-rgba)]

This average is an artistic control, not a calculation of physical luminance.
The next tutorial will distinguish encoded sRGB values from linear-light
values. Here the purpose is to follow one concrete byte-processing algorithm.

A one-pixel example makes alpha preservation visible without an image:

@pixels-interaction[
(bytes->list (duotone-rgba (bytes 255 255 255 128)))
]

The result uses the light ink's RGB channels and retains alpha 128. The
function returns new bytes and leaves its input unchanged.

@section{Write the Result Back}

The upload replaces active pixels without treating source data as padded rows:

@pixels-racketblock+eval[
(define transformed-pixels (duotone-rgba source-pixels))
(raster-buffer-write-rgba! buffer transformed-pixels)
(define processed (raster-buffer->image buffer))
]

@(processed-pict)

This snapshot is shown at twice its pixel size over the same checkerboard.
The transparent gap and translucent strip remain visible after recoloring.
The upload uses straight RGBA input by default and premultiplies it once for storage. It does
not fill or expose writable row padding. The @racket[process-buffer!] helper
combines this read-transform-write sequence:

@codeblock[(source-definition program-source 'process-buffer!)]

The earlier @racket[original] image still contains the original colors. A
snapshot is not a live preview of the current buffer.

@section{Borrow a Writable Subregion}

For direct region editing, borrow a pixmap. A pixmap describes the buffer's
pixels; it does not own a second allocation:

@pixels-interaction[
(call-with-raster-buffer-pixmap
 buffer
 (lambda (view)
   (define patch (pixmap-subset view 145 100 32 20))
   (list (pixmap-width patch) (pixmap-height patch) (pixmap-row-bytes patch))))
]

The subset is 32 by 20, but its stride is still 800, inherited from the parent.
A small view is not necessarily tightly packed. To modify it, explicitly
request a writable borrow:

@codeblock[(source-definition program-source 'stamp-region!)]

@pixels-racketblock+eval[
(stamp-region! buffer)
(define stamped (raster-buffer->image buffer))
]

@(stamped-pict)

The cyan rectangle replaces the selected pixels; it is not a translucent
paint composited over the previous image. The @racket[pixmap-fill!] function
writes the supplied color into the region. The coral outline marks its
exact bounds: source (145, 100) through (177, 120), excluding the right and bottom
edges. It is a figure guide, not a mark in the stored image. All other pixels
retain their processed values. The view and its subsets expire when the
callback returns; keep the resulting image, not the pixmap, for later use.

Only one borrow of a particular buffer can be active. Take snapshots after the
scope, not inside it. A scope restores lifetime safety, not pixel contents:
writes already performed are not rolled back when a callback raises an error.

@section{Keep the Snapshots and Save the Study}

The finished study places three independent snapshots side by side:

@(pixel-study-pict)

The complete program saves @filepath{pixel-study.png} and the processed
@filepath{duotone.png}. The duotone file retains its alpha channel; the checkerboard
in the study is just a background drawn beneath it.

The buffer, snapshots, and paints are ordinary owned CPU resources. Ordinary
Racket bindings are appropriate when exact release time is unimportant. The
pixmap and canvas borrows still need their explicit scopes.

@section{The Complete Program}

Run the file with @tt{racket pixel-lab.rkt}:

@codeblock[(file->string program-source)]

@section{Try It}

Change the two inks while leaving alpha unchanged. Then change the padded row
stride from 800 to 832. The image should look the same, even though the storage
byte string becomes larger.

Try stamping a different rectangle. Its bounds must fit inside the buffer;
@racket[pixmap-subset] does not silently clip an out-of-range request. Compare a
new snapshot with an older one to confirm that only the new snapshot changes.

@section{Where to Go From Here}

This is a transparent implementation of a small CPU image processor, not a
benchmark or a recommendation to write every image effect as a Racket loop.
Built-in color filters and GPU effects may be more suitable for other workloads.
The Guide covers typed pixel formats, image conversion, bulk scaling, and GPU
transfers. A GPU image requires explicit readback before this CPU-buffer path.
