#lang racket/base

;;;
;;; Pict Conversion Geometry
;;;

;; Checks image and picture dimensions, backing scales, and scratch budgets.
;; Supports the project's conversion between Skia resources and Racket picts.


;; Pure geometry and allocation checks for skia/pict.  Keeping these separate
;; lets the public bridge validate options without loading Skia or GUI support.
(require racket/vector
         "check.rkt")

(provide checked-backing-scale
         checked-image-pict-geometry
         checked-picture-pict-geometry
         checked-picture-bounds)

; positive-float : symbol? real? string? -> real?
;   Checks that a positive value remains positive as a native scalar, preserving the original value
;   for logical geometry.
(define (positive-float who value description)
  (define converted (scalar who value))
  (unless (> converted 0.0)
    (raise-argument-error who description value))
  value)

; checked-backing-scale : symbol? real? -> real?
;   Checks the positive backing scale used to translate physical image pixels to pict units.
(define (checked-backing-scale who value)
  (positive-float who value "positive finite real representable as a C float"))

; check-scratch-space : symbol? exact-positive-integer? exact-positive-integer? ->
;   exact-positive-integer?
;   Checks the combined RGBA and ARGB scratch allocation, returning the byte count of one pixel
;   copy.
(define (check-scratch-space who width height)
  ;; check-dimensions preserves the established individual RGBA-buffer limit.
  ;; This bridge holds that buffer and its ARGB copy at the same time.
  (define rgba-bytes (check-dimensions who width height))
  (define required (* 2 rgba-bytes))
  (unless (<= required (current-skia-byte-limit))
    (raise-arguments-error who
                           "pict bridge exceeds current-skia-byte-limit"
                           "required RGBA and ARGB bytes" required
                           "limit" (current-skia-byte-limit)))
  rgba-bytes)

; checked-image-pict-geometry : symbol? exact-positive-integer? exact-positive-integer? real? ->
;   (values real? real?)
;   Returns logical pict width and height after validating physical dimensions, scratch space, and
;   backing scale.
(define (checked-image-pict-geometry who width height backing-scale)
  (define backing (checked-backing-scale who backing-scale))
  (check-scratch-space who width height)
  (define logical-width (/ width backing))
  (define logical-height (/ height backing))
  (positive-float who logical-width "positive finite logical width representable as a C float")
  (positive-float who logical-height "positive finite logical height representable as a C float")
  (values logical-width logical-height))

; checked-picture-bounds : symbol? any/c real? real? -> vector?
;   Copies explicit x/y/width/height bounds, or uses the default origin and dimensions; validates
;   positive extents and native-coordinate endpoints.
(define (checked-picture-bounds who bounds default-width default-height)
  (define values
    (cond
      [(not bounds) (vector 0 0 default-width default-height)]
      [(and (vector? bounds) (= (vector-length bounds) 4)) (vector-copy bounds)]
      [else (raise-argument-error who "#f or a four-element vector" bounds)]))
  (define x (vector-ref values 0))
  (define y (vector-ref values 1))
  (define width (vector-ref values 2))
  (define height (vector-ref values 3))
  (scalar who x)
  (scalar who y)
  (positive-float who width "positive finite bounds width representable as a C float")
  (positive-float who height "positive finite bounds height representable as a C float")
  ;; Check the actual rectangle edge rather than allowing overflow to be hidden
  ;; in a later canvas operation.
  (scalar who (+ x width))
  (scalar who (+ y height))
  (vector-immutable x y width height))

; checked-raster-dimension : symbol? real? real? string? -> exact-positive-integer?
;   Checks a scaled raster extent and requires its ceiling to be an exact positive pixel count.
(define (checked-raster-dimension who value scale description)
  (define product (* value scale))
  (positive-float who product description)
  (define pixels (ceiling product))
  (unless (exact-positive-integer? pixels)
    (raise-arguments-error who "raster dimension is not a positive exact integer"
                           "value" value "scale" scale))
  pixels)

; checked-picture-pict-geometry : symbol? vector? real? -> (values exact-positive-integer?
;   exact-positive-integer? real? real?)
;   Returns pixel width, pixel height, logical width, and logical height after checking scratch
;   allocation and the raster transform.
(define (checked-picture-pict-geometry who bounds raster-scale)
  (define scale (checked-backing-scale who raster-scale))
  (define x (vector-ref bounds 0))
  (define y (vector-ref bounds 1))
  (define width (vector-ref bounds 2))
  (define height (vector-ref bounds 3))
  (define pixel-width
    (checked-raster-dimension
     who width scale "positive finite raster width representable as a C float"))
  (define pixel-height
    (checked-raster-dimension
     who height scale "positive finite raster height representable as a C float"))
  (check-scratch-space who pixel-width pixel-height)
  (define scale-x (/ pixel-width width))
  (define scale-y (/ pixel-height height))
  (positive-float who scale-x "positive finite picture X transform representable as a C float")
  (positive-float who scale-y "positive finite picture Y transform representable as a C float")
  ;; Scaling is applied before translation, so validate the effective pixel
  ;; translations too. This rejects an otherwise finite bounds rectangle that
  ;; would overflow the destination transform.
  (scalar who (* (- x) scale-x))
  (scalar who (* (- y) scale-y))
  (values pixel-width pixel-height width height))
