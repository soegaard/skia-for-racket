#lang racket/base

;;;
;;; Streams Example
;;;

;; Demonstrates native memory-stream ownership transfer, duplication, and reading.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require "../main.rkt")
(provide stream-roundtrip-example)
;;;
;;; Drawing Data and Helpers
;;;

; stream-roundtrip-example : -> (values any/c any/c)
;   Returns both the complete copied stream bytes and the suffix after skipping input.
(define (stream-roundtrip-example)
  (with-skia ([out (make-memory-output-stream #:limit 1024)])
    (output-stream-write-bytes! out #"Native stream / Racket bytes")
    (with-skia ([in (output-stream-detach-input! out)]
                [copy (input-stream-duplicate in)])
      (input-stream-skip! in 7)
      (values (input-stream->bytes copy) (input-stream->bytes in)))))
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; (whole suffix) : (values any/c any/c)
  ;   Receives the detached full byte string and the suffix from the stream example.
  (define-values (whole suffix) (stream-roundtrip-example))
  (unless (and (bytes=? whole #"Native stream / Racket bytes")
               (bytes=? suffix #"stream / Racket bytes"))
    (error 'streams "roundtrip failed"))
  (displayln "stream-example: passed"))
