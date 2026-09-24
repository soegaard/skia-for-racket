#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))

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
