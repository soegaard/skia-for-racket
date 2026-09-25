#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))

;; Full sk_document_pdf_datetime_t and sk_document_pdf_metadata_t layouts.
;; Metadata's C bool is one byte, followed by padding before encoding-quality.
(define-cstruct _sk-pdf-datetime
  ([zone-minutes _int16] [year _uint16] [month _uint8] [weekday _uint8]
   [day _uint8] [hour _uint8] [minute _uint8] [second _uint8]))
(define-cstruct _sk-pdf-metadata
  ([title _pointer] [author _pointer] [subject _pointer] [keywords _pointer]
   [creator _pointer] [producer _pointer] [creation _pointer] [modified _pointer]
   [raster-dpi _float] [pdfa? _stdbool] [encoding-quality _int]))

;; These layouts match SkiaSharp v3.119.1's SkiaApi.generated.cs and
;; generated native structs.  Keep this module boring: the FFI boundary
;; depends on byte-for-byte agreement with the pinned native ABI.
(define-cstruct _sk-image-info
  ([colorspace _pointer] [width _int32] [height _int32]
   [color-type _int] [alpha-type _int]))
(define-cstruct _sk-rect
  ([left _float] [top _float] [right _float] [bottom _float]))
(define-cstruct _sk-point
  ([x _float] [y _float]))
;; sk_textblob_builder_runbuffer_t: native-owned writable buffers returned by
;; SkTextBlobBuilder allocation calls. The pointers remain valid only until
;; the builder is made/reset/destroyed.
(define-cstruct _sk-textblob-runbuffer
  ([glyphs _pointer] [pos _pointer] [utf8text _pointer] [clusters _pointer]))
(define-cstruct _sk-irect
  ([left _int32] [top _int32] [right _int32] [bottom _int32]))
;; SkiaSharp 3.119.1, skia 40f75dc: bool is one byte, and the frame
;; rectangle is inline (not a pointer). Keep the complete 44-byte frame record.
(define-cstruct _sk-codec-options
  ([zero-initialized _int] [subset _pointer]
   [frame-index _int] [prior-frame _int]))
(define-cstruct _sk-codec-frame-info
  ([required-frame _int] [duration _int] [fully-received _stdbool]
   [alpha-type _int] [has-alpha-within-bounds _stdbool]
   [disposal-method _int] [blend _int] [frame-rect _sk-irect]))
(define-cstruct _sk-png-options
  ([filter-flags _int] [zlib-level _int] [comments _pointer]
   [icc-profile _pointer] [icc-description _pointer]))
(define-cstruct _sk-jpeg-options
  ([quality _int] [downsample _int] [alpha-option _int]
   [xmp-metadata _pointer] [icc-profile _pointer] [icc-description _pointer]))
(define-cstruct _sk-webp-options
  ([compression _int] [quality _float]
   [icc-profile _pointer] [icc-description _pointer]))
(define-cstruct _sk-sampling
  ([max-aniso _int] [use-cubic _stdbool]
   [cubic-b _float] [cubic-c _float] [filter _int] [mipmap _int]))

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

(define rgba-8888 4)
(define alpha-premul 2)
(define alpha-unpremul 3)
(define png-all-filters 248)

;; sk_text_encoding_t
(define text-encoding-utf8 0)

;; sk_fontmetrics_t flags
(define font-metric-underline-thickness-valid #x1)
(define font-metric-underline-position-valid #x2)
(define font-metric-strikeout-thickness-valid #x4)
(define font-metric-strikeout-position-valid #x8)
