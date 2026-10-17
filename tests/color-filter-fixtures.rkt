#lang racket/base

;;;
;;; Color Filter Fixtures
;;;

;; Provides shared inputs and drawing fixtures for HSLA, gamma, lookup-table, and composed color
;; filters.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt")
(provide identity-hsla hue-third-hsla saturation-zero-hsla lightness-invert-hsla
         identity-table inverse-table threshold-table filter-swatch-color
         make-probe-color-filter filter-pixel rgba-list)

;;;
;;; Fixtures and Assertions
;;;

; identity-hsla : (listof real?)
;;   Stores a row-major 4-by-5 HSLA identity matrix with normalized channel offsets.
(define identity-hsla '(1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0))

; hue-third-hsla : (listof real?)
;;   Adds one third of a hue turn while preserving saturation, lightness, and alpha.
(define hue-third-hsla '(1 0 0 0 1/3  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0))

; saturation-zero-hsla : (listof real?)
;;   Zeros HSL saturation without altering lightness or alpha.
(define saturation-zero-hsla '(1 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0))

; lightness-invert-hsla : (listof real?)
;;   Maps normalized HSL lightness to one minus lightness.
(define lightness-invert-hsla '(1 0 0 0 0  0 1 0 0 0  0 0 -1 0 1  0 0 0 1 0))

; identity-table : bytes?
;;   Maps all 256 channel values to themselves.
(define identity-table (bytes->immutable-bytes (apply bytes (build-list 256 values))))

; inverse-table : bytes?
;;   Maps each byte channel value to 255 minus that value.
(define inverse-table (bytes->immutable-bytes (apply bytes (build-list 256 (lambda (x) (- 255 x))))))

; threshold-table : bytes?
;;   Maps values below 128 to zero and the remaining values to 255.
(define threshold-table
  (bytes->immutable-bytes (apply bytes (build-list 256 (lambda (x) (if (< x 128) 0 255))))))

; filter-swatch-color : rgba?
;;   Supplies distinct opaque channels for color-filter comparisons.
(define filter-swatch-color (rgba 72 144 216 255))

; rgba-list : rgba? -> (listof byte?)
;;   Extracts red, green, blue, and alpha channels in that order.
(define (rgba-list c) (list (rgba-red c) (rgba-green c) (rgba-blue c) (rgba-alpha c)))

; filter-pixel : color-filter? color? -> rgba?
;;   Renders a filtered solid swatch and samples its center pixel.
(define (filter-pixel cf color)
  (with-skia ([s (make-surface 3 3)]
              [p (make-paint #:color color #:color-filter cf #:antialias? #f)])
    (draw-rect (surface-canvas s) 0 0 3 3 p)
    (surface-pixel s 1 1)))
;; These constructors are shared by the combined visual registry and doctor.
;; No native objects are allocated when this module is required.

; make-probe-color-filter : symbol? -> color-filter?
;;   Creates the named filter fixture, retaining composed children before their wrappers close.
(define (make-probe-color-filter name)
  (case name
    [(identity) (make-hsla-matrix-filter identity-hsla)]
    [(hue) (make-hsla-matrix-filter hue-third-hsla)]
    [(desaturate) (make-hsla-matrix-filter saturation-zero-hsla)]
    [(lighting) (make-lighting-color-filter (rgb 180 255 140) (rgb 30 0 20))]
    [(encode) (make-linear-to-srgb-gamma-color-filter)]
    [(decode) (make-srgb-to-linear-gamma-color-filter)]
    [(rgb-table)
      (make-table-argb-color-filter #:red inverse-table #:green inverse-table #:blue inverse-table)]
    [(threshold)
      (make-table-argb-color-filter #:red threshold-table #:green threshold-table #:blue
        threshold-table)]
    [(luma) (make-luma-color-filter)]
    [(contrast)
      (make-high-contrast-color-filter #:grayscale? #t #:invert-style 'lightness #:contrast 0.25)]
    [(lerp)
     (with-skia ([a (make-probe-color-filter 'identity)] [b (make-probe-color-filter 'rgb-table)])
       (make-lerp-color-filter 0.35 a b))]
    [(compose)
     (with-skia ([a (make-probe-color-filter 'encode)] [b (make-probe-color-filter 'decode)])
       (make-compose-color-filter b a))]
    [else (raise-argument-error 'make-probe-color-filter "known probe filter name" name)]))
