# Native ABI and ownership notes

## Persistent-picture streams and retained shaders

Ten additional existing C callouts bring the total to **377 Skia / 27 HarfBuzz**.
They cover cull/ID/counter getters, serialize-to-data, deserialize-from-data,
picture shader creation, and R-tree factory begin/new/delete. No new cstruct is
introduced. Matrices and rectangle arguments use the existing m119 ABI.

The native SKP stream starts with `skiapict`, a native-endian uint32 version,
four float cull coordinates, and a payload-kind byte. The pinned format writer
uses **103**, not the Skia milestone 119; its reader accepts versions 82–103.
Wrapper header checks reject malformed framing and custom payload kinds, not
malicious or invalid command streams. Default `SkDeserialProcs::fAllowSkSL` is
true in the pinned source, and the C shim exposes no override. Loading therefore
requires explicit trust and must not be advertised as sandboxed.

`sk_picture_deserialize_from_data` receives a temporary native SKData copy;
the decoded picture owns its reconstructed resources. Picture shaders retain
native references. The R-tree factory is called synchronously; the recorder
owns its resulting hierarchy. Skia can tighten a tree-backed picture's cull
bounds. SKP reload reconstructs an ordinary recording, not its previous R-tree.

The auditor never restores trusted Racket provenance from serialized bytes.
All loaded pictures remain opaque/unknown, even inside explicit raster groups.

## General canvas matrices

The public 3x3/4x4 vectors are **row-major**; pinned canvas set/concat/get calls
use the existing **column-major SkM44** record, 16 floats / 64 bytes. The bridge
packs each coefficient at `column*4 + row`, and reverses that conversion on
readback. Translation X/Y/Z is at byte offsets 48/52/56; W's row is at offsets
12/28/44/60. No new native symbols or layouts are introduced: 367 Skia / 27
HarfBuzz remain required. The eighth host-C mirror independently checks offsets;
the native doctor also verifies readback against existing translation callouts.

Values contain only copied numbers. All matrix buffers are scoped to synchronous
FFI calls; canvas validation uses the existing owner, thread, and borrowed-lifetime
bridge. General matrix scopes reuse protected save-stack floors. Exact arithmetic
checks composition range first; a non-finite native result is restored to the
previous full matrix before raising. Full readback does not silently truncate
to affine/3x3. See [PROJECTIVE-MATRICES.md](PROJECTIVE-MATRICES.md) for the exact
embedding, explicit plane projection, rounding, and conservative output policy.

## Structured geometry

Thirty-one additional callouts bring the requirement to 367 Skia / 27 HarfBuzz.
SkRegion and SkVertices are owned resources. Input/iterator buffers never escape
synchronous FFI scopes; mesh construction and picture recording retain copies.
The SkLattice record is 48 bytes on 64-bit hosts (bounds/colors offsets 32/40);
RSXform is four floats, 16 bytes. The C shim reinterprets lattice records, so its
cell-type array must use the C++ uint8 element stride, not the C enum size.
See GEOMETRY-PRIMITIVES.md and tools/check-geometry-abi.c. The native doctor
tests cell kinds at several offsets independently of record-size checks.


## Canvas primitives and layers

Seventeen added C callouts bring the requirement to **336 Skia / 27 HarfBuzz**.
No new C struct layouts are introduced. Point arrays use two native 32-bit
floats per point; rounded corners use four such pairs. Rect/IRect layouts are
unchanged. All arrays are copied into scoped buffers, and opaque SkRRect values
are allocated/configured/released synchronously around each operation.

Rounded clips rebuild native-normalized RRect path verbs into an ordinary path
before clipping. This deliberately drops the special RRect tag so the pinned
SVG clip writer cannot replace unequal corners with a single rx/ry pair.
Temporary paths use the existing owned path and raw-iteration machinery.

Native layer save returns the pre-save count. Its restore paint is copied by
Skia and retains attached native resources; the Racket wrapper never retains
borrowed paint pointers. Scoped layers protect the same owner save-stack floors
as ordinary canvas-state scopes. Recorder finalization is rejected while a
protected scope is active. No native callbacks into user Racket code are added.

Layer bounds are passed through, not used as a wrapper-enforced byte budget.
In this pinned m119, `get_layer_mapping_and_bounds` intersects unfiltered layer
extent with supplied bounds, despite generic API wording describing a hint.
The public contract therefore requires conservative content bounds and does
not promise preservation outside them. Native filters can allocate additional
intermediates not bounded by `current-skia-byte-limit`.

