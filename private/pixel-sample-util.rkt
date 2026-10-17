#lang racket/base

;;;
;;; Pixel Sample Dispatch
;;;

;; Dispatches sample encoding and decoding to integer or floating-point formats.
;; Provides the common sample interface used by raster-buffer operations.

(require "check.rkt" "integer-pixel-util.rkt" "float-pixel-util.rkt" "../image-info.rkt")
(provide pixel-sample->bytes pixel-bytes->sample pixel-black-sample
         pixel-storage-input pixel-tight-input pixel-sample-alpha/8)
; pixel-sample->bytes : symbol? image-info? any/c -> bytes?
;;   Encodes a logical sample using the integer or floating storage family selected by image-info.
(define (pixel-sample->bytes who info sample)
  ((if (float-info? info) float-sample->bytes integer-sample->bytes) who info sample))
; pixel-bytes->sample : symbol? image-info? bytes? [exact-nonnegative-integer?] -> vector?
;;   Decodes one stored pixel through the format's integer or floating implementation.
(define (pixel-bytes->sample who info data [offset 0])
  ((if (float-info? info) float-bytes->sample integer-bytes->sample) who info data offset))
; pixel-black-sample : image-info? -> vector?
;;   Produces format-appropriate black with alpha consistent with the image description.
(define (pixel-black-sample info)
  ((if (float-info? info) float-black-sample integer-black-sample) info))
; pixel-sample-alpha/8 : image-info? vector? -> byte?
;;   Converts stored alpha to an 8-bit observation, rounding floating alpha to the nearest byte.
(define (pixel-sample-alpha/8 info sample)
  (if (float-info? info)
      (inexact->exact (floor (+ 0.5 (* 255 (vector-ref sample 3)))))
      (integer-sample-alpha info sample)))
; pixel-storage-input : symbol? image-info? bytes? integer? [#:full? boolean?] -> bytes?
;;   Snapshots strided integer or float storage and validates every pixel before any destination
;;   write.
(define (pixel-storage-input who info data rb #:full? [full? #f])
  (cond
    [(not (float-info? info)) (integer-storage-input who info data rb #:full? full?)]
    [else
     (unless (bytes? data) (raise-argument-error who "bytes?" data))
     (define-values (_ minimum allocation) (image-info-storage-layout info #:row-bytes rb))
     (unless (and (if full? (= (bytes-length data) allocation) (<= minimum (bytes-length data)))
                  (<= (bytes-length data) (current-skia-byte-limit)))
       (error who "float storage input is truncated, nonexact, or exceeds the byte limit"))
     (define copied (bytes-copy data))
     (define bpp (image-info-bytes-per-pixel info))
     (for* ([y (in-range (image-info-height info))] [x (in-range (image-info-width info))])
       (float-bytes->sample who info copied (+ (* y rb) (* x bpp))))
     copied]))
; pixel-tight-input : symbol? image-info? bytes? integer? -> bytes?
;;   Copies validated logical rows into packed storage, excluding row padding.
(define (pixel-tight-input who info data rb)
  (define copied (pixel-storage-input who info data rb))
  (define tight (image-info-min-row-bytes info))
  (define out (make-bytes (* tight (image-info-height info))))
  (for ([y (in-range (image-info-height info))])
    (bytes-copy! out (* y tight) copied (* y rb) (+ (* y rb) tight)))
  out)
