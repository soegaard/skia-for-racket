#lang racket/base
(require "../main.rkt")
;; Native-to-port publication. Ports are borrowed unless #:close? #t is selected.
(module+ main
  (define destination (open-output-bytes))
  (define count (copy-port/streaming (open-input-bytes #"native streaming") destination))
  (unless (and (= count 16) (bytes=? (get-output-bytes destination) #"native streaming"))
    (error 'example "unexpected streamed copy"))
  (define page
    (make-output-page 64 48
      (lambda (c) (with-skia ([p (make-paint #:color 'red)]) (draw-rect c 8 8 24 16 p)))
      #:background 'white))
  (define pdf (open-output-bytes))
  (output->port page pdf 'pdf)
  (unless (regexp-match? #rx#"^%PDF" (get-output-bytes pdf)) (error 'example "PDF was not published"))
  (displayln "Live stream example passed"))
