#lang racket/base

;;;
;;; DC Consumers Example
;;;

;; Runs existing drawing consumers directly against the public Skia drawing context.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Run from the source checkout: racket examples/dc-consumers.rkt [directory]
;; These are direct public clients of skia-dc%, not rasterized replacements.

(require racket/class racket/cmdline racket/file
         "../dc.rkt" "../tests/dc-consumer-fixtures.rkt")

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; directory : string?
  ;   Selects the destination used by this example's output.
  (define directory "output/dc-consumers")
  (command-line #:args ([path directory]) (set! directory path))
  (make-directory* directory)
  (for ([kind (in-list '(pict plot))])
    (call-with-skia-dc consumer-width consumer-height
      (lambda (dc)
        (send dc clear)
        (case kind [(pict) (draw-consumer-pict dc (make-consumer-pict dc))]
                   [(plot) (draw-consumer-plot dc)])
        (call-with-output-file (build-path directory (format "~a.png" kind))
          (lambda (out) (write-bytes (send dc get-png-bytes) out))
          #:mode 'binary #:exists 'replace)))))
