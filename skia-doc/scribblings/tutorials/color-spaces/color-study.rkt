#lang racket

;;;
;;; Color Study
;;;

;; Builds paired images that distinguish color-space tagging from sample conversion.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)
(provide ramp-bytes make-gray-sample make-color-study draw-color-study
         save-color-study)

;;;
;;; Tagged and Converted Color Samples
;;;

; ramp-bytes : -> bytes?
;   Builds 256 opaque grayscale pixels in tightly packed RGBA order.
(define (ramp-bytes)
  (define pixels (make-bytes (* 256 4)))
  (for ([value (in-range 256)])
    (bytes-copy! pixels (* value 4) (bytes value value value 255)))
  pixels)

; make-gray-sample : (or/c color-space? #f) [byte?] -> image?
;   Constructs gray sample for the example's drawing pipeline.
(define (make-gray-sample color-space [sample 128])
  (rgba-bytes->image 1 1 (bytes sample sample sample 255) #:color-space color-space))

; make-color-study : [byte?] -> list?
;   Constructs color study for the example's drawing pipeline.
(define (make-color-study [sample 128])
  (define srgb (make-srgb-color-space))
  (define linear (make-linear-srgb-color-space))
  (define encoded-gray (make-gray-sample srgb sample))
  (define linear-gray (make-gray-sample linear sample))
  (define converted-gray (image-convert-color-space linear-gray srgb))
  (define samples (ramp-bytes))
  (define encoded-ramp (rgba-bytes->image 256 1 samples #:color-space srgb))
  (define linear-ramp (rgba-bytes->image 256 1 samples #:color-space linear))
  (define converted-ramp (image-convert-color-space linear-ramp srgb))
  ;; Every image displayed by the comparison is now expressed in sRGB.
  (list encoded-gray converted-gray encoded-ramp converted-ramp))

;;;
;;; Comparison Sheet and Export
;;;

; draw-color-study : canvas? list? -> void?
;   Draws the color study component in the current canvas coordinate system.
(define (draw-color-study canvas images)
  (match-define (list encoded-gray converted-gray encoded-ramp converted-ramp) images)
  (define font (make-font #:size 16))
  (define small (make-font #:size 13))
  (define title (make-font #:size 28))
  (define ink (make-paint #:color "#263751"))
  (define source-value (bytes-ref (image->rgba-bytes encoded-gray) 0))
  (define converted-value (bytes-ref (image->rgba-bytes converted-gray) 0))
  (canvas-clear! canvas "#F8F7F3")
  (draw-simple-text canvas "THE NUMBERS NEED A COLOR SPACE" 28 47 title ink)
  (draw-simple-text canvas "Same input bytes. Different meanings. Both previews are sRGB."
                    30 80 small ink)
  (draw-image-rect canvas encoded-gray 30 114 320 115 #:sampling 'nearest)
  (draw-image-rect canvas converted-gray 390 114 320 115 #:sampling 'nearest)
  (draw-simple-text canvas (format "~a interpreted as sRGB" source-value) 30 258 font ink)
  (draw-simple-text canvas (format "~a interpreted as linear sRGB" source-value)
                    390 258 font ink)
  (draw-simple-text canvas (format "sRGB output: ~a" source-value) 30 283 small ink)
  (draw-simple-text canvas (format "Converted sRGB output: ~a" converted-value)
                    390 283 small ink)
  (draw-image-rect canvas encoded-ramp 30 316 680 38 #:sampling 'nearest)
  (draw-simple-text canvas "Equal steps in encoded sRGB" 30 377 small ink)
  (draw-image-rect canvas converted-ramp 30 401 680 38 #:sampling 'nearest)
  (draw-simple-text canvas "Equal steps in linear light, then converted to sRGB" 30 462 small ink))

; save-color-study : -> void?
;   Renders the color study example to the selected output destination.
(define (save-color-study)
  (define srgb (make-srgb-color-space))
  (define profile (color-space->icc-bytes srgb))
  (define images (make-color-study))
  (define surface (make-surface 740 490 #:color-space srgb))
  (draw-color-study (surface-canvas surface) images)
  (save-png surface "color-study.png"
            #:icc-profile profile #:icc-description "Skia color study - sRGB"
            #:exists 'replace)
  (save-image (second images) "converted-gray.png" 'png
              #:icc-profile profile #:icc-description "Converted sRGB sample"
              #:exists 'replace)
  (call-with-output-file "study-srgb.icc"
    (lambda (out) (write-bytes profile out)) #:mode 'binary #:exists 'replace)
  (void))

;;;
;;; Command-Line Entry Point
;;;

(module+ main (save-color-study))
