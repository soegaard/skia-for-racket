#lang racket/base

;;;
;;; Codec Scanline Fixtures
;;;

;; Provides shared inputs and drawing fixtures for scanline decoding, encoded row order, and
;; cursor ownership.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
;; Original deterministic BMP files, including both signed-height variants.
;; No installed fonts, network assets, or external encoder is needed for BMP.
(require "../main.rkt")
(provide scanline-fixture-width scanline-fixture-height scanline-fixture-rgba
         scanline-fixture-bmp scanline-fixture-truncated-bmp scanline-fixture-png
         scanline-fixture-jpeg scanline-collect-bytes)

;;;
;;; Fixtures and Assertions
;;;

; scanline-fixture-width : exact-positive-integer?
;;   Sets the narrow BMP width chosen to require row padding.
(define scanline-fixture-width 7)

; scanline-fixture-height : exact-positive-integer?
;;   Sets the BMP height used for cursor, skipping, and truncation checks.
(define scanline-fixture-height 5)

; u16 : exact-nonnegative-integer? -> bytes?
;;   Encodes an unsigned 16-bit BMP field in little-endian order.
(define (u16 n) (integer->integer-bytes n 2 #f #f))

; u32 : exact-nonnegative-integer? -> bytes?
;;   Encodes an unsigned 32-bit BMP field in little-endian order.
(define (u32 n) (integer->integer-bytes n 4 #f #f))

; s32 : exact-integer? -> bytes?
;;   Encodes a signed 32-bit BMP field, including negative top-down heights.
(define (s32 n) (integer->integer-bytes n 4 #t #f))

; scanline-fixture-rgba : [exact-positive-integer? exact-positive-integer?] -> bytes?
;;   Builds distinct opaque pixels in canonical top-to-bottom RGBA row order.
(define (scanline-fixture-rgba [w scanline-fixture-width] [h scanline-fixture-height])
  (define out (make-bytes (* w h 4) 255))
  (for* ([y (in-range h)] [x (in-range w)])
    (define at (* 4 (+ x (* y w))))
    (bytes-set! out at (modulo (+ 19 (* 31 x) (* 17 y)) 256))
    (bytes-set! out (+ at 1) (modulo (+ 43 (* 13 x) (* 29 y)) 256))
    (bytes-set! out (+ at 2) (modulo (+ 71 (* 23 x) (* 11 y)) 256)))
  out)

; scanline-fixture-bmp : [#:top-down? boolean?] -> bytes?
;;   Builds a padded BGR24 BMP whose signed height controls encoded row order.
(define (scanline-fixture-bmp #:top-down? [top-down? #f])
  (define w scanline-fixture-width) (define h scanline-fixture-height)
  (define rb (* 4 (quotient (+ (* w 3) 3) 4)))
  (define payload (make-bytes (* rb h) 0))
  (define rgba (scanline-fixture-rgba))
  (for* ([row (in-range h)] [x (in-range w)])
    (define y (if top-down? row (- h row 1)))
    (define src (* 4 (+ (* y w) x)))
    (define dst (+ (* row rb) (* x 3)))
    (bytes-set! payload dst (bytes-ref rgba (+ src 2)))
    (bytes-set! payload (+ dst 1) (bytes-ref rgba (+ src 1)))
    (bytes-set! payload (+ dst 2) (bytes-ref rgba src)))
  (bytes-append #"BM" (u32 (+ 54 (bytes-length payload))) (u32 0) (u32 54)
                (u32 40) (s32 w) (s32 (if top-down? (- h) h)) (u16 1) (u16 24)
                (u32 0) (u32 (bytes-length payload)) (u32 2835) (u32 2835)
                (u32 0) (u32 0) payload))

; scanline-fixture-truncated-bmp : [#:top-down? boolean?] -> bytes?
;;   Retains only two encoded BMP rows to test short-read behavior.
(define (scanline-fixture-truncated-bmp #:top-down? [top-down? #f])
  ;; Two complete encoded rows and no part of a third. Header remains valid.
  (define rb (* 4 (quotient (+ (* scanline-fixture-width 3) 3) 4)))
  (subbytes (scanline-fixture-bmp #:top-down? top-down?) 0 (+ 54 (* 2 rb))))

; scanline-fixture-png : -> bytes?
;;   Encodes the same pattern as PNG for format-dependent scanline checks.
(define (scanline-fixture-png)
  (with-skia ([im (rgba-bytes->image 7 5 (scanline-fixture-rgba))]) (image->png-bytes im)))

; scanline-fixture-jpeg : -> bytes?
;;   Encodes a larger full-quality JPEG pattern without chroma subsampling.
(define (scanline-fixture-jpeg)
  (with-skia ([im (rgba-bytes->image 16 12 (scanline-fixture-rgba 16 12))])
    (image->jpeg-bytes im #:quality 100 #:downsample 'yuv-444)))

; scanline-collect-bytes : codec-scanline? [exact-positive-integer?] -> bytes?
;;   Collects complete batches into their logical row positions, rejecting unexpected short reads.
(define (scanline-collect-bytes decoder [batch-size 2])
  ;; Reference placement uses public batch first-row, not the native cursor.
  (define info (codec-scanline-info decoder))
  (define w (image-info-width info)) (define h (image-info-height info))
  (define row (* w (image-info-bytes-per-pixel info)))
  (define out (make-bytes (* row h) 0))
  (let loop ()
    (when (codec-scanline-next-row decoder)
      (define n (min batch-size (- h (codec-scanline-position decoder))))
      (define batch (codec-scanline-read! decoder n))
      (unless (scanline-batch-complete? batch)
        (error 'scanline-fixture "unexpected short native read"))
      (bytes-copy! out (* row (scanline-batch-first-row batch)) (scanline-batch-bytes batch))
      (loop)))
  out)
