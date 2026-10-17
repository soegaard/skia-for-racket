#lang racket/base

;;;
;;; Codec Scanlines Example
;;;

;; Reads a native JPEG decoder in bounded batches of scanlines.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; A public-API-only example. Real native JPEG input, three-row batches.
;;;
;;; Imports and Exports
;;;

(require "../main.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; encoded : bytes?
;   Contains the JPEG input bytes used by the scanline decoder.
(define encoded
  (with-skia ([image (rgba-bytes->image 16 12 (make-bytes (* 16 12 4) 255))])
    (image->jpeg-bytes image #:quality 95)))
(with-skia ([decoder (codec-scanline-from-bytes encoded #:scale 1/2)])
  (define info (codec-scanline-info decoder))
  (printf "Native target: ~ax~a, order ~a\n"
          (image-info-width info) (image-info-height info) (codec-scanline-order decoder))
  (let loop ()
    (when (codec-scanline-next-row decoder)
      (define count (min 3 (- (image-info-height info) (codec-scanline-position decoder))))
      (define batch (codec-scanline-read! decoder count))
      (unless (scanline-batch-complete? batch) (error 'example
        "input ended before all requested rows"))
      (printf "Rows ~a through ~a: ~a decoded bytes\n" (scanline-batch-first-row batch)
              (+ (scanline-batch-first-row batch) (sub1 (scanline-batch-decoded-count batch)))
              (bytes-length (scanline-batch-bytes batch)))
      (loop)))
  (unless (eq? (codec-scanline-state decoder) 'complete) (error 'example
    "incomplete scanline session")))
