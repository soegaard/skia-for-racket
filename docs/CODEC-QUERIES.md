# Codec size and subset negotiation — 0.76a

Stage `0.76a` uses numeric package version `0.76`. It adds **queries**, not new
decoding modes. SkiaSharp remains pinned to 3.119.1 / m119; the minimum Racket
version remains 8.18. No compiled helper, GPU, or document renderer is needed.

```racket
(require skia) ; or the codec-queries.rkt module alongside the existing constructors
(codec-scaled-dimensions codec scale)       ; two exact positive integer values
(codec-supported-subset codec x y w h)      ; #f or immutable #(x y w h)
```

## Scaled dimensions

`codec-scaled-dimensions` delegates to `sk_codec_get_scaled_dimensions`. Its return
values are the native decoder's suggested width and height for the requested
scale. They are not necessarily the mathematical product of scale and source
size. A codec without native downscaling may return the original size. A scale
of one or greater returns the original size; this API does not upscale.

The scale must be a positive finite real representable as a **nonzero C float**.
The wrapper rounds to the actual float representation before checking positivity,
so very small positive Racket numbers cannot silently become an invalid zero
native scale. Zero, negative, nonfinite, nonreal, and overflowing scales raise
an argument exception.

```racket
(with-skia ([codec (codec-from-bytes jpeg-bytes)])
  (define-values (width height) (codec-scaled-dimensions codec 1/2))
  (printf "Native suggestion: ~a by ~a\n" width height))
```

For the controlled 16-by-12 JPEG fixture, half-size is 8-by-6, quarter-size is
4-by-3, and eighth-size is 2-by-2. The last case demonstrates native rounding,
not fractional output rows. PNG's ordinary m119 codec returns 16-by-12 for the
same half-size query.

These dimensions are **encoded-pixel dimensions before EXIF orientation**.
For a JPEG with orientation 6, an encoded 16-by-12 half-size suggestion remains
8-by-6; it is not automatically swapped to 6-by-8. This does not change the
existing origin normalization performed by `codec->image`.

## Supported subsets

`codec-supported-subset` takes exact integer `x`, `y`, `width`, and `height` in
original encoded-pixel coordinates. The origin must be nonnegative, the extents
positive, the endpoints signed-32-bit representable, and the rectangle wholly
inside the original image bounds. Width and height are extents, not right/bottom
coordinates. Internally, the native call receives exclusive right/bottom bounds.

The result is either:

* `#f`: native subset decoding is unsupported for this request/codec;
* an immutable `#(x y width height)`: the **actual native suggestion**, which may
  differ from the request.

An invalid request raises even for a format without subset support. `#f` is not
an argument-validation error, and it is never replaced by a full decode/crop.
The native rectangle is read only when the C call succeeds: on failure its
contents are undefined by the upstream contract.

For m119 WebP, odd left/top coordinates are rounded down to even coordinates,
leaving the exclusive right/bottom coordinates unchanged. For example:

```racket
(codec-supported-subset webp-codec 1 3 6 5)
; => '#(0 2 7 6)
```

An even-origin request such as `(2 4 6 4)` stays unchanged. PNG and JPEG return
`#f` for these valid subset requests in the pinned codec implementation. Do not
generalize WebP's adjustment rule to other future decoders: consume the returned
rectangle rather than assuming the requested one was accepted unchanged.

## Ownership, state, and resource limits

Both calls require a live codec on its owning Racket thread. They use the existing
atomic native-handle borrow, make only synchronous native metadata queries, and
retain no output pointer. Invalid native results are rejected, rather than exposed
as usable dimensions/rectangles. Returned integers and vectors are detached and
remain valid after codec closure.

The queries do not change the codec's selected region, origin, or decode options.
Existing full-image/animation decode APIs remain unchanged. Stream-backed codecs
retain their established private-duplicate ownership; these queries do not advance
the original caller's stream. Native file consumers still require a stable file.

A size query is not a pixel allocation. The wrapper does not charge `width *
height * bytes-per-pixel` against `current-skia-byte-limit` just to report metadata.
Actual decoding/allocation still obeys the existing resource limits. A negotiated
size and subset do not establish that every combination of scale, frame, subset,
color type, and decode mode is supported.

## What is deferred

0.76a does **not** expose scaled/subset pixel decoding, scanline sessions,
progressive/incremental sessions, retained destination storage, or new live-port
codec lifetimes. It does not silently simulate any of them by complete decoding,
resampling, or cropping. Scanline work is stage **0.76b**; incremental work is
**0.76c**. They will consume negotiated options subject to each native mode's own
restrictions. Existing one-shot and animation behavior is preserved.

## Validation

```bash
python tools/validate-codec-queries.py --racket /path/to/racket
python tools/validate-codec-queries.py --racket /path/to/racket --regressions none
```

Full regressions are the standalone default. Feature-only mode always compiles
and runs the focused 31 pure and 26 native cases, the public-API example, and the
native query doctor. Omitted global regressions are reported as not run, not as
passed. Pillow, already listed in `tools/dc-output-requirements.txt`, independently
opens encoded PNG/JPEG/WebP fixtures and checks their dimensions and lossless
pixels. Native full-decode captures before and after queries must agree.

Tests cover native scale rounding, unsupported and adjusted subsets, the EXIF
coordinate distinction, invalid inputs, read-only query behavior, stream lifetime,
closed/cross-thread rejection, and detached results. Independent evidence includes
all three format rows, five scales, exact/adjusted subsets, nine encoded/pixel
files, and the oriented-JPEG result. Synthetic Python fixtures and mock command
plans test the validator; they are not native execution evidence.

The reusable `codec-queries.yml` child runs Linux 8.18/9.3 and Windows 9.3 under
Acceptance, inheriting the umbrella regression mode. Central CI's installed-package
regressions include both new suites on the existing platforms, including macOS.
No additional automatically triggered top-level workflow is introduced.

## Reviewed upstream sources

* `include/c/sk_codec.h` and `src/c/sk_codec.cpp`, mono/skia commit
  `40f75dc0051d141913c07c20d4c19590c7da0cb7`: C call signatures and direct delegation.
* [SkCodec.h at the pinned revision](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/codec/SkCodec.h): positive scales, no upscaling, encoded bounds and undefined subset output on false.
* [SkWebpCodec.cpp at the pinned revision](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/codec/SkWebpCodec.cpp): even-origin subset negotiation.