The observer recognizes new drawing/clip/layer entries. Save/restore and clip
queries still execute during preflight; no fabricated layer counts or clip
rectangles are returned. Known unsupported SVG point/layer use is reported
before submission in strict audited exports. See
[CANVAS-PRIMITIVES.md](CANVAS-PRIMITIVES.md) for semantic restrictions.

## Output audit observation

No C symbols, C layouts, or function signatures are added or changed. The
requirement remains 319 Skia / 27 HarfBuzz symbols. The existing private
`define-native` wrapper calls a Racket-side observer before/after its ordinary
FFI call. Normal native calls still execute once; preflight suppresses only
observed target drawing calls, not resource creation, metrics, state changes,
annotations, or drawing inside explicit raster groups.

The lifetime layer records compact symbolic resource provenance at allocation
and attachment. Weak lifetime-cell keys and immutable summaries never retain
native pointers or original child wrappers. Temporary pointer associations
exist only during synchronous `call-with-owned` scopes. Native lifetime checks,
thread affinity, refcounts, and release callbacks are unchanged. No observer
callback supplied by the user runs inside the FFI/lifetime boundary.

See [the output audit guide](OUTPUT-AUDIT.md) for conservative policy meanings
and the difference between observed features and visual equivalence.

## Runtime effects

Eighteen additional callouts bring the requirement to 319 Skia symbols; HarfBuzz
remains 27. New 64-bit reflection records are 40 bytes (uniform) and 24 (child).
Their two leading string-view words are intentionally opaque: names are copied
using the native name queries rather than interpreting C++ library internals.

Uniform data uses reflected, tightly packed four-byte components; half is still
32-bit storage, and matrix uniforms are column-major. The shader's separate
local matrix uses the existing row-major geometry M33. Native factories retain
uniform data and correctly typed children. See [runtime ABI notes](RUNTIME-ABI.md)
for layout offsets, ownership, and the boundary of the host-C mirror check.

## Document annotations

Three synchronous annotation entry points bring the requirement to 301 Skia
symbols; HarfBuzz remains 27. Existing 16-byte rects, 8-byte points, and owned
SkData are reused. No native struct or encoder layout changes are introduced.
URI/ID bytes include the terminal NUL in SkData's size. Native picture recording
retains a data reference; the transient constructor reference is then released.

Document name registries contain copied Racket strings/points in weak-key tables,
never pointers or references back to their document keys. Canvas access, mutation,
and finalization use the existing live-owner/thread checks. Validation precedes
native closing; explicit finish/abort/close releases registry entries. No finalizer
must call a Racket callback, serialize XML, or publish a file.

PDF delegates rectangle transformation/clipping and destination registration to
the pinned backend. SVG retains native calculated rectangle bounds, relocates
annotation elements outside stale graphics clip groups, and appends deterministic
predefined views for named points. See [annotation semantics](ANNOTATIONS.md).

## Color output

Thirteen additional synchronous bindings bring the requirement to
298 Skia symbols; HarfBuzz remains 27. Twelve construct/query color spaces;
the extra `sk_pixmap_set_colorspace` binding is used only on the temporary PNG
encoding view when an explicit ICC profile must override Skia's sRGB shortcut.
That view must remain color-space-tagged: m119's shared ICC writer returns no
profile at all for a null source color space. The wrapper therefore substitutes
a temporary linear-sRGB tag (non-null and not `isSRGB`) while the explicit parsed
ICC profile supplies the actual encoded characterization. Pixel bytes are not
converted or relabeled on the caller's image.
Native transfer functions are seven
floats (28 bytes), XYZ-D50 matrices nine row-major floats (36 bytes), and
primaries/white-point chromaticities eight floats (32 bytes). These are color
transforms, not the geometry M33/M44 types.

Existing PNG/JPEG/WebP option layouts are unchanged. Their ICC profile fields
point to a parsed native skcms profile, not raw ICC bytes or SkData. The wrapper
copies incoming bytes into SkData, parses a temporary native profile, and keeps
both plus a native NUL-terminated description alive until encoding completes.
All of those pointers are private. Native writing rebuilds profile metadata;
unsupported LUT/HDR override profiles are rejected before that writer is called.

