#lang racket/base

;;;
;;; Typefaces Example
;;;

;; Inspects a supplied font file without replacing it with a default family.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Standalone resource inspection. No GUI or implicit default-family replacement.
;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file racket/list "../main.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; filename : (or/c path-string? #f)
  ;;   Selects the destination used by this example's output.
  (define filename #f)
  (command-line #:args (font-file) (set! filename font-file))
  (with-skia ([face (typeface-from-bytes (file->bytes filename))])
    (printf "Family: ~a\nPostScript: ~a\nGlyphs: ~a\nUnits/em: ~a\nStyle: ~a\n"
            (typeface-family-name face) (typeface-postscript-name face)
            (typeface-glyph-count face) (typeface-units-per-em face) (typeface-style face))
    (for ([tag (in-vector (typeface-table-tags face))])
      (printf "~s: ~a bytes\n" (font-table-tag->bytes tag) (typeface-table-size face tag)))))
