#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia))
@(define-runtime-path program-source "color-study.rkt")

@title{Color Spaces — Give Pixel Values Their Meaning}

@section[#:tag "finished-result"]{The Finished Color Study}

@(tutorial-figure
   (string-append
    "The same RGB sample 128 is interpreted as sRGB on the left and linear sRGB on the "
    "right. After conversion for display, the right swatch is lighter. The ramps compare "
    "equal encoded and equal linear-light steps.")
   (color-study-pict))

Both large swatches started with RGB bytes (128, 128, 128). The left source was
declared to be sRGB; the right source was declared to be linear sRGB. The right
source was then converted to sRGB so the two could be displayed consistently.
The same initial numbers did not represent the same color.

@centered{@bold{Declare the source space. Convert to preserve the color.
Write a profile that describes the result.}}

This tutorial builds the comparison and saves a tagged PNG. It does not attempt
to calibrate a monitor or make every display look identical. Save the complete
@filepath{color-study.rkt} file from the end to use the helpers below.

@tutorial-entry["color-spaces"]

@section[#:tag "color-numbers-and-meaning"]{Keep the Numbers Separate from Their Meaning}

A color space supplies an interpretation for RGB numbers. Its @emph{primaries}
are the reference red, green, and blue colors. A @emph{transfer function} maps
between stored channel values and linear-light values. A @emph{tagged image}
carries color-space information that identifies how to interpret its samples.

Linear sRGB and sRGB use the same primaries but different transfer functions.
Linear values describe relative light intensity; ordinary sRGB samples use a
nonlinear encoding. Half the encoded range is therefore not half the
linear-light intensity.

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

@(tutorial-figure
   (string-append
    "The sRGB sample remains near 128. The linear sample converted to sRGB is near 188, "
    "giving a lighter gray although the source numbers were identical.")
   (gray-pair-pict))

The one-pixel images are enlarged to 140 by 140 logical display units with
nearest sampling. Both previews use sRGB samples; the right one uses the
converted image.

Conversion aims to preserve the represented color by changing its numerical
encoding. Attaching a different tag to unchanged samples instead changes their
interpretation. These are different operations, even when the same two color
spaces are involved.

Skia can also convert a tagged source while drawing into a tagged destination.
Explicitly converting every image in advance is not mandatory. Here is the
same linear source drawn directly into a one-pixel sRGB surface:

@colors-racketblock+eval[
(define preview (make-surface 1 1 #:color-space srgb))
(draw-image (surface-canvas preview) linear-gray 0 0)
]
@colors-interaction[(bytes->list (surface->rgba-bytes preview))]

The surface contains approximately 188 in each RGB channel, just like the
explicitly converted image. The source image still contains linear samples of
128. Drawing performed the conversion without modifying the source.

For comparison, deliberately attach the wrong tag to the original bytes:

@colors-racketblock+eval[
(define wrong-tag
  (rgba-bytes->image 1 1 (image->rgba-bytes linear-gray) #:color-space srgb))
]

@(tutorial-figure
   (string-append
    "Automatic conversion during drawing and explicit conversion give the same lighter "
    "gray. Mislabeling the unchanged linear samples as sRGB gives the darker third "
    "swatch.")
   (conversion-pict))

All three panels are drawn into sRGB surfaces. The first uses the tagged linear
source and lets drawing perform the conversion. The second uses the explicitly
converted image; it represents the same gray. The third takes the original
linear bytes and incorrectly declares them to be sRGB. It is darker because
changing a tag was substituted for converting the samples.

The two valid routes should agree visually, allowing for rounding differences.
Conversion preserves the intended color; it is not a brightness effect.

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

@(tutorial-figure
   (string-append
    "Both ramps mark source sample 128. It remains 128 in the encoded ramp but converts "
    "to about 188 in the linear-light ramp, whose stored sRGB steps are unequal.")
   (ramp-pair-pict))

Each source is 256 by 1 pixel, stretched to a 560-by-42 strip with nearest
sampling. The coral tick marks source sample 128 in each ramp. Inspect the
output bytes at that position:

@colors-interaction[
(bytes->list (subbytes (image->rgba-bytes encoded-ramp) (* 4 128) (* 4 129)))
(bytes->list (subbytes (image->rgba-bytes converted-ramp) (* 4 128) (* 4 129)))
]

The second ramp has equal steps in its original
linear-light samples; converting those samples to sRGB produces unequal steps
in the encoded output.

The reverse conversion helps explain what the darker swatch means. Convert
the original sRGB sample of 128 into linear sRGB:

@colors-racketblock+eval[
(define linear-version (image-convert-color-space encoded-gray linear))
]
@colors-interaction[(bytes->list (image->rgba-bytes linear-version))]

The linear RGB bytes are approximately 55. As an eight-bit fraction, 55/255
is about 0.216, not one half. Conversely, starting with a linear sample near
one half required an encoded sRGB value near 188. The spaces agree about black
and white but encode intermediate light levels differently.

This is why averaging encoded channels, as in
@tutorial-link["pixels"], is not the same as averaging light. The space used for a computation
and the encoding used to store its result are separate choices. The eight-bit
linear example also loses precision through quantization; repeated conversions
are not guaranteed to recover every original byte.

@section{Do Not Guess an Untagged Source}

An untagged image does not say whether its numbers are sRGB, linear sRGB, or
something else. The conversion function refuses to guess:

@colors-racketblock+eval[
(define untagged (rgba-bytes->image 1 1 (bytes 128 128 128 255)))
]

An attempted conversion without a source declaration fails before producing
an image:

@colors-interaction[
(with-handlers ([exn:fail? (lambda (_exception) 'source-space-required)])
  (image-convert-color-space untagged srgb))
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

@(tutorial-figure
   (string-append
    "The finished color study pairs the two gray interpretations with their channel "
    "labels and gray ramps. A matching color-space profile describes the converted "
    "samples.")
   (color-study-pict))

The labels show the converted channel values. The finished program also writes the small
@filepath{converted-gray.png} and a @filepath{study-srgb.icc} profile.

@section[#:tag "try-it"]{Try It}

Change the @racket[(make-color-study)] call in @racket[save-color-study] to
@racket[(make-color-study 64)]. The swatches and their numerical labels will
both follow the new sample. Predict whether conversion from linear sRGB will
increase or decrease its encoded sRGB value, then inspect the readback.
Keep the source image unchanged and compare its bytes afterward.

Try a colored rather than neutral sample. Check that only RGB passes through
the transfer function; alpha has a different meaning. Work with opaque samples
first to avoid confusing color conversion with low-alpha quantization.

@section[#:tag "next-steps"]{Where to Go From Here}

The example stays within eight-bit SDR RGB. Other gamuts change more than the transfer curve.
It does not perform perceptual gamut mapping, HDR tone mapping, or display calibration.
The upstream @hyperlink["https://skia.org/docs/user/color/"]{Skia color-management overview}
provides background on tagged images and destination color spaces.

@tutorial-next["color-spaces"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["color-spaces"]

Run the example with @tt{racket color-study.rkt}:

@codeblock[(file->string program-source)]
