#lang racket/base

;; Explicit snapshot interoperability with ordinary Racket Draw objects. This
;; module is intentionally opt-in: main.rkt neither imports nor re-exports it.
(require racket/class
         (prefix-in rd: racket/draw)
         "bitmap.rkt"
         "color.rkt"
         "private/check.rkt"
         "private/core.rkt"
         "private/racket-draw-bitmap.rkt"
         "private/racket-draw-path.rkt")

(provide bitmap->image
         image->bitmap surface->bitmap
         color%->rgba rgba->color%
         dc-path->skia-path skia-path->dc-path)

(define (bitmap->image bitmap #:resolution [resolution 'physical] #:mask [mask 'loaded])
  (define data (racket-draw-bitmap-snapshot 'bitmap->image bitmap resolution mask))
  (rgba-bytes->image (racket-draw-bitmap-data-width data)
                     (racket-draw-bitmap-data-height data)
                     (racket-draw-bitmap-data-pixels data)
                     #:premultiplied? #t
                     #:color-space #f))

(define (color%->rgba color)
  (define who 'color%->rgba)
  (unless (is-a? color rd:color%)
    (raise-argument-error who "color% object" color))
  (define red (send color red))
  (define green (send color green))
  (define blue (send color blue))
  (unless (and (byte? red) (byte? green) (byte? blue))
    (raise-arguments-error who "color% supplied invalid RGB components" "color" color))
  (define alpha (scalar who (send color alpha)))
  (unless (<= 0 alpha 1)
    (raise-arguments-error who "color% alpha must be in [0,1]" "alpha" alpha))
  (rgba red green blue (inexact->exact (round (* 255 alpha)))))

(define (rgba->color% color)
  (unless (rgba? color) (raise-argument-error 'rgba->color% "rgba?" color))
  (make-object rd:color%
               (rgba-red color) (rgba-green color) (rgba-blue color)
               (/ (rgba-alpha color) 255.0)))

(define (dc-path->skia-path path #:fill-style [fill-style 'odd-even])
  (dc-path->skia-path/checked path fill-style))

(define (skia-path->dc-path path #:conic-subdivisions [power #f])
  (skia-path->dc-path/checked path power))
