#lang racket/base
(require "main.rkt"
         "private/bitmap-transfer.rkt")
(provide surface->bitmap image->bitmap)

(define (surface->bitmap s)
  (unless (surface? s) (raise-argument-error 'surface->bitmap "surface?" s))
  (rgba-premul->bitmap (surface-width s) (surface-height s)
                       (surface->rgba-bytes s #:premultiplied? #t)))

(define (image->bitmap im)
  (unless (image? im) (raise-argument-error 'image->bitmap "image?" im))
  (rgba-premul->bitmap (image-width im) (image-height im)
                       (image->rgba-bytes im #:premultiplied? #t)))
