#lang racket/base
;; Writes the bounded style corpus; no GUI, GPU or reference-image fallback.
(require racket/class racket/cmdline "../dc.rkt" "../tests/dc-style-fixtures.rkt")
(module+ main
  (define output "dc-styles.png")
  (command-line #:args ([path "dc-styles.png"]) (set! output path))
  (define dc (new skia-dc% [width 64] [height 64]))
  (dynamic-wind void
    (lambda () (style-oracle dc)
      (call-with-output-file output (lambda (out) (write-bytes (send dc get-png-bytes) out))
                            #:mode 'binary #:exists 'replace))
    (lambda () (send dc close))))
