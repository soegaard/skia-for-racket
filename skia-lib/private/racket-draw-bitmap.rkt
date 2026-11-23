#lang racket/base

;;;
;;; Racket Bitmap Conversion
;;;

;; Copies bitmap pixels, alpha, masks, and backing-scale information.
;; Bridges racket/draw bitmap values to Skia image construction.


;; Public bitmap% snapshots for skia/racket-draw.  This is deliberately
;; independent of the DC bitmap renderer: a neutral image import must not
;; inherit a drawing context's foreground/background or monochrome style.

;;;
;;; Imports and Exports
;;;

(require racket/class
         (prefix-in rd: racket/draw)
         "check.rkt"
         "dc-support.rkt")

(provide (struct-out racket-draw-bitmap-data)
         racket-draw-bitmap-snapshot)

;;;
;;; Detached Pixels and Capture Validation
;;;

(struct racket-draw-bitmap-data (width height pixels) #:transparent)
;; Fields:
;;   width and height: positive exact pixel dimensions at the requested physical or logical
;;   resolution. pixels: detached premultiplied RGBA bytes, tightly packed left-to-right then
;;   top-to-bottom, exactly 4 * width * height bytes after mask coverage is applied. Each RGB
;;   component is at most alpha, and zero alpha has zero RGB; no bitmap or mask is retained.


; mul255 : byte? byte? -> byte?
;   Multiplies a premultiplied component by mask coverage with nearest-integer rounding.
(define (mul255 component coverage)
  (quotient (+ (* component coverage) 127) 255))

; positive-bitmap-dimensions : symbol? (is-a?/c bitmap%) -> (values exact-positive-integer?
; exact-positive-integer?)
;   Reads and validates the bitmap's logical dimensions before any backing-scale conversion.
(define (positive-bitmap-dimensions who bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error who "bitmap has invalid logical dimensions"
                           "width" width "height" height))
  (values width height))

