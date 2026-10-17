#lang racket/base

;;;
;;; Core Skia Native Layouts
;;;

;; Defines the pinned C records and constants used by the Skia FFI.
;; Keeps native byte layout separate from checked public values and resource wrappers.

(require ffi/unsafe)
(provide (all-defined-out))

;; m119 sk_color4f_t: RGBA, four floats, passed by VALUE by canvas clear/draw.
(define-cstruct _sk-color4f ([r _float] [g _float] [b _float] [a _float]))
;; Fields:
;;   r, g, b, and a: single-precision red, green, blue, and alpha components in RGBA order. Alpha is
;;   a coverage fraction; RGB interpretation follows the associated color space. The record is
;;   passed by value by selected canvas calls.


;; The m119 C shim reinterprets this record as SkCanvas::Lattice. RectTypes
;; *elements* must be uint8_t (the C++ enum), NOT the C header's int-sized enum.
(define-cstruct _sk-lattice
  ([x-divs _pointer] [y-divs _pointer] [rect-types _pointer]
   [x-count _int] [y-count _int] [bounds _pointer] [colors _pointer]))
;; Fields:
;;   x-divs and y-divs: borrowed ordered int32 division arrays. rect-types: optional uint8 cell-type
;;   array in row-major order. x-count and y-count: corresponding division counts.
;;   bounds: optional borrowed integer source rectangle. colors: optional row-major packed-color
;;   array. Counts determine array lengths; all arrays remain live for the synchronous drawing call.
;;   Cell types are byte-sized despite the C header's enum declaration.

(define-cstruct _sk-rsxform ([scos _float] [ssin _float] [tx _float] [ty _float]))
;; Fields:
;;   scos and ssin: scale times cosine/sine of the rotation. tx and ty: translation in drawing
;;   units. Four floats encode the affine map x'=scos*x-ssin*y+tx, y'=ssin*x+scos*y+ty.


;; m119 copies std::string_view as two machine words. Their ordering is a C++
;; library detail, so NEVER dereference these words as a name pointer. The
;; separate get_uniform_name / get_child_name calls copy names into SkString.
(define-cstruct _sk-runtime-uniform
  ([name-word0 _size] [name-word1 _size] [offset _size]
   [type _int] [count _int] [flags _uint32]))
;; Fields:
;;   name-word0 and name-word1: opaque machine words copied from native string_view; never
;;   dereference them as a name. offset: size_t byte offset. type: native uniform enum. count:
;;   element count. flags: uniform bitmask.
;;   Name text is copied through dedicated native queries. Offsets, widths, and declaration order
;;   are pinned to the supported C++ ABI.

(define-cstruct _sk-runtime-child
  ([name-word0 _size] [name-word1 _size] [type _int] [index _int]))
;; Fields:
;;   name-word0 and name-word1: opaque native string_view words, not usable name pointers. type:
;;   child-kind enum. index: native binding position. Dedicated name-copy calls supply text
;;   independently of these words.


;; skcms SDR transfer function and RGB->XYZ(D50), not geometry matrices.
(define-cstruct _sk-transfer
  ([g _float] [a _float] [b _float] [c _float] [d _float] [e _float] [f _float]))
;; Fields:
;;   g, a, b, c, d, e, and f: seven single-precision transfer-function parameters in skcms order.
;;   The ordinary SDR form is (a*x+b)^g+e for x>=d and c*x+f below d. These are color-transfer
;;   coefficients, not geometry.

(define-cstruct _sk-xyz
  ([m00 _float] [m01 _float] [m02 _float]
   [m10 _float] [m11 _float] [m12 _float]
   [m20 _float] [m21 _float] [m22 _float]))
;; Fields:
;;   m00 through m22: nine floats in row-major order, mapping linear RGB to XYZ with D50 white.
;;   Row/column meaning is colorimetric and differs from geometric canvas transforms.

(define-cstruct _sk-primaries
  ([rx _float] [ry _float] [gx _float] [gy _float]
   [bx _float] [by _float] [wx _float] [wy _float]))
;; Fields:
;;   rx/ry, gx/gy, and bx/by: red, green, and blue xy chromaticity pairs. wx/wy: white-point xy
;;   chromaticity. Eight floats are ordered by primary, then white point.


