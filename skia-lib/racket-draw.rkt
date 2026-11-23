#lang racket/base

;;;
;;; Racket Draw Value Conversion
;;;

;; Copies bitmaps, colors, and paths between Racket draw values and Skia values.
;; This opt-in interoperability boundary preserves detached-copy semantics instead of silently
;; sharing native resources between drawing libraries.

;;;
;;; Imports and Exports
;;;


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

;;;
;;; Bitmap Snapshots
;;;

; bitmap->image : (is-a?/c draw:bitmap%) [#:resolution (or/c 'physical 'logical)] [#:mask (or/c
;   'loaded #f (is-a?/c draw:bitmap%))] -> image?
;   Returns an owned, CPU-resident, untagged Skia image containing a snapshot of the public pixels
;   of bitmap.
(define (bitmap->image bitmap #:resolution [resolution 'physical] #:mask [mask 'loaded])
  (define data (racket-draw-bitmap-snapshot 'bitmap->image bitmap resolution mask))
  (rgba-bytes->image (racket-draw-bitmap-data-width data)
                     (racket-draw-bitmap-data-height data)
                     (racket-draw-bitmap-data-pixels data)
                     #:premultiplied? #t
                     #:color-space #f))

;;;
;;; Color Conversion
;;;

; color%->rgba : (is-a?/c draw:color%) -> rgba?
;   Returns an immutable rgba value with the red, green, and blue bytes reported by color.
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

; rgba->color% : rgba? -> (is-a?/c draw:color%)
;   Returns a fresh Racket Draw draw:color% with the same RGB bytes and alpha (/ (rgba-alpha color)
;   255.0).
(define (rgba->color% color)
  (unless (rgba? color) (raise-argument-error 'rgba->color% "rgba?" color))
  (make-object rd:color%
               (rgba-red color) (rgba-green color) (rgba-blue color)
               (/ (rgba-alpha color) 255.0)))

;;;
;;; Path Conversion
;;;

; dc-path->skia-path : (is-a?/c draw:dc-path%) [#:fill-style (or/c 'odd-even 'winding)] ->
;   skia-path?
;   Returns an independently owned Skia path built from the public geometry of path.
(define (dc-path->skia-path path #:fill-style [fill-style 'odd-even])
  (dc-path->skia-path/checked path fill-style))

; skia-path->dc-path : skia-path? [#:conic-subdivisions (or/c #f (integer-in 0 5))] -> (values
;   (is-a?/c draw:dc-path%) (or/c 'odd-even 'winding))
;   Returns two detached values: a fresh Racket Draw draw:dc-path% and the Draw fill style required
;   to preserve the Skia path's fill rule.
(define (skia-path->dc-path path #:conic-subdivisions [power #f])
  (skia-path->dc-path/checked path power))
