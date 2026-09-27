#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))
;; sk_highcontrastconfig_t in the pinned m119 C header. The bool is one byte;
;; default ABI alignment places the 32-bit enum at 4 and float at 8 (size 12).
(define-cstruct _sk-high-contrast-config
  ([grayscale _stdbool] [invert-style _int] [contrast _float]))
