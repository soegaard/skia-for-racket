#lang racket/base
;; Run from the source checkout: racket examples/dc-consumers.rkt [directory]
;; These are direct public clients of skia-dc%, not rasterized replacements.
(require racket/class racket/cmdline racket/file
         "../dc.rkt" "../tests/dc-consumer-fixtures.rkt")
(module+ main
  (define directory "output/dc-consumers")
  (command-line #:args ([path directory]) (set! directory path))
  (make-directory* directory)
  (for ([kind (in-list '(pict plot))])
    (define dc (new skia-dc% [width consumer-width] [height consumer-height]
                   [smoothing 'smoothed]))
    (dynamic-wind void
      (lambda ()
        (send dc clear)
        (case kind [(pict) (draw-consumer-pict dc (make-consumer-pict dc))]
                   [(plot) (draw-consumer-plot dc)])
        (call-with-output-file (build-path directory (format "~a.png" kind))
          (lambda (out) (write-bytes (send dc get-png-bytes) out))
          #:mode 'binary #:exists 'replace))
      (lambda () (send dc close)))))
