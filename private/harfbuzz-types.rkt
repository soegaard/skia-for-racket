#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))

;; HarfBuzz 8.3.1 public ABI structs used by the shaping layer.
(define-cstruct _hb-glyph-info
  ([codepoint _uint32]
   [mask _uint32]
   [cluster _uint32]
   [var1 _uint32]
   [var2 _uint32]))

(define-cstruct _hb-glyph-position
  ([x-advance _int32]
   [y-advance _int32]
   [x-offset _int32]
   [y-offset _int32]
   [var _int32]))

(define-cstruct _hb-feature
  ;; `define-cstruct` itself creates an hb-feature-tag binding for the
  ;; native-pointer tag, so the C field cannot also be named `tag`.
  ;; Field names are Racket-side only; this keeps the exact ABI layout.
  ([feature-tag _uint32]
   [value _uint32]
   [start _uint32]
   [end _uint32]))

(define hb-memory-mode-duplicate 0)
(define hb-font-size-scale 512)
