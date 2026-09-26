# Color-managed output

Color values have two independent parts: numerical samples and the color space
that gives those samples meaning. An ICC profile describes that meaning. Merely
writing a different profile does not change samples into the new space.

The library provides three operations for these distinct jobs:

* `rgba-bytes->image` with `#:color-space` declares the meaning of supplied samples.
* `image-convert-color-space` converts an image's samples to a destination space.
* An encoder's `#:icc-profile` overrides the profile written into the output file,
  without converting samples. Its `#:color-space` option converts samples first.

The current implementation is CPU, eight-bit RGBA and SDR. It is not an HDR
pipeline, display calibration system, proofing system, or perceptual gamut mapper.

## Convert first, then encode

```racket
#lang racket/base
(require "main.rkt") ; use (require skia) when installed

(with-skia ([linear (make-linear-srgb-color-space)]
            [srgb (make-srgb-color-space)]
            [source (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                      #:color-space linear)]
            [converted (image-convert-color-space source srgb)])
  ;; Approximately (188 188 188 255), rather than (128 128 128 255).
  (displayln (bytes->list (image->rgba-bytes converted)))
  (save-image converted "converted.png" 'png
              #:icc-profile (color-space->icc-bytes srgb)
              #:icc-description "Converted sRGB"
              #:exists 'replace))
```

A shorter encoding call can perform the same conversion:

```racket
(image->png-bytes source
                  #:color-space srgb
                  #:icc-profile (color-space->icc-bytes srgb)
                  #:icc-description "Converted sRGB")
```

All encoder defaults remain compatible with earlier calls. Omitting
`#:color-space` does not request a conversion. Omitting `#:icc-profile`, or
passing `#f`, retains the native encoder's automatic profile behavior; it does
**not** request that all color metadata be removed. Skia already generates
profiles for supported tagged source spaces, and can use PNG's sRGB chunk for
sRGB. The explicit override makes the requested matrix/TRC profile and its
description available through all three encoder interfaces.

### Untagged input

An untagged image does not tell the converter what its values mean. Supply a
source declaration explicitly:

```racket
(image-convert-color-space untagged-image srgb
                           #:source-color-space linear)
```

Without that declaration, conversion raises. A source declaration is rejected
for an already-tagged image; it cannot accidentally replace an existing tag.
The ordinary `rgba-bytes->image` declaration remains available for intentional
reinterpretation of raw samples.

Conversion returns an independent owned raster image tagged with the destination
space. The source and its tag are unchanged; the result can outlive both input
wrappers. Alpha is not subjected to the RGB transfer function. Straight RGBA
readback and eight-bit quantization can lose information, particularly near
transparent pixels and outside the destination gamut. Out-of-range colors are
clamped; there is no perceptual gamut mapping or tone mapping. Conversion also
drops any reusable original compressed-image representation.

## Custom RGB spaces

Import these functions from `skia` or `skia/color-space`.

```racket
(make-rgb-color-space transfer gamut)
(named-transfer-function name)
(named-xyz-d50 name)
(primaries->xyz-d50 red green blue white)
(color-space-transfer-function color-space)
(color-space-xyz-d50 color-space)
```

`transfer` accepts a `transfer-function?` value or one of `'srgb`, `'linear`,
`'gamma-2.2`, and `'rec2020`. These named values describe encoded-to-linear
SDR transfer functions. The Rec. 2020 choice does not select PQ, HLG, or HDR.

`gamut` accepts a list/vector of nine row-major RGB-to-XYZ(D50) coefficients or
one of `'srgb`, `'adobe-rgb`, `'display-p3`, `'rec2020`, and `'xyz`. The latter
is the identity XYZ matrix; it is not the white-point adaptation of an arbitrary
RGB system. A color gamut matrix is unrelated to the six-coefficient geometry
`matrix?` type. It must be invertible after conversion to native floats.

For example:

```racket
(with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)]
            [adobe (make-rgb-color-space 'gamma-2.2 'adobe-rgb)]
            [custom (make-rgb-color-space
                     (make-transfer-function 2 1 0 0 0 0 0)
                     (primaries->xyz-d50 '(0.64 0.33) '(0.30 0.60)
                                         '(0.15 0.06) '(0.3127 0.3290)))])
  (displayln (color-space-xyz-d50 custom)))
```

Each primary and white point is an `(x y)` list/vector in chromaticity
coordinates. The native conversion adapts the result to D50. Custom matrices
are already expected to be adapted to D50; passing a D65 matrix does not request
adaptation. Degenerate primaries raise rather than producing a usable space.

Inspection returns detached immutable values that remain usable after the
native color space is closed. `color-space-transfer-function` returns `#f` when
Skia cannot provide a numerical SDR transfer function; `color-space-xyz-d50`
returns `#f` when the matrix is unavailable. Named queries and native inspection
load/use Skia. Constructing and evaluating a transfer value itself does not.

## Transfer values

```racket
(transfer-function? value)
(make-transfer-function g a b c d e f)
(transfer-function-coefficients transfer)
(transfer-function-evaluate transfer x)
(transfer-function-invert transfer)
```

Coefficients have the native skcms order `g a b c d e f`, which is also ICC
parametric-curve function 4 order:

```text
y = (a*x + b)^g + e   when x >= d
    c*x + f          when x < d
```

