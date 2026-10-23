#lang racket/base

;;;
;;; Bitmap Conversion
;;;

;; Copies Skia surfaces and images into Racket bitmap objects.
;; This opt-in bridge connects native rendering results to Racket drawing consumers without exposing
;; native pixel storage.

(require "main.rkt"
         "private/bitmap-transfer.rkt" "private/bitmap-display.rkt")
(provide surface->bitmap image->bitmap)

; surface->bitmap : surface? -> (is-a?/c bitmap%)
;   Returns an independent mutable Racket bitmap with an alpha channel.
(define (surface->bitmap s)
  (unless (surface? s) (raise-argument-error 'surface->bitmap "surface?" s))
  (with-skia ([image (surface-snapshot s)])
    (image->bitmap image)))

; image->bitmap : image? -> (is-a?/c bitmap%)
;   Returns an independent mutable Racket bitmap with an alpha channel.
(define (image->bitmap im)
  (unless (image? im) (raise-argument-error 'image->bitmap "image?" im))
  (rgba-premul->bitmap (image-width im) (image-height im)
                       (image->display-rgba-bytes im)))
