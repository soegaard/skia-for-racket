#lang scribble/manual

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia))
@(define-runtime-path program-source "color-study.rkt")

@title{Color Spaces — Give Pixel Values Their Meaning}

@section{The Finished Color Study}

@(color-study-pict)

Both large swatches started with RGB bytes (128, 128, 128). The left source was
declared to be sRGB; the right source was declared to be linear sRGB. The right
source was then converted to sRGB so the two could be displayed consistently.
The same initial numbers did not represent the same color.

@centered{@bold{Declare what samples mean. Convert samples when that meaning changes.
Write a profile that describes the result.}}

This tutorial builds the comparison and saves a tagged PNG. It does not attempt
to calibrate a monitor or make every display look identical. Save the complete
@filepath{color-study.rkt} file from the end to use the helpers below.

@section{Keep the Numbers Separate from Their Meaning}

A color space supplies an interpretation for RGB numbers. Linear sRGB and sRGB
use the same primaries, but different transfer functions. Linear values describe
relative light intensity; ordinary sRGB samples use a nonlinear encoding.
Half the encoded range is therefore not half the linear-light intensity.

Create one space of each kind:

@colors-racketblock+eval[
(require skia "color-study.rkt")
(define srgb (make-srgb-color-space))
(define linear (make-linear-srgb-color-space))
]

The @racket[#:color-space] argument on @racket[rgba-bytes->image] declares the
meaning of supplied samples. It does not change their bytes:

@colors-racketblock+eval[
(define encoded-gray
  (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space srgb))
(define linear-gray
  (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space linear))
]

@colors-interaction[
(bytes->list (image->rgba-bytes encoded-gray))
(bytes->list (image->rgba-bytes linear-gray))
]

The two readbacks contain the same numbers. Their color-space tags differ.
This is why comparing raw RGB bytes is not sufficient to compare tagged colors.
The fourth byte is alpha, which is not sRGB-encoded.

@section{Convert before Comparing}

To express the linear sample in sRGB, convert it:

@colors-racketblock+eval[
(define converted-gray (image-convert-color-space linear-gray srgb))
]

@colors-interaction[
(bytes->list (image->rgba-bytes converted-gray))
(bytes->list (image->rgba-bytes linear-gray))
]

The converted RGB channels are approximately 188 rather than 128. The source
image is unchanged, and the converted image is independently owned and tagged
with the destination space. Alpha remains 255.

@(gray-pair-pict)

These are the actual one-pixel images, enlarged with nearest sampling. Both
previews use sRGB samples: the right one uses the converted image. The visual
difference is not created by painting a second, hand-chosen gray.

Conversion aims to preserve the represented color by changing its numerical
encoding. Attaching a different tag to unchanged samples instead changes their
interpretation. These are different operations, even when the same two color
spaces are involved.

@section{Compare Two Gray Ramps}

The following helper creates 256 equally spaced gray sample values:

@codeblock[(source-definition program-source 'ramp-bytes)]

Interpret one copy as sRGB and the other as linear sRGB. Convert the linear
copy before displaying it:

@colors-racketblock+eval[
(define samples (ramp-bytes))
(define encoded-ramp (rgba-bytes->image 256 1 samples #:color-space srgb))
(define linear-ramp (rgba-bytes->image 256 1 samples #:color-space linear))
(define converted-ramp (image-convert-color-space linear-ramp srgb))
]

@(ramp-pair-pict)

Each source is 256 by 1 pixel. The previews stretch it into a readable strip
with nearest sampling. The second ramp has equal steps in its original
linear-light samples; converting those samples to sRGB produces unequal steps
in the encoded output.

This is also why averaging encoded RGB channels, as in the preceding artistic
image processor, is not the same as averaging light. A physically motivated
blend generally needs the appropriate linear-light values. That is a choice
about the computation, separate from how its output is encoded for storage.

@section{Do Not Guess an Untagged Source}

An untagged image does not say whether its numbers are sRGB, linear sRGB, or
something else. The conversion function refuses to guess:

@colors-racketblock+eval[
(define untagged (rgba-bytes->image 1 1 (bytes 128 128 128 255)))
]

Because we created these bytes ourselves and know they are linear, we can make
that declaration explicitly:

@colors-racketblock+eval[
(define declared-result
  (image-convert-color-space untagged srgb #:source-color-space linear))
]

This declaration is not a repair for an unknown photograph. Use source metadata
or knowledge of the producing application, rather than choosing whichever tag
makes an image look pleasing. Supplying @racket[#:source-color-space] for an
already-tagged image is rejected so an existing interpretation cannot be
silently replaced.

@section{Write a Matching ICC Profile}

An ICC profile describes a color space in the encoded file. Create profile
bytes from the same sRGB space used for the converted image:

@colors-racketblock+eval[
(define profile (color-space->icc-bytes srgb))
]

The image is already converted, so the profile must describe its current
samples:

@racketblock[
(save-image converted-gray "converted-gray.png" 'png
            #:icc-profile profile
            #:icc-description "Converted sRGB sample"
            #:exists 'replace)
]

The encoder's @racket[#:icc-profile] override changes profile metadata, not the
samples. Writing an sRGB profile onto unchanged linear samples would mislabel
them. The encoder's @racket[#:color-space] option, in contrast, requests sample
conversion before encoding. Do not confuse that conversion option with the
profile override.

An explicit profile is not mandatory for every sRGB PNG: the native encoder can
write suitable color metadata for tagged images. This example supplies one so
the relationship between converted samples and their description is explicit.

A profile can also be imported as a color-space object:

@colors-racketblock+eval[
(define restored-space (color-space-from-icc-bytes profile))
]
@colors-interaction[(color-space? restored-space)]

This is a semantic color-space round trip, not a promise that exported ICC bytes
preserve every original tag or reproduce the input file byte for byte.

@section{Assemble the Comparison Card}

The card renders into an explicitly sRGB-tagged surface. The swatches and ramps
have already been normalized to that same space:

@racketblock[
(define images (make-color-study))
(define surface (make-surface 740 490 #:color-space srgb))
(draw-color-study (surface-canvas surface) images)
(save-png surface "color-study.png"
          #:icc-profile profile #:icc-description "Skia color study - sRGB"
          #:exists 'replace)
]

@(color-study-pict)

The numerical labels are read from the actual converted pixels. They are not
independent color constants. The finished program also writes the small
@filepath{converted-gray.png} and a @filepath{study-srgb.icc} profile.

@section{The Complete Program}

Run the example with @tt{racket color-study.rkt}:

@codeblock[(file->string program-source)]

@section{Try It}

Replace the initial 128 with 64. Predict whether conversion from linear sRGB
will increase or decrease the encoded sRGB value, then inspect the readback.
Keep the source image unchanged and compare its bytes afterward.

Try a colored rather than neutral sample. Check that only RGB passes through
the transfer function; alpha has a different meaning. Work with opaque samples
first to avoid confusing color conversion with low-alpha quantization.

@section{Where to Go From Here}

The example stays within eight-bit SDR RGB. Other gamuts, such as Display P3,
change more than the transfer curve. Converting out-of-gamut colors may clamp
values; neither this example nor the profile override performs perceptual gamut
mapping, HDR tone mapping, or display calibration.

The Guide covers custom RGB spaces and encoder restrictions. The upstream
@hyperlink["https://skia.org/docs/user/color/"]{Skia color-management overview}
provides background on tagged images and destination color spaces.