;; Pinned sk_isize_t / sk_ipoint_t / sk_point3_t used by filter factories.
(define-cstruct _sk-isize ([width _int32] [height _int32]))
;; Fields:
;;   width and height: signed 32-bit integer extents. Constructors validate the range appropriate to
;;   the operation before passing this native record.

(define-cstruct _sk-ipoint ([x _int32] [y _int32]))
;; Fields:
;;   x and y: signed 32-bit integer coordinates in axis order. Coordinate units depend on the
;;   filter/geometry operation using the record.

(define-cstruct _sk-point3 ([x _float] [y _float] [z _float]))
;; Fields:
;;   x, y, and z: single-precision three-dimensional coordinates, used by lighting/filter geometry.
;;   The order is Cartesian x,y,z.


;; m119: path/shader/measure matrices are nine row-major floats.
(define-cstruct _sk-matrix
  ([xx _float] [xy _float] [x0 _float]
   [yx _float] [yy _float] [y0 _float]
   [p0 _float] [p1 _float] [p2 _float]))
;; Fields:
;;   xx, xy, x0; yx, yy, y0; p0, p1, p2: nine floats in row-major order. The first two rows contain
;;   affine coefficients and translations; the last row contains perspective coefficients. This
;;   layout is for paths, shaders, and measures, not SkM44 canvas storage.

;; Canvas get/set/concat reinterpret sixteen floats as SkM44, whose storage
;; is column-major. Do not pass _sk-matrix or follow the misleading C header's
;; row-name comment here. See docs/PATH-MATRIX-ABI.md and independent readback tests.
(define-cstruct _sk-m44
  ([c0r0 _float] [c0r1 _float] [c0r2 _float] [c0r3 _float]
   [c1r0 _float] [c1r1 _float] [c1r2 _float] [c1r3 _float]
   [c2r0 _float] [c2r1 _float] [c2r2 _float] [c2r3 _float]
   [c3r0 _float] [c3r1 _float] [c3r2 _float] [c3r3 _float]))
;; Fields:
;;   c0r0 through c3r3: sixteen floats grouped by column, then row. Translation occupies column 3.
;;   This is column-major SkM44 storage; substituting the nine-float path matrix or reordering by
;;   row corrupts canvas transforms.


;; Full sk_document_pdf_datetime_t and sk_document_pdf_metadata_t layouts.
;; Metadata's C bool is one byte, followed by padding before encoding-quality.
(define-cstruct _sk-pdf-datetime
  ([zone-minutes _int16] [year _uint16] [month _uint8] [weekday _uint8]
   [day _uint8] [hour _uint8] [minute _uint8] [second _uint8]))
;; Fields:
;;   zone-minutes: signed UTC offset in minutes, -1439..1439. year: 1..9999. month: 1..12;
;;   weekday: 0..6 with Sunday zero; day: valid day of the selected month/year. hour: 0..23;
;;   minute and second: 0..59. Calendar and whole-minute-offset validation precede construction;
;;   field order and integer widths match the native PDF date record.

(define-cstruct _sk-pdf-metadata
  ([title _pointer] [author _pointer] [subject _pointer] [keywords _pointer]
   [creator _pointer] [producer _pointer] [creation _pointer] [modified _pointer]
   [raster-dpi _float] [pdfa? _stdbool] [encoding-quality _int]))
;; Fields:
;;   title, author, subject, keywords, creator, and producer: optional native string pointers.
;;   creation and modified: optional _sk-pdf-datetime pointers.
;;   raster-dpi: fallback resolution in dots per inch, 1..9600. pdfa?: one-byte C boolean enabling
;;   PDF/A output. encoding-quality: 0..100 for lossy image quality, or 101 for lossless encoding.
;;   Metadata pointers remain live through creation; padding before encoding-quality is
;;   ABI-significant.


;; These layouts match SkiaSharp v3.119.1's SkiaApi.generated.cs and
;; generated native structs.  Keep this module boring: the FFI boundary
;; depends on byte-for-byte agreement with the pinned native ABI.
(define-cstruct _sk-image-info
  ([colorspace _pointer] [width _int32] [height _int32]
   [color-type _int] [alpha-type _int]))
