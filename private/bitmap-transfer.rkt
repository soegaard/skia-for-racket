#lang racket/base

;; The Racket bitmap API consumes premultiplied ARGB.  Skia's CPU readback
;; path supplies premultiplied RGBA, so bridges share this small, detached
;; channel-order conversion without involving PNG encoding or native state.
(require racket/class
         (only-in racket/draw make-bitmap))

(provide rgba-premul->argb rgba-premul->bitmap)

(define (rgba-premul->argb pixels)
  (define argb (make-bytes (bytes-length pixels)))
  (for ([i (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! argb i (bytes-ref pixels (+ i 3)))
    (bytes-set! argb (+ i 1) (bytes-ref pixels i))
    (bytes-set! argb (+ i 2) (bytes-ref pixels (+ i 1)))
    (bytes-set! argb (+ i 3) (bytes-ref pixels (+ i 2))))
  argb)

(define (rgba-premul->bitmap width height pixels)
  (define bitmap (make-bitmap width height #t))
  ;; Both buffers use premultiplied alpha. Only channel order is changed.
  (send bitmap set-argb-pixels 0 0 width height (rgba-premul->argb pixels) #f #t)
  bitmap)