New RGB constructors copy the numerical values. Returned inspection vectors and
transfer records are detached and immutable; color-space wrappers retain the
same creator-thread/explicit-close rules as other owned resources. Pixel
conversion creates an independent eight-bit RGBA raster rather than mutating
source data or retagging it in place.

PDF/A uses the already-declared metadata bool. It adds no C layout or new PDF
symbol and does not create a user-selectable output intent. The native document
metadata copier consumes the flag synchronously, as it does existing strings
and dates. See [color-output semantics](COLOR-OUTPUT.md).

## Filter graphs

Twenty additional synchronous C factories bring the requirement to 285 Skia
symbols; HarfBuzz remains 27. New structures are two int32 pairs (isize/ipoint,
8 bytes each) and three floats (point3, 12 bytes). Matrix transforms use the
existing 36-byte M33, not the canvas M44. See tools/check-filter-abi.c.

The pinned shim refs graph inputs, images, pictures, and shaders. Constructors
validate and hold owned inputs during native calls; input pointer arrays,
convolution kernels, crop rectangles, and sampling structures are temporary.
Native kernels are copied. Graphs may outlive their input wrappers, and paints
may outlive graph wrappers. Private identity Offset nodes represent implicit
source slots so optimized valid Src/Dst/identity results remain non-null owned
resources. Empty results, such as a clear blend or empty crop, are not source.

Factories without a native crop parameter use a scoped intermediate reference
and an output crop implemented via zero-offset-with-crop. There are no new
native-to-Racket callbacks or changes to document/page lifetimes. See
[the filter guide](FILTER-GRAPHS.md) for pinned crop/tile qualifications.

## Path/matrix boundary

See [the pinned matrix ABI audit](PATH-MATRIX-ABI.md). Canvas entry points use
64-byte SkM44 storage; path/shader/measurement entry points use 36-byte M33.
These are not interchangeable, and the canvas's translation is at byte offsets
48 and 52. Public values are affine; a non-affine native readback is rejected.

Snapshot iterators exist only while the owning path is validated and locked.
They are always destroyed before copied Racket values or sequences are returned.
Shader wrappers own references; transformed paths own independent destinations.
No public native pointer or iterator resource is added.

## Shared output and text-blob snapshots

The shared page/export layer adds no native symbols or C layouts: 249 Skia and
27 HarfBuzz bindings remain required. Page specifications and unit/margin data
are ordinary immutable Racket values. They do not retain native output canvases.

Text blobs now retain an independent private SkFont snapshot and normalized
immutable glyph/position lists. Construction takes a temporary owned typeface
reference from the already-bound font query, copies the existing font properties,
and releases that temporary reference. Native blobs retain their own typeface
references independently. Explicit blob close releases both blob and snapshot;
each owned handle also has its own GC fallback. No release closure captures the
public blob wrapper. Returned outline paths own copied geometry and outlive the
blob. Creator-thread checks precede drawing/conversion.

Scoped text and raster-density parameters do not alter native structures. Text
policy acts during drawing/recording; it cannot rewrite a native picture replay.
Padded rasterization uses native-owned surfaces and copied snapshots, with no
retained Racket pixel buffers or new native-to-Racket callbacks. SVG physical-size
postprocessing changes only the completed root's width/height unit suffixes.

## SVG canvas ownership

SVG adds `sk_svgcanvas_create_with_stream` and `sk_canvas_destroy`: 249 required
Skia symbols in total, 27 HarfBuzz symbols, and no new C layouts. The pinned C
factory takes only bounds and a stream; it does not expose C++ flags.

A single owned native memory-stream handle retains private SVG storage. The
storage holds the owned SVG canvas, which must be deleted before detaching the
stream because its destructor closes buffered XML elements. This destructor is
never used for borrowed surface, picture, or PDF page canvases. Finish caches
postprocessed immutable Racket bytes and invalidates every SVG canvas alias;
the live document may still supply independent byte/string copies. Releasing
or aborting the wrapper discards the cache and destroys any remaining canvas
before the stream. The release closure captures storage, not the wrapper.

Native callouts remain synchronous and thread-confined. Scoped exits and
continuation escapes close the owned handle; finalizers never publish files.
The two explicit geometry/raster helpers use existing path/font/image APIs.
The root/ID postprocessor is deliberately limited to the pinned serializer's
XML, not a general SVG parser or sanitizer. See [SVG output](SVG-OUTPUT.md).

## PDF document ownership and layouts

