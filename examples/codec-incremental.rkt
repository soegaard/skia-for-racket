#lang racket/base
;; Native incremental PNG, supplied a complete encoded chunk at a time. The
;; production API also accepts arbitrary fragments and handles framing itself.
(require racket/list "../main.rkt" "../tests/codec-incremental-fixtures.rkt")
(with-skia ([decoder (make-codec-incremental #:limit (* 1024 1024))])
  (define parts (incremental-fixture-parts))
  (codec-incremental-feed! decoder (car parts))
  (for ([part (in-list (cdr parts))] [i (in-naturals 1)])
    (codec-incremental-feed! decoder part #:final? (= i (sub1 (length parts))))
    (define progress (codec-incremental-step! decoder))
    (printf "~a; native result ~a; initialized rows ~a\n"
            (incremental-progress-state progress) (incremental-progress-result progress)
            (incremental-progress-initialized-rows progress)))
  (unless (eq? (codec-incremental-state decoder) 'complete)
    (error 'codec-incremental-example "decoder did not complete"))
  (with-skia ([pixels (incremental-snapshot->raster-buffer (codec-incremental-snapshot decoder))])
    (unless (bytes=? (raster-buffer->rgba-bytes pixels) (incremental-fixture-pixels))
      (error 'codec-incremental-example "pixels differ")))
  (displayln "Native incremental decoding passed; no one-shot fallback."))
