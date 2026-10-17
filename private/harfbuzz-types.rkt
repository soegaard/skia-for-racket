#lang racket/base

;;;
;;; HarfBuzz Native Layouts
;;;

;; Defines glyph-info, glyph-position, and feature records.
;; Keeps shaping buffers compatible with the pinned HarfBuzz ABI.

(require ffi/unsafe)
(provide (all-defined-out))

;; HarfBuzz 8.3.1 public ABI structs used by the shaping layer.
(define-cstruct _hb-glyph-info
  ([codepoint _uint32]
   [mask _uint32]
   [cluster _uint32]
   [var1 _uint32]
   [var2 _uint32]))
;; Fields:
;;   codepoint: shaped glyph identifier, not a Unicode scalar after shaping. mask: HarfBuzz glyph
;;   mask. cluster: source cluster index, expressed as UTF-8 byte offset for this binding. var1 and
;;   var2: reserved HarfBuzz working words.
;;   All fields are uint32 in native buffer order. Reserved fields are never interpreted as
;;   application metadata.


(define-cstruct _hb-glyph-position
  ([x-advance _int32]
   [y-advance _int32]
   [x-offset _int32]
   [y-offset _int32]
   [var _int32]))
;; Fields:
;;   x-advance and y-advance: signed pen advances. x-offset and y-offset: signed glyph offsets
;;   relative to the pen. var: reserved native working word. Values use the HarfBuzz font scale
;;   selected by the caller; array order matches glyph-info order.


(define-cstruct _hb-feature
  ;; `define-cstruct` itself creates an hb-feature-tag binding for the
  ;; native-pointer tag, so the C field cannot also be named `tag`.
  ;; Field names are Racket-side only; this keeps the exact ABI layout.
  ([feature-tag _uint32]
   [value _uint32]
   [start _uint32]
   [end _uint32]))
;; Fields:
;;   feature-tag: packed four-byte OpenType tag. value: unsigned feature setting. start and end:
;;   half-open cluster range, with HarfBuzz's global-range sentinels where applicable. Features are
;;   passed in list order.


; hb-memory-mode-duplicate : exact-nonnegative-integer?
;;   Requests a HarfBuzz-owned copy of blob input bytes so caller storage need not outlive the blob.
(define hb-memory-mode-duplicate 0)
; hb-font-size-scale : exact-nonnegative-integer?
;;   Converts drawing-unit font sizes into the fixed 512-unit scale used for shaping positions.
(define hb-font-size-scale 512)
