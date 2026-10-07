#lang racket/base
(require "../main.rkt")
(provide stream-roundtrip-example)
(define (stream-roundtrip-example)
  (with-skia ([out (make-memory-output-stream #:limit 1024)])
    (output-stream-write-bytes! out #"Native stream / Racket bytes")
    (with-skia ([in (output-stream-detach-input! out)]
                [copy (input-stream-duplicate in)])
      (input-stream-skip! in 7)
      (values (input-stream->bytes copy) (input-stream->bytes in)))))
(module+ main
  (define-values (whole suffix) (stream-roundtrip-example))
  (unless (and (bytes=? whole #"Native stream / Racket bytes")
               (bytes=? suffix #"stream / Racket bytes"))
    (error 'streams "roundtrip failed"))
  (displayln "stream-example: passed"))