; bitmap-spec : symbol? (is-a?/c bitmap%) symbol? -> (values exact-positive-integer?
; exact-positive-integer? real? exact-positive-integer? exact-positive-integer? boolean?)
;   Returns selected pixel width/height, backing scale, logical width/height, and the unscaled-read
;   flag for physical or logical resolution.
(define (bitmap-spec who bitmap resolution)
  (unless (is-a? bitmap rd:bitmap%)
    (raise-argument-error who "bitmap% object" bitmap))
  (unless (send bitmap ok?)
    (raise-arguments-error who "bitmap is not usable" "bitmap" bitmap))
  (define-values (logical-width logical-height) (positive-bitmap-dimensions who bitmap))
  (define backing (dc-real who (send bitmap get-backing-scale)))
  (unless (> backing 0)
    (raise-arguments-error who "bitmap has invalid backing scale"
                           "backing scale" backing))
  (define physical-width (inexact->exact (ceiling (dc-real who (* logical-width backing)))))
  (define physical-height (inexact->exact (ceiling (dc-real who (* logical-height backing)))))
  (define-values (width height unscaled?)
    (case resolution
      [(physical) (values physical-width physical-height #t)]
      [(logical) (values logical-width logical-height #f)]
      [else (raise-argument-error who "'physical or 'logical" resolution)]))
  (check-dimensions who width height)
  (values width height backing logical-width logical-height unscaled?))

; read-argb : (is-a?/c bitmap%) exact-positive-integer? exact-positive-integer? boolean? boolean? ->
; bytes?
;   Copies premultiplied ARGB or alpha-mask pixels at the selected logical/physical read resolution.
(define (read-argb bitmap width height just-alpha? unscaled?)
  (define result (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height result just-alpha? #t
        #:unscaled? unscaled?)
  result)

; resolve-mask : symbol? (is-a?/c bitmap%) (or/c #f 'loaded (is-a?/c bitmap%)) -> (or/c #f (is-a?/c
; bitmap%))
;   Resolves one explicitly selected or loaded mask and validates it without recursively following
;   loaded masks.
(define (resolve-mask who bitmap mask)
  (define resolved
    (cond [(eq? mask 'loaded) (send bitmap get-loaded-mask)]
          [(not mask) #f]
          [(is-a? mask rd:bitmap%) mask]
          [else (raise-argument-error who "'loaded, #f, or bitmap% object" mask)]))
  (when resolved
    (unless (send resolved ok?)
      (raise-arguments-error who "mask bitmap is not usable" "mask" resolved)))
  resolved)

; checked-budget : symbol? exact-positive-integer? exact-positive-integer? exact-nonnegative-integer?
; exact-nonnegative-integer? -> void?
;   Bounds source ARGB, result RGBA, native construction allowance, and optional mask-copy storage
;   before allocation.
(define (checked-budget who source-width source-height mask-width mask-height)
  ;; Source ARGB, final RGBA, an image-sized construction allowance, and an
  ;; optional mask ARGB buffer coexist. This is an admission check, not a
  ;; process-memory claim about Racket Draw or Skia internals.
  (define bytes (+ (* 12 source-width source-height)
                   (if mask-width (* 4 mask-width mask-height) 0)))
  (unless (<= bytes (current-skia-byte-limit))
    (raise-arguments-error who "bitmap bridge exceeds current-skia-byte-limit"
                           "temporary bytes" bytes
                           "limit" (current-skia-byte-limit))))

;;;
;;; Masked Premultiplied Pixel Capture
;;;

; racket-draw-bitmap-snapshot : symbol? (is-a?/c bitmap%) symbol? (or/c #f 'loaded (is-a?/c bitmap%))
; -> racket-draw-bitmap-data?
;   Copies checked premultiplied RGBA pixels, scaling optional mask sampling across unequal backing
;   scales and canonicalizing transparent RGB.
(define (racket-draw-bitmap-snapshot who bitmap resolution mask)
  (define-values (width height backing logical-width logical-height unscaled?)
    (bitmap-spec who bitmap resolution))
  (define resolved-mask (resolve-mask who bitmap mask))
  (define-values (mask-width mask-height mask-backing mask-logical-width mask-logical-height
                              mask-unscaled?)
    (if resolved-mask
        (bitmap-spec who resolved-mask resolution)
        (values #f #f #f #f #f #f)))
  (when resolved-mask
    (unless (and (= logical-width mask-logical-width)
                 (= logical-height mask-logical-height))
      (raise-arguments-error who "mask must match source logical dimensions"
                             "source dimensions" (list logical-width logical-height)
                             "mask dimensions" (list mask-logical-width mask-logical-height))))
  (checked-budget who width height mask-width mask-height)
  (define source-argb (read-argb bitmap width height #f unscaled?))
  ;; A mask's documented alpha-only readback supplies its coverage semantics,
  ;; including the black/white interpretation of alpha-free masks. A mask's
  ;; own loaded mask is intentionally not expanded recursively.
  (define mask-argb
    (and resolved-mask
         (read-argb resolved-mask mask-width mask-height #t mask-unscaled?)))
  (define rgba (make-bytes (* 4 width height)))
  (for* ([y (in-range height)] [x (in-range width)])
    (define pixel-index (* 4 (+ x (* y width))))
    (define alpha (bytes-ref source-argb pixel-index))
    (define red (bytes-ref source-argb (+ pixel-index 1)))
    (define green (bytes-ref source-argb (+ pixel-index 2)))
    (define blue (bytes-ref source-argb (+ pixel-index 3)))
    (unless (and (<= red alpha) (<= green alpha) (<= blue alpha))
      (raise-arguments-error who "bitmap supplied invalid premultiplied ARGB pixels"
                             "pixel" (list x y)))
    (define coverage
      (if mask-argb
          (let* ([mask-x
                  (if (eq? resolution 'logical)
                      x
                      (min (sub1 mask-width)
                           (inexact->exact
                            (floor (* (+ x 0.5) (/ mask-backing backing))))))]
                 [mask-y
                  (if (eq? resolution 'logical)
                      y
                      (min (sub1 mask-height)
                           (inexact->exact
                            (floor (* (+ y 0.5) (/ mask-backing backing))))))]
                 [mask-index (* 4 (+ mask-x (* mask-y mask-width)))])
            (bytes-ref mask-argb mask-index))
          255))
    (define final-alpha (mul255 alpha coverage))
    ;; Canonicalize hidden RGB when output alpha is zero. This guarantees that
    ;; malformed/hidden source samples never enter the premultiplied Skia path.
    (bytes-set! rgba pixel-index (if (zero? final-alpha) 0 (mul255 red coverage)))
    (bytes-set! rgba (+ pixel-index 1) (if (zero? final-alpha) 0 (mul255 green coverage)))
    (bytes-set! rgba (+ pixel-index 2) (if (zero? final-alpha) 0 (mul255 blue coverage)))
    (bytes-set! rgba (+ pixel-index 3) final-alpha))
  (racket-draw-bitmap-data width height rgba))
