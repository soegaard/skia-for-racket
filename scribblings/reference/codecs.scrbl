#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/codec-queries))

@title[#:tag "skia-codecs"]{Image Codecs and Frames}

@(declare-exporting skia)

Use a codec when you need image metadata before decoding pixels, access to
individual animation frames, or control over orientation and destination
color space during decoding. Open one with @racket[codec-from-file] or
@racket[codec-from-bytes], then decode a selected frame with
@racket[codec->image]. For simply loading an image to draw, use
@racket[image-from-file] or @racket[image-from-bytes].

An image @deftech{codec} owns an encoded source and provides metadata and frame
decoding. It is an @tech{owned resource}, not a decoded image. Its operations
require an open codec on its owning thread. Successful construction or metadata
inspection does not guarantee that pixel decoding will succeed.

Encoded metadata describes the stored image before orientation normalization.
A decoded image has its own storage and lifetime. Each frame decode starts with
a fresh destination; callers do not supply a previous frame's pixels.

@local-table-of-contents[#:style 'immediate-only]

@section{Codec Construction and Frame Decoding}

@defproc[(codec? [v any/c])
          boolean?]{
Returns @racket[#t] for a codec, including a closed wrapper, and @racket[#f]
otherwise. It does not report whether a particular frame can be decoded.
}

@defproc[(codec-from-bytes [encoded bytes?])
          codec?]{
Constructs a codec from a copy of nonempty encoded bytes. The input must fit
@racket[current-skia-byte-limit]. Later mutation of @racket[encoded] does not
change the codec. Invalid or unsupported data raises an exception. Metadata is
inspected without allocating a full decoded raster.
}

@defproc[(codec-from-file [filename path-string?])
          codec?]{
Constructs a codec from a bounded snapshot of a nonempty encoded file. The file
must exist, its path must not contain NUL, and its contents must fit
@racket[current-skia-byte-limit], including if it grows during reading. No file
mapping or open port is retained. This differs from a codec made from a
file-backed @racket[make-file-input-stream] via @racket[codec-from-stream].
}

@defproc[(codec-info [codec codec?])
          encoded-image-info?]{
Returns encoded metadata. Obtaining the metadata does not decode all
pixels, normalize orientation, or enforce the full-raster allocation limits of
@racket[codec->image].
}

@defproc[(codec-frame-count [codec codec?])
          exact-positive-integer?]{
Returns the number of frame indices exposed by the codec. A still image has
one frame, even when its native animation metadata table is empty. This count
does not certify that every frame's pixel decode will succeed.
}

@defproc[(codec-repetition-count [codec codec?])
          (integer-in -1 #f)]{
Returns the native animation repetition count. Zero means no repeat after the
first playthrough; a positive value counts additional repetitions. A value of
@racket[-1] means repeat indefinitely. The count alone does not establish that
the input has more than one frame.
}

@defproc[(codec-color-space [codec codec?])
          (or/c color-space? #f)]{
Returns an independently owned reference to the source color space, or
@racket[#f] when the source is untagged. Closing the codec does not invalidate
the returned color-space resource. The query does not convert any samples.
}

@defproc[(codec->image [codec codec?]
          [#:frame-index index (integer-in 0 2147483647) 0]
          [#:normalize-origin? normalize? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f])
          image?]{
Decodes the selected zero-based frame into a new CPU image with premultiplied
RGBA8888 storage. The index must be less than the result of @racket[codec-frame-count]. Each
encoded dimension must lie from 1 through 32768, and the full four-byte-per-pixel
allocation must fit @racket[current-skia-byte-limit]. Any non-success native
result, including incomplete input, raises an exception instead of returning
partially initialized pixels.

The codec reconstructs the requested frame's dependencies into a fresh buffer.
Calls need not be made in frame order. A false color-space option preserves the
source tag; a supplied live space requests conversion during decoding and is
retained independently by the returned image.

The default permutes pixels to top-left orientation without resampling. Origins
that exchange axes also exchange the output width and height. Disabling
normalization preserves encoded coordinates. These coordinates differ from a
frame rectangle reported by @racket[codec-frame-info], which always uses encoded
coordinates. No scaling or subset negotiation is applied by this function.

@racketblock[
(with-skia ([surface (make-surface 3 2 #:background 'blue)])
  (define encoded (surface->png-bytes surface))
  (with-skia ([codec (codec-from-bytes encoded)]
              [image (codec->image codec)])
    (list (codec-frame-count codec)
          (encoded-image-info-frame-count (codec-info codec))
          (image-width image) (image-height image))))
]

A still PNG has one selectable frame; its animation-metadata count can be zero.

@reference-figure["codec-image.png"
                  "The actual codec-to-image result, enlarged with nearest-neighbor sampling: an opaque solid-blue image that is three pixels wide by two pixels high."]

The figure is a labeled enlargement of the decoded 3 by 2 image, not a drawing made to resemble
the source surface.
}

@defproc[(image-frame-from-bytes [encoded bytes?] [index (integer-in 0 2147483647) 0]
          [#:normalize-origin? normalize? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f])
          image?]{
Constructs a temporary codec with @racket[codec-from-bytes], decodes @racket[index]
with @racket[codec->image], and closes the codec. The returned image is independent.
Orientation, color-space, frame-dependency, and decode-failure rules are unchanged.
}

@defproc[(image-frame-from-file [filename path-string?] [index (integer-in 0 2147483647) 0]
          [#:normalize-origin? normalize? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f])
          image?]{
Constructs a temporary codec with @racket[codec-from-file], decodes @racket[index]
with @racket[codec->image], and closes the codec. The returned image is independent.
Orientation, color-space, frame-dependency, and decode-failure rules are unchanged.
}

@section[#:tag "skia-encoded-metadata"]{Encoded Metadata}

An @deftech{encoded image description} is an immutable Racket structure reporting dimensions,
format, native color and alpha types, @tech{encoded orientation}, and animation metadata
count. It is not a @tech{pixel description}.

@defproc[(encoded-image-info? [v any/c])
          boolean?]{
Returns @racket[#t] for an encoded image description and @racket[#f] otherwise.
}

@defproc[(encoded-image-info-from-bytes [encoded bytes?])
          encoded-image-info?]{
Probes nonempty encoded bytes without returning a codec or allocating the
complete decoded raster. The input must fit @racket[current-skia-byte-limit].
Invalid or unsupported input raises an exception. A successful probe does not
establish complete pixel decodability.
}

@defproc[(encoded-image-info-from-file [filename path-string?])
          encoded-image-info?]{
Probes an existing nonempty file without returning a codec or allocating the
complete decoded raster. The path must not contain NUL and the encoded file
size must fit @racket[current-skia-byte-limit]. Invalid or unsupported input
raises an exception. A successful probe does not establish complete pixel
decodability.
}

@defproc[(encoded-image-info-width [info encoded-image-info?])
          exact-positive-integer?]{
Returns the encoded pixel width, before orientation normalization.
}

@defproc[(encoded-image-info-display-width [info encoded-image-info?])
          exact-positive-integer?]{
Returns the width after applying the encoded orientation. The four transposed
origins exchange width and height. This query allocates no pixels.
}

@defproc[(encoded-image-info-height [info encoded-image-info?])
          exact-positive-integer?]{
Returns the encoded pixel height, before orientation normalization.
}

@defproc[(encoded-image-info-display-height [info encoded-image-info?])
          exact-positive-integer?]{
Returns the height after applying the encoded orientation. The four transposed
origins exchange width and height. This query allocates no pixels.
}

@defproc[(encoded-image-info-format [info encoded-image-info?])
          (or/c 'bmp 'gif 'ico 'jpeg 'png 'wbmp 'webp 'pkm 'ktx 'astc 'dng 'heif 'avif 'jpeg-xl)]{
Returns the native encoded-format name. These symbols describe recognized
metadata values; they do not promise that every listed format is enabled in
an installed native library.
}

@defproc[(encoded-image-info-color-type [info encoded-image-info?])
          symbol?]{
Returns the native decoder's color-type name, such as @racket['rgba-8888].
It is not the encoded file format and need not equal the RGBA8888 output type
selected by @racket[codec->image]. Native metadata can describe formats beyond
the storage formats accepted by @racket[make-image-info].
}

@defproc[(encoded-image-info-alpha-type [info encoded-image-info?])
          (or/c 'unknown 'opaque 'premul 'unpremul)]{
Returns the source decoder's alpha interpretation. It need not equal the
premultiplied alpha type selected for @racket[codec->image]'s output.
}

@defproc[(encoded-image-info-origin [info encoded-image-info?])
          (or/c 'top-left 'top-right 'bottom-right 'bottom-left
                'left-top 'right-top 'right-bottom 'left-bottom)]{
Returns the @deftech{encoded orientation}, which specifies how stored pixel rows
and columns are oriented for display. The first part names the side
containing the first row; the second names the side containing the first column.
The @racket['left-top], @racket['right-top], @racket['right-bottom], and
@racket['left-bottom] orientations exchange axes. Use the display-dimension
queries when sizing an orientation-normalized result.
}

@defproc[(encoded-image-info-frame-count [info encoded-image-info?])
          exact-nonnegative-integer?]{
Returns the native animation-metadata count captured by the probe. A still
image commonly reports zero. This is not @racket[codec-frame-count], which
exposes one selectable frame for a still image.
}

@section{Animation Frame Information}

Use @racket[codec-frame-info] to inspect a frame's duration and update behavior
when implementing animation playback. Decode its pixels separately with
@racket[codec->image]; that operation reconstructs the frame's dependencies
without requiring you to supply earlier frames.

Frame information is stored in an immutable Racket structure. Durations are in milliseconds,
indices are zero-based, and rectangles remain in encoded pixel coordinates.

@defproc[(codec-frame-info [codec codec?] [index (integer-in 0 2147483647)])
          (or/c codec-frame-info? #f)]{
Returns metadata for a valid selectable frame. A still image with no native
animation metadata returns @racket[#f] for index zero. An invalid index or failure
to obtain metadata for an animation frame raises an exception.
The result does not contain the frame's pixels.
}

@defproc[(codec-frame-info? [v any/c])
          boolean?]{
Returns @racket[#t] for frame information and @racket[#f] otherwise.
}

@defproc[(codec-frame-info-index [info codec-frame-info?])
          exact-nonnegative-integer?]{
Returns the queried zero-based frame index.
}

@defproc[(codec-frame-info-required-frame [info codec-frame-info?])
          (or/c exact-nonnegative-integer? #f)]{
Returns an earlier frame required for reconstruction, or @racket[#f] when
none is required. A returned index is strictly less than the frame's index.
The one-shot decoder handles these dependencies; this field does not ask the
caller to supply a previous frame buffer.
}

@defproc[(codec-frame-info-duration [info codec-frame-info?])
          exact-nonnegative-integer?]{
Returns the frame duration in milliseconds; zero is permitted.
}

@defproc[(codec-frame-info-fully-received? [info codec-frame-info?])
          boolean?]{
Returns whether the native codec reports the frame data as fully received.
This metadata flag is not a substitute for a successful pixel decode.
}

@defproc[(codec-frame-info-alpha-type [info codec-frame-info?])
          (or/c 'unknown 'opaque 'premul 'unpremul)]{
Returns the native alpha interpretation reported for this frame.
}

@defproc[(codec-frame-info-has-alpha-within-bounds? [info codec-frame-info?])
          boolean?]{
Returns the native flag indicating transparency within the frame rectangle.
It describes the frame update, not necessarily the composited full image.
}

@defproc[(codec-frame-info-disposal-method [info codec-frame-info?])
          (or/c 'keep 'restore-background 'restore-previous)]{
Returns how playback treats the frame after its display duration: retain the
result, restore the update region to the background, or restore the previous
state. The codec applies required disposal when reconstructing a later frame.
}

@defproc[(codec-frame-info-blend [info codec-frame-info?])
          (or/c 'src-over 'src)]{
Returns whether the update composites over its preceding image or replaces
the update region. This is frame metadata, not the paint used to draw a decoded
image onto another canvas.
}

@defproc[(codec-frame-info-rect [info codec-frame-info?])
          (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 immutable?)]{
Returns an immutable vector containing x, y, width, and height of the frame
update in encoded coordinates. The rectangle is not orientation-normalized or
scaled to a later drawing destination.
}

@section{Native Size and Subset Negotiation}

@defmodule[skia/codec-queries #:no-declare]
@(declare-exporting skia skia/codec-queries #:use-sources (skia/codec-queries))

These queries ask what the native decoder can support. They do not decode,
crop, resample, or change the codec. A successful query is not a request to
apply its result in a subsequent @racket[codec->image] call.

@defproc[(codec-scaled-dimensions [codec codec?] [scale (and/c real? (>/c 0))])
          (values exact-positive-integer? exact-positive-integer?)]{
Returns the native decoder's proposed pixel dimensions for @racket[scale].
The scale must remain strictly positive after binary32
rounding. A positive value that rounds to zero is rejected. Scales above one
are accepted as queries, but returned dimensions do not exceed the encoded size.
The result may be a supported approximation rather than the requested ratio.
No full-raster allocation is performed.
}

@defproc[(codec-supported-subset [codec codec?]
          [x (integer-in 0 2147483647)] [y (integer-in 0 2147483647)]
          [width (integer-in 1 2147483647)] [height (integer-in 1 2147483647)])
          (or/c #f
                (and/c (vector/c exact-integer? exact-integer? exact-positive-integer?
                                 exact-positive-integer?)
                       immutable?))]{
Returns the native decoder's proposed subset as an immutable x, y, width,
height vector, or @racket[#f] when subset decoding is unsupported. The requested
rectangle must be nonempty and inside the encoded image; its right and bottom
must fit signed 32-bit integers. The returned rectangle is validated against
encoded bounds, but is not promised to equal or contain the requested rectangle.
No fallback to complete decoding and cropping is performed.
}
