#lang racket/base
;; Standalone resource inspection. No GUI or implicit default-family replacement.
(require racket/cmdline racket/file racket/list "../main.rkt")
(module+ main
  (define filename #f)
  (command-line #:args (font-file) (set! filename font-file))
  (with-skia ([face (typeface-from-bytes (file->bytes filename))])
    (printf "Family: ~a\nPostScript: ~a\nGlyphs: ~a\nUnits/em: ~a\nStyle: ~a\n"
            (typeface-family-name face) (typeface-postscript-name face)
            (typeface-glyph-count face) (typeface-units-per-em face) (typeface-style face))
    (for ([tag (in-vector (typeface-table-tags face))])
      (printf "~s: ~a bytes\n" (font-table-tag->bytes tag) (typeface-table-size face tag)))))