;; Fields:
;;   colorspace: optional native color-space pointer. width and height: signed 32-bit pixel
;;   dimensions. color-type: reviewed Skia format code (for example 4 = RGBA8888, 6 = BGRA8888).
;;   alpha-type: 1 opaque, 2 premultiplied, or 3 straight alpha; 0 denotes unknown native metadata.
;;   The caller retains the color space for the entire synchronous native use.

(define-cstruct _sk-rect
  ([left _float] [top _float] [right _float] [bottom _float]))
;; Fields:
;;   left, top, right, and bottom: single-precision rectangle edges in drawing coordinates. Width
;;   and height are differences between edges; order matches SkRect.

(define-cstruct _sk-point
  ([x _float] [y _float]))
;; Fields:
;;   x and y: single-precision coordinates in axis order. Point arrays preserve the caller's
;;   path/vertex order.

;; sk_textblob_builder_runbuffer_t: native-owned writable buffers returned by
;; SkTextBlobBuilder allocation calls. The pointers remain valid only until
;; the builder is made/reset/destroyed.
(define-cstruct _sk-textblob-runbuffer
  ([glyphs _pointer] [pos _pointer] [utf8text _pointer] [clusters _pointer]))
;; Fields:
;;   glyphs: native writable glyph-id array. pos: native writable positions/transforms for the
;;   selected run mode. utf8text: optional text-byte buffer. clusters: optional per-glyph UTF-8 byte
;;   offsets.
;;   All pointers are builder-owned and expire when the builder is made, reset, or destroyed. Array
;;   lengths come from the corresponding allocation request.

(define-cstruct _sk-irect
  ([left _int32] [top _int32] [right _int32] [bottom _int32]))
;; Fields:
;;   left, top, right, and bottom: signed 32-bit integer rectangle edges, typically in pixel
;;   coordinates. This inline layout is also embedded in codec frame information.

;; SkiaSharp 3.119.1, skia 40f75dc: bool is one byte, and the frame
;; rectangle is inline (not a pointer). Keep the complete 44-byte frame record.
(define-cstruct _sk-codec-options
  ([zero-initialized _int] [subset _pointer]
   [frame-index _int] [prior-frame _int]))
;; Fields:
;;   zero-initialized: native destination-initialization enum. subset: optional borrowed integer
;;   rectangle. frame-index: requested animation frame. prior-frame: initialized prerequisite frame
;;   index or native sentinel. The subset pointer remains live during decoding.

(define-cstruct _sk-codec-frame-info
  ([required-frame _int] [duration _int] [fully-received _stdbool]
   [alpha-type _int] [has-alpha-within-bounds _stdbool]
   [disposal-method _int] [blend _int] [frame-rect _sk-irect]))
;; Fields:
;;   required-frame: prerequisite frame index or sentinel. duration: milliseconds. fully-received:
;;   complete-input C boolean. alpha-type: native alpha enum. has-alpha-within-bounds: C boolean.
;;   disposal-method and blend: animation compositing enums. frame-rect: inline integer frame
;;   bounds, not a pointer. Boolean widths and inline rectangle layout are required for the pinned
;;   44-byte ABI.

(define-cstruct _sk-png-options
  ([filter-flags _int] [zlib-level _int] [comments _pointer]
   [icc-profile _pointer] [icc-description _pointer]))
;; Fields:
;;   filter-flags: PNG row-filter bitmask; wrappers use 248 to allow all filters. zlib-level: exact
;;   compression level 0..9, with 0 uncompressed and 9 maximum compression. comments: optional native
;;   comment data pointer, #f in these wrappers. icc-profile: parsed native profile or #f;
;;   icc-description: NUL-terminated UTF-8 description pointer or #f. All pointed-to storage remains
;;   live until encoding returns.

(define-cstruct _sk-jpeg-options
  ([quality _int] [downsample _int] [alpha-option _int]
   [xmp-metadata _pointer] [icc-profile _pointer] [icc-description _pointer]))
;; Fields:
;;   quality: exact integer 0..100. downsample: 0 YUV420, 1 YUV422, or 2 YUV444. alpha-option:
;;   0 ignores alpha; 1 blends on black. xmp-metadata: optional native XMP pointer, #f here.
;;   icc-profile and icc-description: parsed profile and NUL-terminated UTF-8 description pointers
;;   or #f; their storage remains live through encoding.

