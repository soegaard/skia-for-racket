#lang scribble/manual

@(require (for-label racket/base racket/contract file/convertible skia))

@title[#:tag '("skia-png" "skia-encoding")]{Image Encoding}

These functions encode images as PNG, JPEG, or WebP. Choose an interface
according to how you select the format and where you want the result:

@itemlist[
 @item{For a known format, use @racket[image->png-bytes],
   @racket[image->jpeg-bytes], or @racket[image->webp-bytes]. Each returns a byte
   string and accepts only the options relevant to its format.}
 @item{For a format selected at runtime, use @racket[image->encoded-bytes].
   Pass @racket['png], @racket['jpeg], or @racket['webp] as its format argument.}
 @item{To write an image to a file, use @racket[save-image]. It accepts the same
   format choices and encoding options as @racket[image->encoded-bytes].}]

The general byte encoder and file writer are counterparts:
@racket[save-image] calls @racket[image->encoded-bytes] and writes the completed
bytes to a file. Its format argument, not the filename extension, determines
the file format. The format-specific byte encoders provide simpler interfaces
when you already know which format you want.

For a CPU surface, @racket[save-png] and @racket[surface->png-bytes] provide PNG
output directly, without requiring you to create an image first.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-encoding-bytes"]{Encoding Images to Byte Strings}

The byte-returning encoders produce new mutable byte strings. They neither
write files nor close their input resources. The entire result must fit
@racket[current-skia-byte-limit]. Encoding may first decode or generate
CPU-compatible pixels; GPU-dependent input is rejected. Native failure raises
an exception rather than returning a partially encoded result.

See @secref["skia-encoding-options"] for the color-space conversion and
ICC-profile options shared by these encoders.

@defproc[(image->png-bytes [image image?]
                          [#:compression compression (integer-in 0 9) 6]
                          [#:color-space space (or/c color-space? #f) #f]
                          [#:icc-profile profile (or/c bytes? #f) #f]
                          [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes an image as PNG. The compression setting changes encoding effort and
size, not a lossy-quality target. Pixel-format conversion, alpha conversion,
and an explicitly requested color-space conversion can still change numerical
samples before encoding. Color-space and ICC-profile options follow
@secref["skia-encoding-options"].

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
and conversion options follow @secref["skia-encoding-options"].
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
Color conversion and ICC options follow @secref["skia-encoding-options"].
}

@defproc[(image->encoded-bytes [image image?] [format (or/c 'png 'jpeg 'webp)]
                              [#:quality quality any/c 90]
                              [#:png-compression compression any/c 6]
                              [#:jpeg-downsample downsample any/c 'yuv-420]
                              [#:jpeg-alpha alpha any/c 'ignore]
                              [#:webp-lossless? lossless? any/c #f]
                              [#:color-space space (or/c color-space? #f) #f]
                              [#:icc-profile profile (or/c bytes? #f) #f]
                              [#:icc-description description (or/c string? #f) #f]) bytes?]{
Dispatches to @racket[image->png-bytes], @racket[image->jpeg-bytes], or
@racket[image->webp-bytes] according to @racket[format].

The contracts of the format-specific options depend on @racket[format], as shown
in the table. An option marked Ignored is not inspected by the selected encoder and
may have any value. The @racket[any/c] contracts in the signature do not relax
the restrictions on an option used by the selected format.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Keyword} @bold{PNG} @bold{JPEG} @bold{WebP})
  (list @racket[#:quality] "Ignored"
        @racket[(integer-in 0 100)] @racket[(real-in 0 100)])
  (list @racket[#:png-compression] @racket[(integer-in 0 9)] "Ignored" "Ignored")
  (list @racket[#:jpeg-downsample] "Ignored"
        @racket[(or/c 'yuv-420 'yuv-422 'yuv-444)] "Ignored")
  (list @racket[#:jpeg-alpha] "Ignored"
        @racket[(or/c 'ignore 'blend-on-black)] "Ignored")
  (list @racket[#:webp-lossless?] "Ignored" "Ignored" @racket[boolean?]))]

For PNG, @racket[#:png-compression] supplies the encoder's @racket[#:compression]
argument. For JPEG, @racket[#:jpeg-downsample] and @racket[#:jpeg-alpha] supply
@racket[#:downsample] and @racket[#:alpha]. For WebP, @racket[#:webp-lossless?]
supplies @racket[#:lossless?]. Their meanings and defaults are those of the
corresponding encoder.

The common @racket[#:color-space], @racket[#:icc-profile], and
@racket[#:icc-description] options apply to all three formats, as described in
@secref["skia-encoding-options"].

For example, PNG accepts arbitrary values for the options of the other formats:

@racketblock[
(with-skia ([image (rgba-bytes->image 1 1 (bytes 50 109 230 255))])
  (define encoded
    (image->encoded-bytes image 'png
                         #:quality 'unused
                         #:jpeg-downsample 'unused
                         #:jpeg-alpha 'unused
                         #:webp-lossless? 'unused))
  (subbytes encoded 0 8))
]

The result is the PNG signature. In contrast, an invalid
@racket[#:png-compression] value is rejected for this call.
}

@section{Writing Images to Files}

@defproc[(save-image [image image?] [filename path-string?] [format (or/c 'png 'jpeg 'webp)]
                     [#:exists exists (or/c 'error 'replace) 'error]
                     [#:quality quality any/c 90]
                     [#:png-compression compression any/c 6]
                     [#:jpeg-downsample downsample any/c 'yuv-420]
                     [#:jpeg-alpha alpha any/c 'ignore]
                     [#:webp-lossless? lossless? any/c #f]
                     [#:color-space space (or/c color-space? #f) #f]
                     [#:icc-profile profile (or/c bytes? #f) #f]
                     [#:icc-description description (or/c string? #f) #f]) void?]{
Encodes with @racket[image->encoded-bytes] and writes the completed bytes to
@racket[filename]. The format argument, not the filename extension, chooses the
encoder. The format-specific option contracts, defaults, and ignored values
follow the table in @racket[image->encoded-bytes].

The color-management options in @secref["skia-encoding-options"] apply to every
format. File replacement, errors, and the order of encoding and writing follow
@secref["skia-encoding-file-writing"]. The image remains open and unchanged.
}

@section{PNG Surface Output}

These functions encode a CPU surface directly as PNG. To encode a surface in
another format, first create an image with @racket[surface-snapshot] and use an
image encoder.

@defproc[(surface->png-bytes [surface surface?]
                            [#:compression compression (integer-in 0 9) 6]
                            [#:color-space space (or/c color-space? #f) #f]
                            [#:icc-profile profile (or/c bytes? #f) #f]
                            [#:icc-description description (or/c string? #f) #f]) bytes?]{
Encodes a temporary snapshot of an open CPU surface as PNG. The compression
option has the same meaning as for @racket[image->png-bytes]; color-space and
ICC-profile options follow @secref["skia-encoding-options"].
The byte-string, size-limit, and error rules in @secref["skia-encoding-bytes"]
also apply here. No output file is opened, and the surface remains open and
unchanged. The temporary image is released when encoding finishes or raises
an exception.

Surfaces also support PNG conversion through @racketmodname[file/convertible].
The expression @racket[(convert surface 'png-bytes)] is equivalent to
@racket[(surface->png-bytes surface)] with the default options. Other conversion
requests return the supplied default value without inspecting the surface.
For a @racket['png-bytes] request, conversion errors raise exceptions even when
a default value is supplied.
}

@defproc[(save-png [surface surface?] [filename path-string?]
                   [#:exists exists (or/c 'error 'replace) 'error]
                   [#:compression compression (integer-in 0 9) 6]
                   [#:color-space space (or/c color-space? #f) #f]
                   [#:icc-profile profile (or/c bytes? #f) #f]
                   [#:icc-description description (or/c string? #f) #f]) void?]{
Encodes the current pixels of an open CPU surface as PNG and writes them to
@racket[filename]. The operation does not close the surface or change its
pixels. A GPU surface is rejected; obtain a separate CPU image through an
explicit @tech{GPU readback} API before using the corresponding image encoder.

Encoding options and size limits are the same as for
@racket[surface->png-bytes]. The compression setting ranges from 0 through 9
and defaults to 6. File replacement, errors, and the order of encoding and
writing follow @secref["skia-encoding-file-writing"].

The following example permits running the same save more than once:

@racketblock[
(with-skia ([surface (make-surface 80 40 #:background 'white)])
  (save-png surface "blank.png" #:exists 'replace))
]
}

@section[#:tag "skia-encoding-options"]{Shared Encoding Options}

All encoders and file writers in this chapter accept @racket[#:color-space],
@racket[#:icc-profile], and @racket[#:icc-description]. Use
@racket[#:color-space] to convert colors before encoding, or
@racket[#:icc-profile] to specify how the encoded color values should be
interpreted. Neither option changes the source image or surface.

Supplying a color space with @racket[#:color-space] requests conversion in
temporary storage before encoding. The source must already have a color-space
tag; the operation does not guess the meaning of untagged samples.

Supplying an @tech{ICC profile} with @racket[#:icc-profile] overrides output
color metadata, not pixel samples. The caller is responsible for supplying a
profile that describes the encoded samples. The library checks the profile's
format and whether it is supported for encoding, but does not verify that it
agrees with those samples. Attaching a profile does not convert the samples.

The profile must be a supported SDR RGB matrix/TRC profile with XYZ profile
connection space, valid tag ranges, and a declared byte length equal to the
supplied length. LUT and HDR profile overrides are rejected. The profile must
be at least 132 bytes and fit @racket[(current-skia-byte-limit)]. Native
profile parsing can also reject unsupported or invalid data. The encoder may
regenerate the profile rather than copy its bytes verbatim.

Supplying a string with @racket[#:icc-description] requires an
@racket[#:icc-profile] override. The description must contain 1 through 4096
printable ASCII characters; its terminating NUL also counts against the byte
limit. With a supplied profile, @racket[#f] uses the encoder's default
description.

See @seclink["top"
             #:doc '(lib "skia/scribblings/tutorials/color-spaces/color-spaces.scrbl")]{
Color Spaces} for examples of tags and conversion.

@section[#:tag "skia-encoding-file-writing"]{File-Writing Behavior}

The @racket[save-image] and @racket[save-png] functions share the following
file-writing behavior.

The @racket[#:exists] argument defaults to @racket['error], which refuses to
replace an existing file. Passing @racket['replace] permits replacement.
The parent directory must already exist.

The complete image is encoded before the destination is opened. An encoding
failure therefore does not truncate an existing destination. Allocation and
encoding failures, output-size limit violations, invalid resources, and
filesystem errors raise exceptions.

A filesystem failure during writing can leave a partial output file.
Neither function promises atomic file replacement or rollback of a partially
written file.