The PDF layer adds seven Skia symbols and no HarfBuzz symbols. Its C metadata
layout has eight pointers, a float raster DPI, a one-byte bool, padding, and an
int encoding quality: 80 bytes on the validated 64-bit C mirror. The timestamp
contains int16 UTC-offset minutes, uint16 year, and six uint8 calendar/clock
fields: 10 bytes. The corresponding Racket FFI layouts still require a host run.

A single owned handle releases an unfinished document by aborting it, then
unrefs the document, unrefs any detached output data, and destroys the native
memory stream. The document borrows that stream. Finalization closes the native
document and detaches its output into retained SkData; each public byte read
copies the data. Native stream/data pointers never escape the public API.

The metadata shim copies SkStrings and timestamps during construction; the
wrapper scopes all temporary strings and keeps date structs alive through the
call. No Racket port or pixel buffer is retained by a native document.

Every page canvas has a fresh Racket validity token and retains its document.
Native calls require both a live thread-confined document handle and the exact
currently active page token. Ending a page invalidates its canvases permanently;
starting another page cannot revive an earlier canvas, even if Skia reuses an
address. Protected page/canvas scopes reject manual page-ending.

See [PDF output](PDF-OUTPUT.md) for pinned source links and
[PDF validation](PDF-TESTING.md) for ABI, native, structural, and visual checks.
The version-specific sections below retain historical implementation notes.

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
| Integer rectangle | int32 left, top, right, bottom | 16 |
| Point | float x, y | 8 |
| Sampling options | int max-anisotropy, bool use-cubic, padding, float B, float C, int filter, int mipmap | 24 |
| PNG options | int filter flags, int compression, comments pointer, ICC-profile pointer, ICC-description pointer | 32 |
| JPEG options | int quality, int downsample, int alpha option, alignment, XMP pointer, ICC-profile pointer, ICC-description pointer | 40 |
| WebP options | int compression, float quality, ICC-profile pointer, ICC-description pointer | 24 |
| Font metrics | uint32 flags, then 15 floats from top through strikeout position | 64 |

All optional PNG/JPEG/WebP pointer fields used by this binding are initialized
to NULL. JPEG's first pointer begins at offset 16 on a 64-bit ABI because the
three leading C ints occupy 12 bytes and the pointer requires 8-byte alignment.
The host-C checker and Racket pure tests both exercise these offsets. Sampling
fields are initialized even when cubic filtering and mipmaps are disabled.
Surface creation explicitly selects RGBA8888 rather than relying on
platform-dependent native color ordering.

`sk_point_t` is two adjacent C floats. Linear gradients pass two points as four
contiguous floats; radial, sweep, and conical constructors use the corresponding
8-byte point structure. Tile modes are the pinned native values clamp=0,
repeat=1, mirror=2, decal=3.

The integer rectangle is used for raster image subsets. Source rectangles passed
to `sk_canvas_draw_image_rect` remain floating-point `sk_rect_t` values.

The text-blob runbuffer mirrors `sk_textblob_builder_runbuffer_t` as four
native pointers (`glyphs`, `pos`, `utf8text`, `clusters`). Version 0.9 only
uses the positioned-run allocation, so `glyphs` points at native `uint16_t`
storage and `pos` at contiguous 8-byte `sk_point_t` values. Those pointers are
borrowed from the temporary builder and are never exposed publicly or retained
after `sk_textblob_builder_make`.

The font-metrics flags are copied as a 32-bit mask. The four decoration fields
(underline thickness/position and strikeout thickness/position) are exposed to
Racket only when their corresponding native validity bit is set. UTF-8 simple
text uses the pinned native text-encoding value 0.

The 0.1 through 0.8 declarations have been live-tested on macOS/aarch64 with
Racket 9.3.0.2 and the pinned native asset. Version 0.9 adds the four-pointer
text-blob runbuffer layout plus font-manager/text-blob callouts; those additions
are source/ABI checked in the authoring environment and require the included
local Racket/native run before they receive the same validation status. A host-C
layout check is not a substitute for validating Racket's actual FFI
declarations.

## Ownership map

