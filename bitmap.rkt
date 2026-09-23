#lang racket/base
(require racket/class
         (only-in racket/draw make-bitmap)
         "main.rkt")
(provide surface->bitmap image->bitmap)

(define (rgba->bitmap w h pixels)
  (define argb (make-bytes (bytes-length pixels)))
  (for ([i (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! argb i (bytes-ref pixels (+ i 3)))
    (bytes-set! argb (+ i 1) (bytes-ref pixels i))
    (bytes-set! argb (+ i 2) (bytes-ref pixels (+ i 1)))
    (bytes-set! argb (+ i 3) (bytes-ref pixels (+ i 2))))
  (define bm (make-bitmap w h #t))
  ;; Both buffers use premultiplied alpha. Only channel order is changed.
  (send bm set-argb-pixels 0 0 w h argb #f #t)
  bm)

(define (surface->bitmap s)
  (unless (surface? s) (raise-argument-error 'surface->bitmap "surface?" s))
  (rgba->bitmap (surface-width s) (surface-height s)
                (surface->rgba-bytes s #:premultiplied? #t)))

(define (image->bitmap im)
  (unless (image? im) (raise-argument-error 'image->bitmap "image?" im))
  (rgba->bitmap (image-width im) (image-height im)
                (image->rgba-bytes im #:premultiplied? #t)))
