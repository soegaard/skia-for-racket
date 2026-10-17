#lang racket/base

;;;
;;; Small Gaps Example
;;;

;; Demonstrates linear RGB basis conversion using XYZ-D50 matrices.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; All operations are public. Basis conversion below assumes linear samples;
;; it does not decode transfer functions, clip, tone-map, or convert an image.
;;;
;;; Imports and Exports
;;;

(require "../main.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; srgb : xyz-d50?
;;   Retains the linear sRGB-to-XYZ-D50 basis matrix.
(define srgb (named-xyz-d50 'srgb))
; display-p3 : xyz-d50?
;;   Retains the Display-P3 RGB-to-XYZ-D50 basis matrix.
(define display-p3 (named-xyz-d50 'display-p3))
; from-xyz-to-p3 : (or/c xyz-d50? #f)
;;   Inverts the Display-P3 basis so XYZ-D50 samples can be expressed in linear P3.
(define from-xyz-to-p3 (xyz-d50-invert display-p3))
(unless from-xyz-to-p3 (error 'small-gaps "Display-P3 matrix has no finite inverse"))
; linear-srgb-to-linear-p3 : xyz-d50?
;;   Composes the linear sRGB-to-XYZ and XYZ-to-P3 basis transforms.
(define linear-srgb-to-linear-p3 (xyz-d50-concat from-xyz-to-p3 srgb))
(printf "Linear sRGB -> linear Display-P3 (row-major): ~s\n" linear-srgb-to-linear-p3)
(printf "Singular inverse: ~s\n" (xyz-d50-invert '#(0 0 0 0 0 0 0 0 0)))
(call-with-nodraw-canvas 320 200
  (lambda (canvas)
    (with-canvas-state canvas
      (canvas-translate! canvas 10 20)
      (with-skia ([paint (make-paint #:color (rgb 30 100 180))])
        (draw-rect canvas 0 0 80 40 paint)))
    (printf "Diagnostic backend: ~a; an image surface? ~a\n"
            (canvas-execution-backend canvas) (surface? canvas))))
