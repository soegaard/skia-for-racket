#lang racket/base

;;;
;;; Live Streams Example
;;;

;; Copies between native streams and Racket ports while respecting borrowed ownership.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require "../main.rkt")
;; Native-to-port publication. Ports are borrowed unless #:close? #t is selected.
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; destination : output-port?
  ;   Selects the destination used by this example's output.
  (define destination (open-output-bytes))

  ; count : exact-nonnegative-integer?
  ;   Records the number of bytes transferred from the borrowed input port.
  (define count (copy-port/streaming (open-input-bytes #"native streaming") destination))
  (unless (and (= count 16) (bytes=? (get-output-bytes destination) #"native streaming"))
    (error 'example "unexpected streamed copy"))

  ; page : output-page?
  ;   Describes the page drawing and its export dimensions.
  (define page
    (make-output-page 64 48
      (lambda (c) (with-skia ([p (make-paint #:color 'red)]) (draw-rect c 8 8 24 16 p)))
      #:background 'white))

  ; pdf : output-port?
  ;   Keeps the output byte port that receives the streamed PDF document.
  (define pdf (open-output-bytes))
  (output->port page pdf 'pdf)
  (unless (regexp-match? #rx#"^%PDF" (get-output-bytes pdf)) (error 'example "PDF was not published"))
  (displayln "Live stream example passed"))
