#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/color-space skia/image-info))

@title[#:tag "skia-color-management"]{Color Management}

@(declare-exporting skia)

Use an explicit color space when combining content from different color spaces
or preparing pixels for an output with a known color interpretation. For
example, pass a space from @racket[make-srgb-color-space] to
@racket[make-surface] through @racket[#:color-space] to create an sRGB drawing
target. A color-space label describes what channel values mean; assigning a
label is not itself a conversion of existing pixels.

A @deftech{color space} describes how color samples are interpreted. A color-space
resource is different from a @tech{color specification}: it supplies the
interpretation, not the channel values. The @racket[color-space?] predicate is
provided by @racketmodname[skia], not @racketmodname[skia/color]. The standard
constructors and queries are also provided by @racketmodname[skia].

A color-space value wraps a native Skia object. Racket can reclaim it when
the value becomes unreachable. Use @racket[skia-close!] to release it at a
specific time; see @secref["skia-resources"]. A color space obtained from an
image or surface remains usable after that image or surface is released.
Releasing a color-space value does not change images or surfaces that use it.

An omitted or @racket[#f] color-space argument does not mean sRGB. Its meaning
depends on the operation; for @racket[make-surface] and @racket[rgba-bytes->image],
it creates an untagged result rather than selecting a default profile.

@local-table-of-contents[#:style 'immediate-only]

@section{Standard Color Spaces}

@defproc[(color-space? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia color-space resource and @racket[#f] otherwise.
A closed color-space wrapper still satisfies this predicate but cannot be used
for native operations.
}

@defproc[(make-srgb-color-space) color-space?]{
Returns a new owned color-space reference describing sRGB, with its standard
RGB primaries and nonlinear @tech{transfer function}. The result has an independent
wrapper lifetime even when Skia shares the underlying native color space.
Creating the reference does not convert any image or surface samples.
}

@defproc[(make-linear-srgb-color-space) color-space?]{
Returns a new owned color-space reference with the same RGB primaries as sRGB
and a linear transfer function. Samples in this space represent relative
linear-light channel values rather than sRGB-encoded values. The result follows
the same ownership rules as @racket[make-srgb-color-space].

The two spaces can be used with the image and surface constructors:

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [linear (make-linear-srgb-color-space)]
            [encoded (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                        #:color-space srgb)]
            [light (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                      #:color-space linear)]
            [surface (make-surface 2 1 #:color-space srgb)])
  (define canvas (surface-canvas surface))
  (draw-image canvas encoded 0 0)
  (draw-image canvas light 1 0)
  (bytes->list (surface->rgba-bytes surface #:color-space srgb)))
]

Both source images contain the same channel bytes, but those bytes describe
different colors. The sRGB source produces RGB values of 128; the linear source
produces approximately 188 in the sRGB destination. Alpha remains 255. The
@racket[#:color-space] arguments to @racket[rgba-bytes->image] declare the input
bytes' meaning; drawing into the tagged destination performs the conversion.

@reference-figure["color-space-interpretation.png"
                  "The actual two-pixel sRGB destination enlarged with nearest-neighbor sampling. The left opaque gray sample, declared sRGB, is RGB 128; the right sample has the same source bytes declared linear sRGB and converts to approximately RGB 188."]

The swatches are captured from the destination surface. They are not manually selected gray
paint colors.

@bold{Conceptual diagram.} The constructor's color-space tag declares what the
same RGB bytes mean; it does not convert those samples. Drawing the tagged image
into the tagged sRGB destination performs conversion. Thus opaque bytes
@racket[(128 128 128)] produce destination 128 when declared sRGB and about 188
when declared linear sRGB. Alpha premultiplication and RGBA/BGRA byte order are
separate storage topics.

@reference-figure["concept-color-interpretation.png"
                  "The RGB channel values (128,128,128) branch to an sRGB declaration and a linear-sRGB declaration, then into the same sRGB destination. The two destination swatches are labeled 128 and approximately 188, showing interpretation followed by conversion."]
}

@defproc[(color-space=? [a color-space?] [b color-space?]) boolean?]{
Returns @racket[#t] when Skia considers @racket[a] and @racket[b] equivalent
color spaces, and @racket[#f] otherwise. This compares the color-space
descriptions, not Racket wrapper identity or image pixels. Both arguments must
be open resources used on their owning thread.
}

@defproc[(color-space-srgb? [space color-space?]) boolean?]{
Returns @racket[#t] when Skia recognizes @racket[space] as sRGB, and @racket[#f]
otherwise. The space must be open and used on its owning thread. Linear sRGB
does not satisfy this predicate merely because it has the same RGB primaries.
}

@defproc[(color-space-linear-gamma? [space color-space?]) boolean?]{
Returns @racket[#t] when @racket[space] has a linear transfer function, and
@racket[#f] otherwise. The space must be open and used on its owning thread.
The result does not identify the RGB primaries or verify the meaning of any
pixel samples.

@racketblock[
(with-skia ([srgb (make-srgb-color-space)]
            [another-srgb (make-srgb-color-space)]
            [linear (make-linear-srgb-color-space)])
  (list (color-space=? srgb another-srgb)
        (color-space=? srgb linear)
        (color-space-srgb? srgb)
        (color-space-srgb? linear)
        (color-space-linear-gamma? srgb)
        (color-space-linear-gamma? linear)))
]

The result is @racket['(#t #f #t #f #f #t)].
}


@section[#:tag "skia-color-gamma"]{Changing the Transfer Function}

These operations return or inspect color-space descriptions. They do not
convert pixel samples. Native resources must be open on their owning thread.
A returned color-space reference has its own lifetime; closing the source does
not close the result. Native allocation or unsupported descriptions raise an
exception rather than returning a partly initialized resource.

@defproc[(color-space-gamma-close-to-srgb? [space color-space?]) boolean?]{
Returns @racket[#t] when Skia considers the space's transfer function close
enough to sRGB for its sRGB approximation, and @racket[#f] otherwise. This is
not an equality test for the complete color space and says nothing about its
RGB primaries or the interpretation of actual image samples.
}

@defproc[(color-space->linear-gamma [space color-space?]) color-space?]{
Returns an owned color-space reference with the source's RGB gamut and a linear
transfer function. The source description is unchanged. Tagging existing
nonlinear samples with this result would reinterpret them, not linearize them;
use @racket[image-convert-color-space] when sample conversion is intended.
}

@defproc[(color-space->srgb-gamma [space color-space?]) color-space?]{
Returns an owned color-space reference with the source's RGB gamut and the
sRGB transfer function. The result need not be sRGB: a Display P3 gamut remains
Display P3 even when its transfer function is sRGB.
}

@section[#:tag "skia-transfer-functions"]{Transfer Functions}

@defmodule[skia/color-space #:no-declare]
@(declare-exporting skia skia/color-space #:use-sources (skia/color-space))

To construct an RGB color space with @racket[make-rgb-color-space], choose how
its channel values encode light as well as its RGB gamut. The transfer
functions below describe that encoding; gamuts are described in
@secref["skia-xyz-d50"].

A @deftech{transfer function} is an immutable Racket structure with seven
coefficients in order @tt{g, a, b, c, d, e, f}. Its nonnegative-domain formula is
@math{c x + f} when @math{x < d}, and @math{(a x + b)^g + e} otherwise. The forward
functions used to construct RGB color spaces decode encoded channels into
linear-light values. An inverse encodes in the other direction.

The coefficient representation supports these standard-dynamic-range formulas,
not arbitrary lookup tables, PQ, HLG, or tone mapping. Coefficients are rounded
to IEEE binary32 when stored. Native-backed operations in this section require
the installed Skia library.

@defproc[(transfer-function? [v any/c]) boolean?]{
Returns @racket[#t] for a transfer-function value and @racket[#f] otherwise.
A seven-element vector is not itself a transfer-function value.
}

@defproc[(make-transfer-function [g real?] [a real?] [b real?] [c real?]
                                 [d real?] [e real?] [f real?]) transfer-function?]{
Returns a transfer function with the seven supplied coefficients. After binary32
rounding, @racket[g] must be positive; @racket[a], @racket[c], and @racket[d] must
be nonnegative; and @math{a d + b} must be nonnegative. The constructor does not
require the two branches to meet continuously or make the function invertible.
Construction performs no native call and converts no color samples.

@racketblock[
(define transfer (make-transfer-function 2 1 0 0 0 0 0))
(transfer-function-evaluate transfer 0.5)
]

The result is 0.25. The coefficients describe a square-law decoding function.
}

@defproc[(transfer-function-coefficients [transfer transfer-function?])
         (and/c (vector/c real? real? real? real? real? real? real?) immutable?)]{
Returns the stored immutable vector in order @tt{g, a, b, c, d, e, f}. The vector
contains ordinary Racket numbers, not borrowed native storage. This query does
not load the native library.
}

@defproc[(named-transfer-function [name (or/c 'srgb 'linear 'gamma-2.2 'rec2020)])
         transfer-function?]{
Returns a transfer-function structure with the named native coefficients. The
names select sRGB, linear, a power of 2.2, or the standard-dynamic-range Rec. 2020
function, respectively. The result describes channel encoding, not an RGB gamut.
This operation requires native Skia. Rec. 2020 here does not select an HDR
transfer function.
}

@defproc[(transfer-function-evaluate [transfer transfer-function?]
                                    [x (real-in 0 3.402823e38)]) real?]{
Returns the transfer formula evaluated at @racket[x]. The argument is a
nonnegative finite real in the displayed range; it is not restricted to 0
through 1. This Racket computation uses the stored coefficients without first
rounding @racket[x] to binary32 and without clamping the result. A non-real or
nonfinite result raises an exception. Evaluation does not require native Skia.
}

@defproc[(transfer-function-invert [transfer transfer-function?])
         (or/c transfer-function? #f)]{
Returns a transfer-function structure for the native inverse, or @racket[#f]
when the native inversion reports failure. The inverse uses the same coefficient
representation and can introduce rounding error. This is not an independent
proof that a user-supplied discontinuous function is globally invertible.
Inversion requires native Skia; it does not modify the argument.
}

@section[#:tag "skia-xyz-d50"]{RGB Gamuts and XYZ-D50 Matrices}

@(declare-exporting skia skia/color-space #:use-sources (skia/color-space))

The gamut argument of @racket[make-rgb-color-space] selects the RGB primaries
and white point. Use a named gamut or supply a matrix computed from custom
primaries and a white point with @racket[primaries->xyz-d50].

An @deftech{XYZ-D50 matrix} is a row-major three-by-three matrix relating
linear RGB to CIE XYZ with the D50 reference white. It is represented by nine
numbers, not by an affine drawing matrix. A @deftech{chromaticity} describes a
primary or white point through its CIE x and y coordinates.

Matrix and chromaticity inputs may be lists or vectors. Input coefficients
are copied. Returned matrices are immutable vectors. These operations do not decode transfer
functions, alter alpha, or convert a complete image by themselves.

@defproc[(named-xyz-d50 [name (or/c 'srgb 'adobe-rgb 'display-p3 'rec2020 'xyz)])
         (and/c (vectorof real?) immutable?)]{
Returns the named native RGB-to-XYZ-D50 matrix as nine row-major coefficients.
The selected gamut does not choose a transfer function. This operation requires
native Skia.
}

@defproc[(primaries->xyz-d50
          [red (or/c (list/c real? real?) (vector/c real? real?))]
          [green (or/c (list/c real? real?) (vector/c real? real?))]
          [blue (or/c (list/c real? real?) (vector/c real? real?))]
          [white (or/c (list/c real? real?) (vector/c real? real?))])
         (and/c (vectorof real?) immutable?)]{
Returns a nine-coefficient matrix for the supplied RGB primary chromaticities
and source white, adapted to D50 by the native implementation. After rounding,
each pair must satisfy @math{0 <= x <= 1}, @math{0 < y <= 1}, and
@math{x + y <= 1.000001}. The small allowance on the sum accommodates numerical
rounding. Native rejection of unusable or degenerate primaries raises an
exception. Passing these elementary checks alone does not guarantee a usable gamut.
}

@defproc[(make-rgb-color-space
          [transfer (or/c transfer-function? 'srgb 'linear 'gamma-2.2 'rec2020)]
          [gamut (or/c 'srgb 'adobe-rgb 'display-p3 'rec2020 'xyz
                       (listof real?) (vectorof real?))]) color-space?]{
Returns an owned RGB color-space resource with the supplied transfer function
and gamut. Named arguments select the corresponding native descriptions. A
matrix argument must contain exactly nine row-major coefficients and have a
nonzero determinant after binary32 rounding. Native rejection raises an
exception. The input coefficients are copied; later mutation of an input vector
has no effect on the color space.

@racketblock[
(with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)]
            [linear-p3 (color-space->linear-gamma p3)])
  (list (color-space-srgb? p3)
        (color-space-gamma-close-to-srgb? p3)
        (color-space-linear-gamma? linear-p3)))
]

The result is @racket['(#f #t #t)]. Sharing the sRGB transfer function does
not make the Display P3 primaries sRGB primaries.
}

@defproc[(color-space-transfer-function [space color-space?])
         (or/c transfer-function? #f)]{
Returns a numerical transfer description for an open color space, or
@racket[#f] when no such description is available. An invalid or closed resource
raises an exception; it is not reported as an unavailable numerical description.
}

@defproc[(color-space-xyz-d50 [space color-space?])
         (or/c #f (and/c (vectorof real?) immutable?))]{
Returns nine row-major coefficients for an open space's XYZ-D50 matrix, or
@racket[#f] when the native query cannot supply one. The result is not a complete
color conversion without the corresponding transfer function.
}

@defproc[(xyz-d50-concat [a (or/c (listof real?) (vectorof real?))]
                        [b (or/c (listof real?) (vectorof real?))])
         (and/c (vectorof real?) immutable?)]{
Returns the matrix product @math{a b} as nine row-major binary32 coefficients.
Each input must contain nine coefficients. With column color vectors,
@racket[b] acts first. Singular inputs are permitted for multiplication, unlike
the gamut required by @racket[make-rgb-color-space]. The inputs are copied and
not mutated. A nonfinite native result raises an exception. Native Skia is
required.
}

@defproc[(xyz-d50-invert [matrix (or/c (listof real?) (vectorof real?))])
         (or/c #f (and/c (vectorof real?) immutable?))]{
Returns the native inverse as nine row-major coefficients, or @racket[#f]
when inversion fails or produces nonfinite coefficients. The argument must
contain nine coefficients; singular input is accepted and yields no inverse.
The input is not modified. A returned inverse can amplify rounding error for
an ill-conditioned matrix.
}

@section[#:tag "skia-icc-profiles"]{ICC Profiles}

@(declare-exporting skia)

Use ICC profiles to exchange color-space descriptions with image files or
other software. Import profile bytes with @racket[color-space-from-icc-bytes]
when interpreting externally supplied colors, or export a supported space
with @racket[color-space->icc-bytes] when another consumer needs its profile.

An @deftech{ICC profile} is an external color-space description stored as bytes. Import,
export, and encoder overrides have different restrictions. Neither an ICC
profile nor a native color space verifies that a particular set of samples was
actually encoded in the described space.

@defproc[(color-space-from-icc-bytes [profile bytes?]) color-space?]{
Returns an owned color-space resource parsed from nonempty ICC bytes. The
input length must fit @racket[current-skia-byte-limit]. Native parsing or an
unsupported native color-space representation raises an exception. The input
byte string is copied; later changes to it do not affect the color space.
Input may be mutable or immutable.

Successful import does not guarantee that the original bytes are accepted as
an encoder's @racket[#:icc-profile] override. Those overrides impose the
additional matrix/TRC restrictions documented by @racket[save-png].
}

@defproc[(color-space->icc-bytes [space color-space?]) bytes?]{
Exports the color space as an ICC profile.

The result is a new mutable byte string. It contains an ICC v4 RGB monitor
profile constructed from the space's numerical transfer function and XYZ-D50 matrix.
This is not the original imported profile: descriptions, other metadata, tag
layout, and original bytes are not preserved. The native space must be open.
Missing numerical descriptions, coefficients outside the ICC signed 15.16
fixed-point range, or output exceeding @racket[current-skia-byte-limit] raise
an exception.

The exported coefficients are quantized to ICC fixed-point representation.
Importing the result need not give bit-identical coefficients or satisfy an
exact native equality test with the original space. Export does not convert
samples or write a file.

@racketblock[
(with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)])
  (define profile (color-space->icc-bytes p3))
  (with-skia ([restored (color-space-from-icc-bytes profile)])
    (list (bytes? profile) (immutable? profile) (color-space? restored))))
]

The result is @racket['(#t #f #t)]. The two resources have independent lifetimes.
}

@section[#:tag "skia-color-space-descriptors"]{Color-Space Descriptors}

@defmodule[skia/image-info #:no-declare]
@(declare-exporting skia skia/image-info #:use-sources (skia/image-info))

Use a color-space descriptor to express color-space settings as a symbol or
ICC profile bytes. For example, @racket[make-image-info] accepts this form
through @racket[#:color-space], instead of a live color-space resource.

A @deftech{color-space descriptor} is @racket[#f], @racket['srgb],
@racket['linear-srgb], or complete immutable ICC bytes with the required header.
APIs that require an explicit source interpretation reject @racket[#f]. Some
such APIs also accept mutable ICC bytes by copying them; their argument
contracts therefore differ from this representation predicate.

@defproc[(color-space-descriptor? [v any/c]) boolean?]{
Returns @racket[#t] for @racket[#f], the two named descriptors, or an immutable
byte string of at least 128 bytes with @tt{acsp} at byte offsets 36 through 39
and a big-endian declared size equal to the complete byte length. Returns
@racket[#f] otherwise, including for mutable ICC bytes and live color-space
resources. The header check does not parse tag contents, load native Skia, or
check @racket[current-skia-byte-limit]. A recognized description can still be
rejected when used to construct a native space.

Use @racket[bytes->immutable-bytes] on an exported profile when an immutable
descriptor value is needed. The function @racket[color-space->icc-bytes]
returns mutable bytes, even though it can describe a valid color space.
}

@section[#:tag "skia-sample-conversion"]{Converting Image Samples}

@(declare-exporting skia)

@defproc[(image-convert-color-space [image image?] [destination color-space?]
                                   [#:source-color-space source (or/c color-space? #f) #f])
         image?]{
Converts the image's colors to @racket[destination] and returns a new image.

The result is an owned resource stored in CPU memory.
A tagged input supplies its own source interpretation and rejects a nonfalse
@racket[source]. An untagged input requires an explicit open source color space;
the operation does not guess sRGB. The destination must also be open.

This operation uses an intermediate buffer of eight-bit RGBA pixels with
unpremultiplied alpha. It preserves pixel dimensions, not the original pixel
format or precision. Floating-point images are rejected rather than silently
reduced to eight bits. Conversion can
clip or quantize colors, and does not promise a lossless round trip. A
GPU-dependent input is rejected; this operation does not perform implicit GPU
readback. The input image is unchanged, and the result remains usable after the
input and the caller's color-space wrappers close.

@racketblock[
(with-skia ([linear (make-linear-srgb-color-space)]
            [srgb (make-srgb-color-space)]
            [source (rgba-bytes->image 1 1 (bytes 128 128 128 255))]
            [converted (image-convert-color-space source srgb #:source-color-space linear)])
  (list (bytes->list (image->rgba-bytes source))
        (bytes->list (image->rgba-bytes converted))))
]

The source bytes stay @racket['(128 128 128 255)]; the converted RGB bytes are
approximately 188, with alpha still 255. Declaring an encoding when constructing
an image, converting its samples, and overriding an encoder's profile are three
different operations.

@reference-figure["image-color-space-conversion.png"
                  "Two actual one-pixel images enlarged with nearest-neighbor sampling. The left untagged source bytes are previewed under an explicitly stated sRGB assumption and appear RGB 128; the right converted sRGB image is approximately RGB 188. Both are opaque."]

The source's bytes are not changed for this preview. Only @racket[image-convert-color-space]
creates the brighter converted sample.
}