Coefficients are rounded to IEEE binary32 and stored in an immutable vector.
The constructor rejects nonfinite coefficients, nonpositive gamma, negative
`a`, `c`, or `d`, and a negative power-branch base at the breakpoint. It does
not certify continuity, normalization, or invertibility of every custom curve.

Evaluation accepts a finite, nonnegative input and uses the rounded coefficients
in Racket arithmetic. It does not clamp the result to `[0,1]`, and rejects a
nonfinite result. It is not a bit-for-bit replacement for all native SIMD color
operations. Negative inputs and the special HDR transfer encodings are outside
this value API. Inversion uses Skia and returns a detached transfer value or
`#f` when inversion fails.

## Encoder options and profile lifetime

The following existing functions accept three additional keyword arguments:

```racket
#:color-space     [destination #f]
#:icc-profile     [profile-bytes #f]
#:icc-description [description #f]
```

They are `image->png-bytes`, `image->jpeg-bytes`, `image->webp-bytes`,
`image->encoded-bytes`, `save-image`, `surface->png-bytes`, and `save-png`.
Compression, quality, alpha handling and other existing options are unchanged.

An explicit profile must be an SDR RGB matrix/TRC ICC profile with XYZ PCS.
The wrapper checks the declared length, signature, tag table, matrix/curve
entries, and byte limit before passing it to Skia. LUT and CICP/HDR overrides
are rejected. These are intentional encoder restrictions: arbitrary profiles
accepted by the existing color-space importer are not necessarily supported
by the pinned native profile writer. `color-space-from-icc-bytes` is unchanged.

`#:icc-description` requires an explicit profile and accepts 1–4096 printable
ASCII characters. Omit it to use `skia-for-racket RGB`. The native writer's
`char*` description API is not treated as an arbitrary Unicode interface.

The encoder regenerates an ICC profile from the parsed matrix/curves. The
embedded profile can have a different header, tag order, description, and
binary representation from the supplied bytes. It is a semantic profile
transfer, not lossless archival copying of arbitrary ICC tags. Tests compare
matrix/transfer behavior rather than profile byte equality.

The explicit ICC override does not itself modify image samples. When both
`#:color-space` and `#:icc-profile` are supplied, the caller must choose a
profile describing that destination. A deliberately mismatched override is
possible; it is not silently corrected by the library.

The source profile is copied into native SkData because skcms can retain pointers
into it while reading curves. Its native data, parsed profile, and NUL-terminated
description remain alive until the synchronous encode finishes. They are released
on normal return or any scoped exit. No profile pointers escape.

The byte limit covers input/profile buffers, requested pixel conversion buffers,
and copied output; it is not a total bound on codec/encoder internal allocations.
File helpers retain the existing encode-before-opening guarantee: an encoding
failure does not truncate the destination. They are not transactional against
filesystem write failures.

## PDF, SVG, and portable document colors

The pinned m119 PDF bitmap serializer contains a TODO for converting images to
sRGB or tagging them. Do not treat an arbitrary ICC-tagged input image as a
promise of color-correct PDF output. Its existing compressed JPEG reuse is an
additional reason to normalize pixels before document embedding.

For a portable document, explicitly convert source images to sRGB and draw the
result on both PDF and SVG canvases. The probe uses that approach; matching
thumbnail appearance is not evidence that PDF preserved a wide-gamut source
profile. SVG can embed PNG profiles, but the viewer and display pipeline still
determine color-managed appearance. The SVG backend does not expose a whole-
document arbitrary ICC output intent.

### Skia PDF/A mode

```racket
(make-pdf-document ... #:pdfa? #f)
(call-with-pdf-bytes draw-document ... #:pdfa? #f)
(call-with-pdf-file path draw-document ... #:pdfa? #f)
(output->bytes page-or-pages 'pdf ... #:pdfa? #f)
(save-output page-or-pages path 'pdf ... #:pdfa? #f)
```

Setting the boolean to `#t` forwards Skia's `fPDFA` option. It adds XMP metadata,
a document UUID and a fixed sRGB output intent, which upstream describes as
necessary features for PDF/A-2b. It does **not** certify a particular document's
PDF/A conformance, validate fonts, convert arbitrary embedded-image samples,
add a CMYK output intent, or provide a user-selected output profile. Use an
independent conformance validator for an archival requirement.

The UUID makes PDF/A-mode output non-reproducible byte for byte. Default `#f`
preserves the prior metadata behavior. A true PDF/A request on shared SVG
export raises before executing the drawing callback.

## Probe and primary implementation sources

`examples/color-output.rkt` is the single registry for three PDF/SVG/raster pages,
six tagged encoded files, two source ICC profiles, and a native-value trace.
See [the validation instructions](COLOR-OUTPUT-TESTING.md).

The native behavior above is based on the pinned Skia revision
`40f75dc0051d141913c07c20d4c19590c7da0cb7`, not on later Skia interfaces:

- [RGB constructors and queries](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_colorspace.cpp)
- [PNG profile override](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/encode/SkPngEncoder.h)
- [Native profile writer](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/encode/SkICC.cpp)
- [PDF/A metadata option](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/docs/SkPDFDocument.h)
- [PDF bitmap serializer and color-space TODO](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/pdf/SkPDFBitmap.cpp)
