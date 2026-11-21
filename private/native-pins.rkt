#lang racket/base

;; Upstream pins are data. Importing this module does not load native code.
(require racket/file racket/runtime-path racket/string)
(provide native-skia-version native-harfbuzz-version)
(define-runtime-path skia-pin "native-default-version.txt")
(define-runtime-path harfbuzz-pin "harfbuzz-default-version.txt")
(define (pin path pattern)
  (define value (string-trim (file->string path)))
  (unless (regexp-match? pattern value) (error 'native-pins "malformed pin: ~a" path))
  (string->immutable-string value))
(define native-skia-version (pin skia-pin #px"^[0-9]+[.][0-9]+[.][0-9]+$"))
(define native-harfbuzz-version (pin harfbuzz-pin #px"^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$"))
