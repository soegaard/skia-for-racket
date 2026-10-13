#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-png"]{Image Encoding}

@defproc[(save-png [surface surface?] [filename path-string?]
                   [#:exists exists (or/c 'error 'replace) 'error]
                   [#:compression compression (integer-in 0 9) 6]
                   [#:color-space space (or/c color-space? #f) #f]
                   [#:icc-profile profile (or/c bytes? #f) #f]
                   [#:icc-description description (or/c string? #f) #f]) void?]{
Encodes the current pixels of an open CPU surface as PNG and writes them to
@racket[filename]. The operation does not close the surface or change its
pixels. A GPU surface is rejected; obtain a separate CPU image through an
explicit GPU readback API before using the corresponding image encoder.

The default @racket['error] refuses to replace an existing file. The
@racket['replace] mode permits replacement. The parent directory must already
exist. The compression setting ranges from 0 through 9 and defaults to 6.

The following example permits running the same save more than once:

@racketblock[
(with-skia ([surface (make-surface 80 40 #:background 'white)])
  (save-png surface "blank.png" #:exists 'replace))
]

The complete PNG is encoded before the destination is opened. An encoding
failure therefore does not truncate an existing destination. A filesystem
failure during writing is still possible; this procedure does not promise an
atomic file replacement or rollback of a partially written file.

The optional @racket[space] requests sample conversion before encoding. The
source must already have a color-space tag; the operation does not guess the
meaning of untagged samples. The original surface is unchanged.

The optional @racket[profile] overrides output color metadata, not pixel samples.
It must be a supported SDR RGB matrix/TRC ICC profile with XYZ profile connection
space, valid tag ranges, and a declared byte length equal to the supplied length.
LUT and HDR profile overrides are rejected. The profile must be at least 132
bytes and fit @racket[(current-skia-byte-limit)]. Native profile parsing can also
reject unsupported or invalid data. The encoder may regenerate the profile
rather than copy its bytes verbatim.

The optional @racket[description] requires @racket[profile]. It must contain 1
through 4096 printable ASCII characters; its terminating NUL also counts against
the byte limit. With a supplied profile, @racket[#f] uses the encoder's default
description.
The caller is responsible for supplying an ICC profile that describes the encoded
samples. The library checks the profile's format and whether it is supported for
encoding, but does not verify that it agrees with those samples. Attaching a
profile does not convert the samples.

Native allocation, encoding, output-size limits, invalid resources, and
filesystem errors are reported as exceptions. See
@seclink["top" #:doc '(lib "skia/scribblings/tutorials/color-spaces/color-spaces.scrbl")]{
Color Spaces} for examples of tags and conversion.
}

@section[#:tag "skia-encoding-bytes"]{Encoding to Byte Strings}

The byte-returning encoders produce new mutable byte strings. They neither
write files nor close their input resources. The entire result must fit
@racket[current-skia-byte-limit]. Encoding may first decode or materialize
CPU-compatible pixels; GPU-dependent input is rejected. Native failure raises
an exception rather than returning a partially encoded result.

Color-space conversion, ICC override restrictions, and the caller's
responsibility for matching profiles to samples are the same as for
@racket[save-png]. A conversion request changes samples in temporary storage;
an ICC override changes their description. Neither changes the source image.

@defproc[(surface->png-bytes [surface surface?]
                            [#:compression compression (integer-in 0 9) 6]
                            [#:color-space space (or/c color-space? #f) #f]
                            [#:icc-profile profile (or/c bytes? #f) #f]
                            [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes a temporary snapshot of an open CPU surface as PNG. The options have
the same meaning as for @racket[save-png], but no output file is opened.
The temporary image is released when encoding finishes or raises an exception.
}

@defproc[(image->png-bytes [image image?]
                          [#:compression compression (integer-in 0 9) 6]
                          [#:color-space space (or/c color-space? #f) #f]
                          [#:icc-profile profile (or/c bytes? #f) #f]
                          [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes an image as PNG. The compression setting changes encoding effort and
size, not a lossy-quality target. Pixel-format conversion, alpha conversion,
and an explicitly requested color-space conversion can still change numerical
samples before encoding. Options follow @racket[save-png].

@racketblock[
(with-skia ([image (rgba-bytes->image 1 1 (bytes 50 109 230 255))]
            [decoded (image-from-bytes (image->png-bytes image))])
  (bytes->list (image->rgba-bytes decoded)))
]
}

@defproc[(image->jpeg-bytes [image image?]
                           [#:quality quality (integer-in 0 100) 90]
                           [#:downsample downsample (or/c 'yuv-420 'yuv-422 'yuv-444) 'yuv-420]
                           [#:alpha alpha (or/c 'ignore 'blend-on-black) 'ignore]
                           [#:color-space space (or/c color-space? #f) #f]
                           [#:icc-profile profile (or/c bytes? #f) #f]
                           [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes the image as lossy JPEG. Higher quality requests less quantization,
not a particular output size. The downsampling option selects chroma resolution:
@racket['yuv-420] subsamples both axes, @racket['yuv-422] the horizontal axis,
and @racket['yuv-444] neither axis.

JPEG does not retain an alpha channel. The @racket['ignore] option discards alpha;
@racket['blend-on-black] composites against black before encoding. The profile
and conversion options follow @racket[save-png].
}

@defproc[(image->webp-bytes [image image?]
                           [#:quality quality (real-in 0 100) 90]
                           [#:lossless? lossless? boolean? #f]
                           [#:color-space space (or/c color-space? #f) #f]
                           [#:icc-profile profile (or/c bytes? #f) #f]
                           [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes the image as WebP. Lossy mode is the default. In lossy mode, quality
controls the requested quality/size tradeoff; in lossless mode it controls
compression effort rather than a permitted loss of pixel information. The
quality argument is a real number, unlike JPEG's integer quality argument.
Color conversion and ICC options follow @racket[save-png].
}

@defproc[(image->encoded-bytes [image image?] [format (or/c 'png 'jpeg 'webp)]
                              [#:quality quality (real-in 0 100) 90]
                              [#:png-compression compression (integer-in 0 9) 6]
                              [#:jpeg-downsample downsample
                               (or/c 'yuv-420 'yuv-422 'yuv-444) 'yuv-420]
                              [#:jpeg-alpha alpha (or/c 'ignore 'blend-on-black) 'ignore]
                              [#:webp-lossless? lossless? boolean? #f]
                              [#:color-space space (or/c color-space? #f) #f]
                              [#:icc-profile profile (or/c bytes? #f) #f]
                              [#:icc-description description (or/c string? #f) #f]) bytes?]{
Dispatches to the PNG, JPEG, or WebP encoder according to @racket[format]. The
quality argument must be an exact integer for JPEG; WebP accepts a real quality.
PNG uses the PNG-compression setting instead. Format-specific options are passed
only to the selected encoder; unused options do not affect the result and are
not validated by another encoder.
}

@section{Writing Encoded Images}

@defproc[(save-image [image image?] [filename path-string?] [format (or/c 'png 'jpeg 'webp)]
                     [#:exists exists (or/c 'error 'replace) 'error]
                     [#:quality quality (real-in 0 100) 90]
                     [#:png-compression compression (integer-in 0 9) 6]
                     [#:jpeg-downsample downsample (or/c 'yuv-420 'yuv-422 'yuv-444) 'yuv-420]
                     [#:jpeg-alpha alpha (or/c 'ignore 'blend-on-black) 'ignore]
                     [#:webp-lossless? lossless? boolean? #f]
                     [#:color-space space (or/c color-space? #f) #f]
                     [#:icc-profile profile (or/c bytes? #f) #f]
                     [#:icc-description description (or/c string? #f) #f]) void?]{
Encodes with @racket[image->encoded-bytes] and writes the completed bytes to
@racket[filename]. The format argument, not the filename extension, chooses the
encoder. The exists modes and encode-before-open behavior match @racket[save-png].
An existing parent directory is required. The image remains open; a write error
can still leave a partial output file.
}