| Resource | Release function | Rule |
|---|---|---|
| Surface | `sk_surface_unref` | One owned reference |
| Canvas from a surface | None | Borrowed; surface wrapper retained |
| Paint | `sk_paint_delete` | Native-owned object; retains attached shader/path-effect/filter refs |
| Shader | `sk_shader_unref` | One owned reference |
| Path effect | `sk_path_effect_unref` | One owned reference; paints/composed effects retain inputs |
| Color filter | `sk_colorfilter_unref` | One owned reference; paints/composed filters retain inputs |
| Mask filter | `sk_maskfilter_unref` | One owned reference; paints retain it |
| Image filter | `sk_imagefilter_unref` | One owned reference; paints/filter graphs retain inputs |
| Path | `sk_path_delete` | Native-owned object |
| Path measure | `sk_pathmeasure_destroy` | Owns a private cloned `SkPath`; measure destroyed before clone |
| Image/snapshot/decoded/subset image | `sk_image_unref` | One owned reference |
| Typeface | `sk_typeface_unref` | One owned reference |
| Font manager | `sk_fontmgr_unref` | Owned ref-counted manager; default-manager wrapper receives its own ref |
| Font | `sk_font_delete` | Native-owned object; may retain a private default typeface wrapper |
| Text blob | `sk_textblob_unref` | Immutable ref-counted blob made from a temporary builder |
| Temporary encoded `SkData` | `sk_data_unref` | Owned while creating/probing an encoded image |
| Temporary codec | `sk_codec_destroy` | Owned only while copying metadata |
| Codec info color-space reference | `sk_colorspace_unref` | Released after scalar metadata is copied |
| Temporary raster image | `sk_image_unref` | Owned while exposing a pixmap for encoding |
| Temporary font style | `sk_fontstyle_delete` | Owned only during family/font-manager matching |
| Temporary text-blob builder | `sk_textblob_builder_delete` | Owns writable run buffers only until the blob is sealed |
| Temporary native string | `sk_string_destructor` | Owned while copying a family name to Racket |
| Temporary pixmap | `sk_pixmap_destructor` | Descriptor owned only during encoding; pixels are borrowed |
| Temporary stream | `sk_dynamicmemorywstream_destroy` | Owned during encoding |
| Detached encoded data | `sk_data_unref` | Owned until bytes are copied to Racket |

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
constructor. Encoded byte input is copied into native `SkData`; both
`SkImages::DeferredFromEncodedData` and `SkCodec::MakeFromData` take their own
native references before the temporary Racket-side `SkData` wrapper is released.
File-backed encoded data is likewise confined to the constructor/probe scope.
Pixel readback and encoded output are copied into normal Racket byte strings.
`make-sized-byte-string` is not used because it is not supported by Racket CS.
The bridge to `bitmap%` also copies.

`sk_codec_get_info` deserves special care: the C shim's `ToImageInfo` returns a
referenced color-space pointer. Version 0.4 does not yet expose color spaces, so
the metadata probe copies width/height/color/alpha scalars and releases that
reference with `sk_colorspace_unref`, including when metadata conversion raises.
The pinned C shim implements `sk_codec_get_frame_count` using
`getFrameInfo().size()`, so still images may report zero frame-info entries.

Encoding a general `image?` first obtains a temporary raster image, borrows its
pixels through a temporary pixmap descriptor, writes to a native dynamic memory
stream, detaches `SkData`, then copies the encoded bytes to Racket. No returned
byte string aliases Skia memory. Image subsets own a new native image reference;
source-rectangle drawing borrows only the already-owned source image during the
synchronous canvas call.

Gradient colors and optional positions are copied into temporary atomic native
arrays for one synchronous FFI call. Skia constructs immutable shader state
before the call returns; no shader retains those array pointers. Image shaders
and blend shaders retain their native image/shader dependencies internally.

The m119 C paint getters are ownership-producing calls: shader, path-effect,
color-filter, mask-filter, and image-filter getters all call the corresponding
`ref...().release()`. Public paint getters therefore wrap non-null returned
pointers directly as one owned reference. The initial 0.3/0.4 `paint-shader`
wrapper incorrectly added another `sk_shader_ref`; rendering remained correct,
but one native ref leaked per getter call. Version 0.5 removes that extra ref.
Paint setters use `sk_ref_sp`, so paints retain their own references independently
of caller wrappers.

Dash interval arrays are temporary atomic native float arrays consumed
synchronously by `SkDashPathEffect::Make`. Path effects returned by constructors
own one native reference; compose/sum effects retain their dependencies.

