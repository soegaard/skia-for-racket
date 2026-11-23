#lang racket/base

;;;
;;; Color Filter Native Layouts
;;;

;; Defines the high-contrast configuration record required by Skia.
;; Keeps the color-filter FFI layout separate from public argument validation.

(require ffi/unsafe)
(provide (all-defined-out))
;; sk_highcontrastconfig_t in the pinned m119 C header. The bool is one byte;
;; default ABI alignment places the 32-bit enum at 4 and float at 8 (size 12).
(define-cstruct _sk-high-contrast-config
  ([grayscale _stdbool] [invert-style _int] [contrast _float]))
;; Fields:
;;   grayscale: C boolean enabling grayscale conversion. invert-style: native inversion enum.
;;   contrast: checked floating-point contrast adjustment. The one-byte boolean and subsequent
;;   padding are ABI-significant.