(define-cstruct _sk-webp-options
  ([compression _int] [quality _float]
   [icc-profile _pointer] [icc-description _pointer]))
;; Fields:
;;   compression: 0 lossy or 1 lossless. quality: single-precision real in 0..100; in lossless mode
;;   this controls encoding effort rather than pixel fidelity. icc-profile and icc-description:
;;   parsed profile and NUL-terminated UTF-8 description pointers or #f, valid for the encoding call.

(define-cstruct _sk-sampling
  ([max-aniso _int] [use-cubic _stdbool]
   [cubic-b _float] [cubic-c _float] [filter _int] [mipmap _int]))
;; Fields:
;;   max-aniso: anisotropic sampling setting, zero in the nearest/linear wrappers. use-cubic:
;;   C boolean selecting cubic reconstruction, #f here; cubic-b and cubic-c: inactive coefficients,
;;   both 0.0.
;;   filter: 0 nearest or 1 linear; mipmap: 0 disables mipmaps in these wrappers. Only fields selected
;;   by the sampling mode are active; declaration order and padding are ABI-significant.


;; sk_fontmetrics_t / SKFontMetrics.  The flags word says which of the
;; decoration metrics are meaningful; the remaining fields are floats.
(define-cstruct _sk-font-metrics
  ([flags _uint32]
   [top _float]
   [ascent _float]
   [descent _float]
   [bottom _float]
   [leading _float]
   [avg-char-width _float]
   [max-char-width _float]
   [x-min _float]
   [x-max _float]
   [x-height _float]
   [cap-height _float]
   [underline-thickness _float]
   [underline-position _float]
   [strikeout-thickness _float]
   [strikeout-position _float]))
;; Fields:
;;   flags: validity bitmask for optional metrics. top, ascent, descent, and bottom: signed vertical
;;   bounds relative to the baseline. leading: extra line gap. avg-char-width and max-char-width:
;;   horizontal size metrics.
;;   x-min and x-max: horizontal font bounds. x-height and cap-height: height metrics.
;;   underline-thickness, underline-position, strikeout-thickness, and strikeout-position:
;;   decoration measurements, valid only when their flag is set.
;;   All measurements are single-precision values at the selected font size. Declaration order
;;   follows sk_fontmetrics_t; public conversion replaces invalid optional metrics with #f.


; rgba-8888 : exact-nonnegative-integer?
;;   Selects Skia's four-byte red/green/blue/alpha color-type layout.
(define rgba-8888 4)
; alpha-premul : exact-nonnegative-integer?
;;   Selects premultiplied alpha in Skia's native alpha-type enumeration.
(define alpha-premul 2)
; alpha-unpremul : exact-nonnegative-integer?
;;   Selects straight, unpremultiplied alpha in Skia's native alpha-type enumeration.
(define alpha-unpremul 3)
; png-all-filters : exact-nonnegative-integer?
;;   Enables all reviewed PNG row-filter choices in the native encoder bitmask.
(define png-all-filters 248)

;; sk_text_encoding_t
; text-encoding-utf8 : exact-nonnegative-integer?
;;   Declares that text buffers passed to native text APIs contain UTF-8 bytes.
(define text-encoding-utf8 0)

;; sk_fontmetrics_t flags
; font-metric-underline-thickness-valid : exact-nonnegative-integer?
;;   Marks the underline-thickness field as valid in a native font-metrics record.
(define font-metric-underline-thickness-valid #x1)
; font-metric-underline-position-valid : exact-nonnegative-integer?
;;   Marks the underline-position field as valid in a native font-metrics record.
(define font-metric-underline-position-valid #x2)
; font-metric-strikeout-thickness-valid : exact-nonnegative-integer?
;;   Marks the strikeout-thickness field as valid in a native font-metrics record.
(define font-metric-strikeout-thickness-valid #x4)
; font-metric-strikeout-position-valid : exact-nonnegative-integer?
;;   Marks the strikeout-position field as valid in a native font-metrics record.
(define font-metric-strikeout-position-valid #x8)