Color-matrix filter coefficients are likewise copied into a temporary atomic
20-float array for one synchronous constructor call. The resulting color filter
does not retain that array. Color-filter composition, image-filter input graphs,
and filter attachment to paints all retain inputs internally with `sk_ref_sp`.
Filter getters from paints return ownership-producing references, not borrowed
pointers. Blur mask/image filters and drop shadows use only scalar parameters;
no Racket memory is retained by native filter objects.

Raw `SkPathMeasure` stores a pointer to path data rather than a ref-counted path.
The public 0.5 wrapper therefore clones the input `SkPath` and owns that private
snapshot together with the measure. Its release operation destroys
`SkPathMeasure` first and then the snapshot. Replacing the measured path clones
the new input before swapping it into the native measure, then deletes the old
snapshot. This prevents explicit closure or mutation of the caller's path from
creating dangling native state. Boolean PathOps consume owned path pointers only
for the duration of synchronous calls and write into a newly owned result path.

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


Font-manager matching returns newly owned typeface references from the native
`sk_sp::release()` path. The manager does not need to remain live after a
successful match. BCP-47 language strings are copied into temporary C buffers
and a temporary `char**` array for the synchronous match call; none are
retained by Racket or Skia afterward.

Text-blob construction writes only into native run buffers allocated by the
builder. `sk_textblob_builder_make` transfers/seals the recorded run into one
owned blob reference. The builder is destroyed immediately afterward. The blob
contains/copies the `SkFont` state needed by the run, so Racket does not keep a
font wrapper alive solely for blob lifetime.

## Deliberate exclusions

No native-to-Racket callbacks, custom streams invoking Racket callbacks,
retained client pixel buffers, GPU contexts, arbitrary user native pointers,
or C++ exception boundary enter the public API. Shaping, bidi/paragraph layout,
color spaces, owned codecs, animated frames, orientation normalization, and PDF
output are implemented above the private native layer. Incremental/scanline
decoding, arbitrary encoder metadata, shader-local matrices, and full SVG
output remain outside this release. The filter subset does not expose crop
rectangles, arithmetic/merge/morphology, displacement, convolution, lighting,
table, or runtime-effect filter APIs.

Normal C library failures are converted to Racket exceptions where the ABI
provides failure results; a native crash/abort cannot be caught as an ordinary
Racket exception by this wrapper.

## Revalidation when changing the pin

Compare every used C prototype, enum, struct layout, and ownership rule against
the new version. Update the package URLs and accepted milestone together. Run
pure tests, doctor, native tests, and visual examples on each supported
architecture. Review alpha conversion; PNG/JPEG/WebP option fields; codec
color-space ownership; encoded-data retention; source/subset rectangles;
sampling padding; font-metrics and text-blob-runbuffer layouts; UTF-8/glyph
conversion; font-manager match ownership and temporary BCP-47 buffers;
text-blob builder/run-buffer ownership; shader/path-effect/filter refcounts;
path-measure snapshot ownership; PathOps results; color-matrix arrays;
blur/shadow filter construction;
filter-graph input retention; typeface/font lifetime; image snapshot lifetime;
and both explicit and GC cleanup. Do not simply widen the milestone check until
an incompatible build loads.


## HarfBuzz shaping ABI

Version 0.10 optionally loads `libHarfBuzzSharp` 8.3.1.2, containing HarfBuzz
8.3.1. It is lazy and separate from `libSkiaSharp`; the core Skia APIs remain
usable without it. The shaping layer mirrors the public `hb_glyph_info_t`
(20 bytes), `hb_glyph_position_t` (20 bytes), and `hb_feature_t` (16 bytes)
layouts. Font bytes are copied from an owned SkTypeface stream into an
`HB_MEMORY_MODE_DUPLICATE` blob before temporary Skia stream storage is released.


## Version 0.11 paragraph layout

Version 0.11 adds no native declarations and no ABI structs. Paragraph layout
is implemented in Racket above the live-validated 0.10 shaping and text-blob
layers, so both symbol-audit counts remain unchanged.


## 0.12 mixed text

Version 0.12 adds no Skia C ABI structs and no new by-value HarfBuzz structs.
It adds the borrowed `hb_unicode_funcs_get_default` lookup and
`hb_unicode_script` query, bringing the HarfBuzz symbol audit from 25 to 27
required exports. The default Unicode-functions pointer is transfer-none and is
never destroyed by the Racket wrapper. Mixed-layout objects are pure Racket
metadata; transient fallback shapers follow the existing deterministic resource
cleanup rules.
