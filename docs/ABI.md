# Native ABI and ownership notes

## Version boundary

The reference is the `v3.119.1` tag of SkiaSharp, especially the generated
`SkiaApi.generated.cs` declarations containing the C prototypes, enum values,
and struct layouts. The explicit installer pins that version rather than
following the latest package. It is not presented as the current Skia release.
See [SOURCES.md](SOURCES.md).

`sk_version_get_milestone` is the first callout. Milestones other than 119 are
rejected before any versioned struct reaches C. All required symbols are
resolved before the first allocation, so a destructor does not need a new
library lookup from a finalizer. Matching milestone and symbols is necessary,
not sufficient, for compatibility with custom builds. Use the pinned binary.
The C++ API and historical Google experimental C API are not used directly.

## Structs used

Natural alignment is used; no packed structs. C enums are represented by C
`int`, `size_t` by `_size`, channel colors by `_uint32`, and C/C++ `bool` by
Racket `_stdbool` (one byte), not an int-sized `_bool`.

| Struct | Field order | Typical 64-bit size |
|---|---|---:|
| Image info | color-space pointer, int32 width, int32 height, int color type, int alpha type | 24 |
| Rectangle | float left, top, right, bottom | 16 |
| Sampling options | int max-anisotropy, bool use-cubic, padding, float B, float C, int filter, int mipmap | 24 |
| PNG options | int filter flags, int compression, comments pointer, ICC-profile pointer, ICC-description pointer | 32 |
| Font metrics | uint32 flags, then 15 floats from top through strikeout position | 64 |

All three PNG pointer fields are initialized to NULL. An older two-field PNG
options declaration would be unsafe with this API; the native encoder reads
the later fields. Sampling fields are initialized even when cubic filtering
and mipmaps are disabled. Surface creation explicitly selects RGBA8888 rather
than relying on platform-dependent native color ordering.

The font-metrics flags are copied as a 32-bit mask. The four decoration fields
(underline thickness/position and strikeout thickness/position) are exposed to
Racket only when their corresponding native validity bit is set. UTF-8 simple
text uses the pinned native text-encoding value 0.

The 0.1 layout declarations were live-tested on macOS/aarch64 with Racket
9.3.0.2. The new 0.2 `SKFontMetrics` declaration is covered by source tests and
a host-C mirror, but still requires the included Racket tests on a machine with
the pinned native library. A host-C layout check is not a substitute for
validating Racket's actual FFI declaration.

## Ownership map

| Resource | Release function | Rule |
|---|---|---|
| Surface | `sk_surface_unref` | One owned reference |
| Canvas from a surface | None | Borrowed; surface wrapper retained |
| Paint | `sk_paint_delete` | Native-owned object |
| Path | `sk_path_delete` | Native-owned object |
| Image/snapshot | `sk_image_unref` | One owned reference |
| Typeface | `sk_typeface_unref` | One owned reference |
| Font | `sk_font_delete` | Native-owned object; may retain a private default typeface wrapper |
| Temporary font style | `sk_fontstyle_delete` | Owned only during family matching |
| Temporary native string | `sk_string_destructor` | Owned while copying a family name to Racket |
| Temporary pixmap | `sk_pixmap_destructor` | Wrapper owns descriptor; surface owns pixels |
| Temporary stream | `sk_dynamicmemorywstream_destroy` | Owned during encoding |
| Detached encoded data | `sk_data_unref` | Owned until bytes copied |

Each owned handle contains a mutable pointer, a release operation, the creating
Racket thread, and a kind label. Explicit release invalidates the pointer first
and cancels allocator-tracked finalization. Aliases share that lifetime cell.
The `ffi/unsafe/alloc` allocator/deallocator machinery provides fallback cleanup.

`call-with-owned` validates thread/closed state and keeps handles live through
synchronous native calls using `call-as-atomic` and `void/reference-sink`.
The design deliberately does not mark drawing callouts `#:blocking? #t` and
does not release the Racket scheduler for concurrent native drawing. Do not
share native resources across Racket threads. These lifetime choices need live
stress testing on both Racket CS and target operating systems.

Public constructors never give Skia retained pointers into movable Racket pixel
storage. Surfaces allocate native pixels. RGBA image input uses the native copy
constructor. Pixel readback and encoded output are copied into normal Racket
byte strings. `make-sized-byte-string` is not used because it is not supported
by Racket CS. The bridge to `bitmap%` also copies.

Typeface family names are copied out of temporary native `sk_string_t` objects
before those strings are destroyed. Text is encoded into temporary Racket UTF-8
bytes and consumed synchronously. Glyph arrays are allocated only for the
native call and copied into Racket vectors. Font metrics are copied field by
field into an immutable Racket structure. Neither text nor metric APIs retain a
pointer into Racket-managed memory.

A font made without an explicit typeface owns a private default typeface wrapper
at the Racket level and closes it after closing the font. A font made from an
explicit caller-owned typeface never closes that wrapper. The pinned native
`SkFont` retains the typeface state it needs; a regression case checks that the
caller may close its typeface wrapper after successful font construction.

## Deliberate exclusions

No native-to-Racket callbacks, custom streams invoking Racket callbacks,
retained client pixel buffers, GPU contexts, arbitrary user native pointers,
C++ exceptions, font-manager/fallback abstraction, shaping engine, bidi
reordering, or paragraph layout enter this binding. Version 0.2 exposes only
the low-level typeface/font/simple-text/glyph layer.
Normal C library failures are converted to Racket exceptions where the ABI
provides failure results; a native crash/abort cannot be caught as an ordinary
Racket exception by this wrapper.

## Revalidation when changing the pin

Compare every used C prototype, enum, struct layout, and ownership rule against
the new version. Update the package URLs and accepted milestone together.
Run pure tests, doctor, native tests, and visual examples on each supported
architecture. Review alpha conversion, PNG option fields, sampling padding,
font-metrics layout and validity flags, UTF-8/glyph conversion, typeface/font
lifetime, image snapshot lifetime, and both explicit and GC cleanup. Do not simply widen
the milestone check until an incompatible build loads.
