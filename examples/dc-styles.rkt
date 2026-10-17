#lang racket/base

;;;
;;; DC Styles Example
;;;

;; Writes the shared drawing-context style corpus to a PNG.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Writes the bounded style corpus; no GUI, GPU or reference-image fallback.
;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline "../dc.rkt" "../tests/dc-style-fixtures.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; output : string?
  ;   Selects the destination used by this example's output.
  (define output "dc-styles.png")
  (command-line #:args ([path "dc-styles.png"]) (set! output path))

  ; dc : (is-a?/c skia-dc%)
  ;   Owns the raster Skia drawing context used to save the style corpus.
  (define dc (new skia-dc% [width 64] [height 64]))
  (dynamic-wind void
    (lambda () (style-oracle dc)
      (call-with-output-file output (lambda (out) (write-bytes (send dc get-png-bytes) out))
                            #:mode 'binary #:exists 'replace))
    (lambda () (send dc close))))
