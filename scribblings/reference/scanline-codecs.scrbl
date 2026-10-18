#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/codec-scanlines))

@title[#:tag "skia-scanline-codecs"]{Scanline Decoding}

@defmodule[skia/codec-scanlines #:no-declare]
@(declare-exporting skia skia/codec-scanlines #:use-sources (skia/codec-scanlines))

Use scanline decoding when you can process an image a few rows at a time
without collecting a complete decoded image. Start a session with
@racket[codec-scanline-from-bytes] or @racket[codec-scanline-from-stream], then
request batches with @racket[codec-scanline-read!]. This controls returned batch
size, not total decoder memory use. It is not a way to feed an unfinished
encoded download.

A @deftech{scanline session} decodes the first frame in row batches using a
private native codec. It is an @tech{owned resource} with one forward cursor,
not a public codec that another operation can reset. Construction negotiates
native scaled dimensions and starts scanline decoding; unsupported formats or
output conversions raise an exception. There is no complete-decode-and-slice
fallback.

Input is already available as copied bytes, a private stream duplicate, or a
fully buffered port. A short scanline read is not a request to feed more input;
use an @tech{incremental decoding session} for explicitly supplied chunks.
Scanline output preserves @tech{encoded orientation}. The session's row order describes
native consumption order, not EXIF orientation normalization.

All session operations except the predicate require the creating Racket thread.
The state query also works after closure. Other session queries require an open
resource.

@local-table-of-contents[#:style 'immediate-only]

@section{Sessions and Row Decoding}

@defproc[(codec-scanline-session? [v any/c])
          boolean?]{
Returns @racket[#t] for a scanline session, including a closed one, and @racket[#f] otherwise.
}

@defproc[(codec-scanline-from-bytes [encoded bytes?]
          [#:scale scale (and/c real? (>/c 0)) 1]
          [#:color-type color-type (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8
                                 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'opaque 'premul 'unpremul) 'unpremul]
          [#:color-space space (or/c #f 'srgb 'linear-srgb bytes?) 'srgb])
          codec-scanline-session?]{
Starts a session from copied, nonempty encoded bytes. The scale follows
@racket[codec-scaled-dimensions]; the resulting size is negotiated, not guaranteed
to be the requested ratio. Pixel-format and alpha combinations follow
@racket[make-image-info], and native scanline support is checked separately.
The default requests unpremultiplied RGBA8888 in sRGB. The destination description
is independent of the encoded source metadata.

The session checks that at least one output row fits the byte limit without
allocating a full output raster. Requested batches are bounded separately.
Bottom-up decoding is rejected if negotiated height differs from encoded height,
because this wrapper does not invent scaled bottom-up row coordinates.
}

@defproc[(codec-scanline-from-stream [stream skia-input-stream?]
          [#:scale scale (and/c real? (>/c 0)) 1]
          [#:color-type color-type (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8
                                 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'opaque 'premul 'unpremul) 'unpremul]
          [#:color-space space (or/c #f 'srgb 'linear-srgb bytes?) 'srgb])
          codec-scanline-session?]{
Starts a session through a private duplicate at byte zero. The original stream
is neither consumed nor closed, and closing it does not invalidate the session.
The scale, format, color, and native-support rules are those of
@racket[codec-scanline-from-bytes]. File-backed input still requires a stable file.
}

@defproc[(codec-scanline-from-port/buffered [input input-port?]
          [#:scale scale (and/c real? (>/c 0)) 1]
          [#:color-type color-type (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8
                                 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'opaque 'premul 'unpremul) 'unpremul]
          [#:color-space space (or/c #f 'srgb 'linear-srgb bytes?) 'srgb]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          codec-scanline-session?]{
Validates the requested output options, buffers the unread port input, and
starts a session. Buffering, cancellation, close behavior, and the one-byte
limit probe follow @racket[buffered-port->input-stream]. The explicit limit bounds
encoded input; later row batches use the captured/current decoding byte limit.
No live port callback remains attached to the session.
}

@defproc[(codec-scanline-state [session codec-scanline-session?])
          (or/c 'ready 'complete 'incomplete 'failed 'closed)]{
Returns the session state. Ready means rows remain; complete means all rows
have been consumed, possibly by skipping rather than decoding. Incomplete means
a read decoded fewer rows than requested. Failed means a skip or an attempted
operation failed. Neither incomplete nor failed permits further reading or
skipping; close the session and start a new one. Closed takes precedence once
the resource is released.
}

@defproc[(codec-scanline-info [session codec-scanline-session?])
          image-info?]{
Returns the full-output pixel description, using negotiated dimensions
and the selected output color/alpha format. It is not the size of the last batch.
}

@defproc[(codec-scanline-source-info [session codec-scanline-session?])
          encoded-image-info?]{
Returns metadata for the original encoded source, before scaling and
orientation normalization. This may describe different dimensions and formats
from @racket[codec-scanline-info].
}

@defproc[(codec-scanline-order [session codec-scanline-session?])
          (or/c 'top-down 'bottom-up)]{
Returns the native row consumption order. Top-down consumes output rows from
zero upward; bottom-up consumes them from height minus one downward. Individual
returned batches nevertheless contain decoded rows in increasing output-row order.
}

@defproc[(codec-scanline-position [session codec-scanline-session?])
          exact-nonnegative-integer?]{
Returns the number of requested rows consumed by reads and skips. This is a
cursor in consumption order, not necessarily an output row number or the count
of successfully decoded rows. A short read still advances by its requested count.
}

@defproc[(codec-scanline-next-row [session codec-scanline-session?])
          (or/c exact-nonnegative-integer? #f)]{
Returns the output row that would be consumed next, or @racket[#f] at the end.
The state must be ready or complete. It never queries the native decoder beyond
the last row.
}

@defproc[(codec-scanline-output-row [session codec-scanline-session?]
          [input-row exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Maps a zero-based consumption-order index to its output row. The index must be
less than the output height. This query does not advance the cursor and is valid
in ready or complete states. It uses @math{height - input-row - 1} for bottom-up
order and the unchanged index for top-down order.
}

@defproc[(codec-scanline-read! [session codec-scanline-session?]
          [count exact-positive-integer? 1]
          [#:row-bytes row-bytes (or/c exact-nonnegative-integer? #f) #f])
          scanline-batch?]{
Requests @racket[count] rows and returns a scanline batch. The count must not
exceed the remaining rows; requesting zero or reading after completion is an
error. The stride follows @racket[image-info-storage-layout]. The requested
batch allocation, including padding, must fit the smaller of the session's
captured limit and @racket[current-skia-byte-limit].

A short native read returns only successfully decoded rows and changes the state
to @racket['incomplete]. Native fill rows are excluded. The cursor advances by
the requested count, not the returned count. Bottom-up short reads retain the
successfully decoded rows in top-to-bottom order and report their actual first
output row. Row padding is initialized to zero.

Validation or staging-allocation failures before the native read leave the
session usable. An exception after attempting the native read changes the state
to @racket['failed]. No caller-owned byte string is partially mutated.

@racketblock[
(with-skia ([surface (make-surface 3 2 #:background 'blue)]
            [image (surface-snapshot surface)]
            [session (codec-scanline-from-bytes (image->jpeg-bytes image))])
  (define batch (codec-scanline-read! session 2))
  (list (scanline-batch-complete? batch)
        (scanline-batch-decoded-count batch)
        (codec-scanline-position session)
        (codec-scanline-next-row session)))
]

A complete two-row read yields @racket[#t], @racket[2], @racket[2], and @racket[#f].

@racketblock[
(with-skia ([source (make-surface 90 60 #:background 'red)]
            [green (make-paint #:color 'green)]
            [blue (make-paint #:color 'blue)])
  (draw-rect (surface-canvas source) 0 20 90 20 green)
  (draw-rect (surface-canvas source) 0 40 90 20 blue)
  (with-skia ([image (surface-snapshot source)]
              [session (codec-scanline-from-bytes (image->jpeg-bytes image))]
              [target (make-surface 90 60 #:background 'white)])
    (for ([count '(20 20 20)])
      (define batch (codec-scanline-read! session count))
      (with-skia ([buffer (scanline-batch->raster-buffer batch)]
                  [part (raster-buffer->image buffer)])
        (draw-image (surface-canvas target) part 0
                    (scanline-batch-first-row batch))))))
]

@reference-figure["scanline-batches.png"
                  "Three horizontal color bands reconstructed from successive scanline batches."]
}

@defproc[(codec-scanline-skip! [session codec-scanline-session?] [count exact-nonnegative-integer?])
          boolean?]{
Skips a count no greater than the remaining rows. Zero is accepted, including
at completion. A successful skip returns @racket[#t]; a native skip failure
returns @racket[#f] and marks the session failed. Either native result advances
the cursor by the requested count. A successful final skip marks completion but
does not supply decoded pixels for the skipped rows.
}

@section{Row Batches}

A @deftech{scanline batch} is an immutable Racket structure containing decoded rows,
their @tech{row stride} and output-row origin, and the counts for one request.
Consecutive bottom-up batches must be placed by their first-row
fields, not blindly concatenated as if they arrived in top-down order.

@defproc[(scanline-batch? [v any/c])
          boolean?]{
Returns @racket[#t] for a scanline batch and @racket[#f] otherwise.
}

@defproc[(scanline-batch-info [batch scanline-batch?])
          image-info?]{
Returns the batch description. Its height is the successfully decoded
row count, not the requested count or full image height.
}

@defproc[(scanline-batch-row-bytes [batch scanline-batch?])
          exact-positive-integer?]{
Returns the stride of a row, including padding. The byte-string length equals
this stride times the decoded row count.
}

@defproc[(scanline-batch-first-row [batch scanline-batch?])
          (or/c exact-nonnegative-integer? #f)]{
Returns the output row corresponding to the first stored row. Subsequent
stored rows increase from there. A zero-decoded-row batch returns @racket[#f].

The following example uses a two-pixel-wide BMP with three rows. Its top row
is red and green, its middle row is blue and white, and its bottom row is yellow
and black. The small input is constructed here so no external image file is needed.

@racketblock[
(define (bottom-up-bmp)
  ;; Two pixels per row, three rows, uncompressed BGR24, four-byte row alignment.
  ;; Top-to-bottom colors: red/green, blue/white, yellow/black.
  (define output (make-bytes 78))
  (define (put offset value size)
    (bytes-copy! output offset (integer->integer-bytes value size #f #f)))
  (bytes-copy! output 0 #"BM")
  (for ([offset '(2 10 14 18 22 26 28 34)] [value '(78 54 40 2 3 1 24 24)]
        [size '(4 4 4 4 4 2 2 4)])
    (put offset value size))
  (bytes-copy! output 54 (bytes 0 255 255 0 0 0 0 0))
  (bytes-copy! output 62 (bytes 255 0 0 255 255 255 0 0))
  (bytes-copy! output 70 (bytes 0 0 255 0 255 0 0 0))
  output)

(with-skia ([session (codec-scanline-from-bytes (bottom-up-bmp))]
            [target (make-surface 2 3)])
  (define lower-batch (codec-scanline-read! session 2))
  (define upper-batch (codec-scanline-read! session 1))
  (for ([batch (list lower-batch upper-batch)])
    (with-skia ([buffer (scanline-batch->raster-buffer batch)]
                [part (raster-buffer->image buffer)])
      (draw-image (surface-canvas target) part 0
                  (scanline-batch-first-row batch))))
  (list (scanline-batch-first-row lower-batch)
        (scanline-batch-first-row upper-batch)))
]

@reference-figure["scanline-bottom-up-placement.png"
                  "The actual 2-by-3 target rebuilt from bottom-up scanline batches, enlarged with nearest-neighbor sampling. Its top row is red and green, middle row blue and white, and bottom row yellow and black; labels identify the batches' first output rows."]

Each batch is converted to an owned image and drawn at its reported first output row. The thin
horizontal rules are presentation markers for target rows, not decoded pixels.

The result is @racket['(1 0)]. The first batch contains output rows 1 and 2;
the second contains row 0. Each batch stores its rows in top-to-bottom order,
but concatenating the batches in consumption order would produce rows 1, 2, 0.
Place each batch at its reported first row instead.
}

@defproc[(scanline-batch-requested-count [batch scanline-batch?])
          exact-positive-integer?]{
Returns the number of rows requested by this read.
}

@defproc[(scanline-batch-decoded-count [batch scanline-batch?])
          exact-nonnegative-integer?]{
Returns the number of rows actually decoded, at most the requested count.
}

@defproc[(scanline-batch-bytes [batch scanline-batch?])
          (and/c bytes? immutable?)]{
Returns the immutable storage bytes for successfully decoded rows,
including initialized row padding but excluding native fill rows. An empty batch
contains an empty byte string.
}

@defproc[(scanline-batch-complete? [batch scanline-batch?])
          boolean?]{
Returns whether decoded count equals requested count for this batch. It does
not mean the entire image has been read.
}

@defproc[(scanline-batch->raster-buffer [batch scanline-batch?])
          raster-buffer?]{
Copies a nonempty batch into an independently owned raster buffer, preserving
its format and stride. An empty decoded batch is rejected. The new buffer starts
at local row zero; the batch's first-row field must be used separately when
placing it into the full image. This operation neither fills missing rows nor
applies the encoded orientation.
}

@section{Scanline Start Failures}

@defproc[(exn:fail:codec-scanline? [v any/c])
          boolean?]{
Returns @racket[#t] for the exception subtype used when the native codec
rejects starting scanline decoding, and @racket[#f] otherwise. Argument errors,
codec-construction failures, and later scanline failures need not have this type.
}

@defproc[(exn:fail:codec-scanline-result [exception exn:fail:codec-scanline?])
          symbol?]{
Returns the native result name. Names include @racket['incomplete-input],
@racket['error-in-input], @racket['invalid-conversion], @racket['invalid-scale],
@racket['invalid-parameters], @racket['invalid-input], @racket['could-not-rewind],
@racket['internal-error], and @racket['unimplemented]. An unrecognized numeric
code is reported as @racket['unknown-result], not treated as success.
}

@defproc[(exn:fail:codec-scanline-native-code [exception exn:fail:codec-scanline?])
          exact-integer?]{
Returns the numeric native result retained with the exception. This value is
for diagnostics; no automatic fallback decode is performed.
}
