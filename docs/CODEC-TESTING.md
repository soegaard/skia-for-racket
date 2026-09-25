# Advanced codecs: validation and ABI notes

## Baseline and scope

This is a source patch for standalone `soegaard/skia-for-racket` **0.20.0**,
against commit `257517a5c9f561b075c2fff23dd3ccad3be39d9a` (the ICC-corrected
0.19 baseline). It does not replace the ICC implementation, change existing
image constructors, add a native binary or font, or integrate another project.

The patch adds an owned codec API, selected full-canvas animation frames,
orientation normalization, richer animation metadata, regression fixtures,
and a contact-sheet example. Animation encoding, streaming/incremental decode,
and a sequential playback cache remain outside this revision.

## Verification actually performed in the authoring environment

- Retrieved the baseline and relevant upstream source through GitHub at pinned
  commits. Complete small-file copies used for edits were checked against their
  Git blob hashes; other edits use exact fetched source contexts.
- Reviewed the new Racket forms, checked balanced delimiters/strings, checked
  test-suite structure, and counted 10 new pure plus 17 new native cases.
  These structural checks are not a Racket reader, expander, or compiler.
- Decoded the original GIF and lossless WebP fixtures independently with Pillow:
  all five GIF and three WebP composited frames matched the expected RGBA bytes.
  This validates the fixture expectations, not Skia's behavior.
- Compiled and ran `tools/check-codec-abi.c` with the host C compiler. The mirror
  reported `options=24 frame-info=44 pointer=8`. This verifies the mirrored
  host layouts, not a loaded Skia library or Racket's FFI layout.
- Checked the patch's unified-diff structure and application to a reconstruction
  containing its exact fetched contexts. This is **not** a full-checkout
  `git apply --check`; run that on the actual repository as shown below.

**Not run here:** Racket compilation/tests, the native symbol audits, the full
repository static checker, doctor, Unicode conformance, or Skia rendering.
No new native pass, native leak check, performance result, or cross-platform
claim is made. The host validation below is required before calling 0.20 green.

## Apply the patch

From the repository root, check the working tree before applying. The patch
expects the exact baseline above and creates new files; do not apply it twice.

```sh
git status --short
git rev-parse HEAD

PATCH="$HOME/Downloads/skia-for-racket-0.20.0-advanced-codecs-20260925.patch"
git apply --check "$PATCH" &&
git apply "$PATCH"
```

## Build, test, and render on the existing macOS setup

Run from the patched repository root. No native reinstall is required when
the pinned libraries are already installed. Both symbol audits must still run:
the three new bindings must exist in the installed Skia library.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

python3 tools/static-check.py &&
cc -std=c11 -Wall -Wextra -pedantic tools/check-codec-abi.c \
  -o /tmp/skia-codec-abi-check &&
/tmp/skia-codec-abi-check &&
bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&
"$RACO" make \
  main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt \
  tests/codec-native-test.rkt examples/advanced-codecs.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&
mkdir -p output &&
"$RACKET" examples/advanced-codecs.rkt output/advanced-codecs-0.20.png &&
python3 tools/update-source-sums.py
```

The existing `SOURCE-SHA256SUMS.txt` is deliberately not rewritten from an
incomplete checkout. The last command above regenerates it from your complete
patched repository; include that change when committing the stage.

Expected required symbols: **240 Skia, 27 HarfBuzz**, with zero missing.
Expected suites: **54 original pure + 6 lifetime + 10 codec pure + 132 original
native + 17 codec native = 219 cases**. These are test-case counts, not counts
of individual assertions. `run-tests.rkt --pure` runs 70 cases and explicitly
does not run native cases. Existing Unicode conformance can be rerun separately
with `RACKET="$RACKET" bash tools/run-unicode-conformance.sh`; its implementation
is unchanged by this patch.

## Visual review

The top row shows five GIF frames. A green pixel appears on frame 1 and is
removed by restore-previous before frame 2. Frame 2's blue pixel is cleared
by restore-background before frame 3. Frame 4 blends transparent subframe
pixels over the prior canvas rather than clearing them. Transparent pixels
reveal the checkerboard.

The second row shows three lossless WebP frames, requested in reverse order
but placed in forward order. The bottom two rows show all eight EXIF origins
applied to an asymmetric six-color raster. Origins 5 through 8 swap width and
height. Lettering is not used as a pixel-exact oracle and depends on the host's
font selection; the tests compare decoded pixels independently of fonts.

## ABI and lifetime

Three new lazy C bindings are required: `sk_codec_get_pixels`,
`sk_codec_get_frame_info_for_index`, and `sk_codec_get_repetition_count`.
`sk_codec_options_t` is 24 bytes on the supported 64-bit targets: zero-initialized
at offset 0, subset pointer at 8, frame index at 16, and prior frame at 20.
The subset pointer is always null in this API.

`sk_codec_frameinfo_t` is **44 bytes**, alignment 4: required frame at 0,
duration at 4, one-byte fully-received flag at 8, alpha type at 12, one-byte
has-alpha flag at 16, disposal enum at 20, blend enum at 24, and the inline
16-byte integer rectangle at 28. Omitting blend or treating the rectangle as
a pointer would corrupt the FFI boundary. The pure Racket suite checks offsets
as well as sizes. `tools/check-codec-abi.c` is an additional host-C mirror.

The codec owns a referenced SkData copy; caller bytes are never retained.
Decode buffers are ordinary Racket bytes used only by synchronous calls.
`fPriorFrame = -1` requests dependency reconstruction into fresh pixels.
A successful decode is copied into native raster image storage. No incremental
operation retains a pointer into Racket memory. Each `sk_codec_get_info` call
returns a referenced color-space pointer, released after copying metadata or
pixels. Public color-space queries acquire their own reference.

## Pinned primary sources

The SkiaSharp 3.119.1 `externals/skia` submodule points to
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:

- [C codec entry points and ownership](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_codec.cpp)
- [C option, frame-info, and enum definitions](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_types.h)
- [SkCodec dependency reconstruction, color conversion, and repeated decode contract](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/codec/SkCodec.h)

Fixtures are original tiny images embedded in `tests/codec-fixtures.rkt`.
GIF SHA-256: `a6a1431ee9ab10f5fc4ce3696a27c152116845512ff929c840b3ecf2aec25b1c`.
WebP SHA-256: `77555ab6956ff9a1ed3f014dd840f38a67feff23dab9ed5059f9202b26b4b083`.
