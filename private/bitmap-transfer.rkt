#lang racket/base

;;;
;;; Bitmap Pixel Transfer
;;;

;; Converts premultiplied RGBA storage to and from racket/draw ARGB byte order.
;; Bridges Skia raster output and Racket bitmap presentation.


;; The Racket bitmap API consumes premultiplied ARGB.  Skia's CPU readback
;; path supplies premultiplied RGBA, so bridges share this small, detached
;; channel-order conversion without involving PNG encoding or native state.

;;;
;;; Imports and Exports
;;;

(require racket/class
         (only-in racket/draw make-bitmap))

(provide rgba-premul->argb argb-premul->rgba rgba-premul->bitmap)

;;;
;;; Channel Order and Bitmap Construction
;;;

; rgba-premul->argb : bytes? -> bytes?
;   Copies four-byte premultiplied RGBA pixels into ARGB order; the length must be divisible by four.
(define (rgba-premul->argb pixels)
  (define argb (make-bytes (bytes-length pixels)))
  (for ([i (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! argb i (bytes-ref pixels (+ i 3)))
    (bytes-set! argb (+ i 1) (bytes-ref pixels i))
    (bytes-set! argb (+ i 2) (bytes-ref pixels (+ i 1)))
    (bytes-set! argb (+ i 3) (bytes-ref pixels (+ i 2))))
  argb)

; argb-premul->rgba : bytes? -> bytes?
;   Copies four-byte premultiplied ARGB pixels into RGBA order without changing their alpha values.
(define (argb-premul->rgba pixels)
  (define rgba (make-bytes (bytes-length pixels)))
  (for ([i (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! rgba i (bytes-ref pixels (+ i 1)))
    (bytes-set! rgba (+ i 1) (bytes-ref pixels (+ i 2)))
    (bytes-set! rgba (+ i 2) (bytes-ref pixels (+ i 3)))
    (bytes-set! rgba (+ i 3) (bytes-ref pixels i)))
  rgba)

; rgba-premul->bitmap : exact-positive-integer? exact-positive-integer? bytes? -> (is-a?/c bitmap%)
;   Creates an alpha bitmap from a tightly packed width-by-height premultiplied RGBA buffer.
(define (rgba-premul->bitmap width height pixels)
  (define bitmap (make-bitmap width height #t))
  ;; Both buffers use premultiplied alpha. Only channel order is changed.
  (send bitmap set-argb-pixels 0 0 width height (rgba-premul->argb pixels) #f #t)
  bitmap)
