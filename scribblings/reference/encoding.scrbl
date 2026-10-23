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

@section[#:tag "skia-encoding-destinations"]{Choosing an Output Destination}

The byte-string and file interfaces above produce the complete encoded result
before returning bytes or replacing a file. The live writers in
@secref["skia-live-streams"] send encoded bytes to a port or native stream as
encoding proceeds. All four destinations support PNG, JPEG, and WebP, but
their failure behavior differs:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Destination} @bold{Interface} @bold{On failure})
  (list "Byte string" @racket[image->encoded-bytes] "No partial result is returned")
  (list "File" @racket[save-image] "An existing destination is unchanged")
  (list "Racket port" @racket[image->port] "A written prefix can remain")
  (list "Native stream" @racket[image-write-stream!] "A written prefix can remain"))]

All four interfaces accept the same encoding options and defaults, including
color-space conversion, ICC-profile overrides, and fractional WebP quality.
A non-@racket[#f] option belonging to another format raises an exception.
See @racket[image->encoded-bytes] for the common format-option table.

Live output does not require a complete encoded byte string, but it may still
need decoded pixel storage. It is not a promise of constant memory. Port output
offers cancellation and optional port closure; native-stream output offers
neither keyword and appends to the stream's current contents. A failure after
the native-stream writer takes exclusive use prevents further use of that
stream; close it instead of retrying. See @secref["skia-native-publication"]
for the stream's ownership and failure rules, and
@secref["skia-encoding-file-writing"] for file replacement guarantees.

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

JPEG cannot store transparency. The @racket['ignore] option discards alpha
without undoing premultiplication. With @tech{premultiplied alpha}, translucent
colors can therefore appear darker. The @racket['blend-on-black] option resolves
transparency against black before encoding.

@;{The installed m119 encoder passes premultiplied RGBA/BGRA samples through
   without unpremultiplying for kIgnore. See mono/skia at
   40f75dc0051d141913c07c20d4c19590c7da0cb7, src/encode/SkJpegEncoderImpl.cpp,
   SkJpegEncoderMgr::setParams.}

To choose another background, draw the image onto an opaque surface of that
color and encode a @racket[surface-snapshot]. The profile and conversion
options follow @secref["skia-encoding-options"].
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
                              [#:quality quality (or/c #f (real-in 0 100)) #f]
                              [#:png-compression compression (or/c #f (integer-in 0 9)) #f]
                              [#:jpeg-downsample downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444) #f]
                              [#:jpeg-alpha alpha (or/c #f 'ignore 'blend-on-black) #f]
                              [#:webp-lossless? lossless? boolean? #f]
                              [#:color-space space (or/c color-space? #f) #f]
                              [#:icc-profile profile (or/c bytes? #f) #f]
                              [#:icc-description description (or/c string? #f) #f]) bytes?]{
Dispatches to @racket[image->png-bytes], @racket[image->jpeg-bytes], or
@racket[image->webp-bytes] according to @racket[format].

The format-specific options default to @racket[#f], meaning unspecified. The
selected encoder then uses its normal defaults. Supplying a non-@racket[#f]
option for another format raises an exception, rather than silently ignoring it.
The table shows which formats accept each option and its contract when supplied.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Keyword} @bold{PNG} @bold{JPEG} @bold{WebP})
  (list @racket[#:quality] @racket[#f]
        @racket[(integer-in 0 100)] @racket[(real-in 0 100)])
  (list @racket[#:png-compression] @racket[(integer-in 0 9)] @racket[#f] @racket[#f])
  (list @racket[#:jpeg-downsample] @racket[#f]
        @racket[(or/c 'yuv-420 'yuv-422 'yuv-444)] @racket[#f])
  (list @racket[#:jpeg-alpha] @racket[#f]
        @racket[(or/c 'ignore 'blend-on-black)] @racket[#f])
  (list @racket[#:webp-lossless?] @racket[#f] @racket[#f] @racket[boolean?]))]

For PNG, @racket[#:png-compression] supplies the encoder's @racket[#:compression]
argument. For JPEG, @racket[#:jpeg-downsample] and @racket[#:jpeg-alpha] supply
@racket[#:downsample] and @racket[#:alpha]. For WebP, @racket[#:webp-lossless?]
supplies @racket[#:lossless?]. Their meanings and defaults are those of the
corresponding encoder: PNG compression 6, JPEG and WebP quality 90, JPEG
downsampling @racket['yuv-420] and alpha handling @racket['ignore], and lossy
WebP encoding. JPEG quality must be an exact integer; WebP also accepts
fractional quality.

The common @racket[#:color-space], @racket[#:icc-profile], and
@racket[#:icc-description] options apply to all three formats, as described in
@secref["skia-encoding-options"].

For example, select PNG compression without supplying JPEG or WebP options:

@racketblock[
(with-skia ([image (rgba-bytes->image 1 1 (bytes 50 109 230 255))])
  (define encoded
    (image->encoded-bytes image 'png #:png-compression 6))
  (subbytes encoded 0 8))
]

The result is the PNG signature. Adding @racket[#:quality 90] to this call
raises an exception because PNG does not use a quality setting.
}

@section{Writing Images to Files}

@defproc[(save-image [image image?] [filename path-string?] [format (or/c 'png 'jpeg 'webp)]
                     [#:exists exists (or/c 'error 'replace) 'error]
                     [#:quality quality (or/c #f (real-in 0 100)) #f]
                     [#:png-compression compression (or/c #f (integer-in 0 9)) #f]
                     [#:jpeg-downsample downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444) #f]
                     [#:jpeg-alpha alpha (or/c #f 'ignore 'blend-on-black) #f]
                     [#:webp-lossless? lossless? boolean? #f]
                     [#:color-space space (or/c color-space? #f) #f]
                     [#:icc-profile profile (or/c bytes? #f) #f]
                     [#:icc-description description (or/c string? #f) #f]) void?]{
Encodes with @racket[image->encoded-bytes] and writes the completed bytes to
@racket[filename]. The format argument, not the filename extension, chooses the
encoder. The format-specific option contracts, defaults, and restrictions
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

For PNG conversion through @racketmodname[file/convertible], see
@secref["skia-encoding-convertible"].
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

@section[#:tag "skia-encoding-convertible"]{Standard PNG Conversion}

Images and surfaces accept @racket['png-bytes] through
@racketmodname[file/convertible], using the corresponding encoder's defaults.
The resource must be open and CPU-compatible; GPU pixels require explicit
@tech{GPU readback} first. See @secref["skia-standard-conversion"] for the
conversion table, shared error rules, and an example. Call an encoder directly
to select encoding options.

@section[#:tag "skia-encoding-options"]{Shared Encoding Options}

The byte-string encoders and file writers described here accept
@racket[#:color-space], @racket[#:icc-profile], and @racket[#:icc-description].
The live writers compared in @secref["skia-encoding-destinations"] do not. Use
@racket[#:color-space] to convert colors before encoding, or
@racket[#:icc-profile] to specify how the encoded color values should be
interpreted. Neither option changes the source image or surface.

Supplying a @tech{color space} with @racket[#:color-space] requests conversion in
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

The destination is resolved before encoding. The complete image is encoded,
then written to a temporary file in the destination directory. Only after the
write succeeds is that file renamed to the destination. Encoding or writing
failure leaves an existing destination unchanged and removes the temporary
file. The @racket['error] policy is checked again at rename time, so a file
created in the meantime is not overwritten.

Allocation and encoding failures, output-size limit violations, invalid
resources, and filesystem errors raise exceptions. The rename publishes a
complete file; it does not promise that the data will survive a system crash.
