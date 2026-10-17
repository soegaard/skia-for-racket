#lang racket/base

;;;
;;; Bitmap Conversion
;;;

;; Copies Skia surfaces and images into Racket bitmap objects.
;; This opt-in bridge connects native rendering results to Racket drawing consumers without exposing
;; native pixel storage.

;;;
;;; Imports and Exports
;;;

(require "main.rkt"
         "private/bitmap-transfer.rkt")
(provide surface->bitmap image->bitmap)

; surface->bitmap : surface? -> (is-a?/c bitmap%)
;   Returns an independent mutable Racket bitmap with an alpha channel.
(define (surface->bitmap s)
  (unless (surface? s) (raise-argument-error 'surface->bitmap "surface?" s))
  (rgba-premul->bitmap (surface-width s) (surface-height s)
                       (surface->rgba-bytes s #:premultiplied? #t)))

; image->bitmap : image? -> (is-a?/c bitmap%)
;   Returns an independent mutable Racket bitmap with an alpha channel.
(define (image->bitmap im)
  (unless (image? im) (raise-argument-error 'image->bitmap "image?" im))
  (rgba-premul->bitmap (image-width im) (image-height im)
                       (image->rgba-bytes im #:premultiplied? #t)))
