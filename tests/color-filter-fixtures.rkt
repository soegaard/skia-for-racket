#lang racket/base
(require "../main.rkt")
(provide identity-hsla hue-third-hsla saturation-zero-hsla lightness-invert-hsla
         identity-table inverse-table threshold-table filter-swatch-color
         make-probe-color-filter filter-pixel rgba-list)
(define identity-hsla '(1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0))
(define hue-third-hsla '(1 0 0 0 1/3  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0))
(define saturation-zero-hsla '(1 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0))
(define lightness-invert-hsla '(1 0 0 0 0  0 1 0 0 0  0 0 -1 0 1  0 0 0 1 0))
(define identity-table (bytes->immutable-bytes (apply bytes (build-list 256 values))))
(define inverse-table (bytes->immutable-bytes (apply bytes (build-list 256 (lambda (x) (- 255 x))))))
(define threshold-table (bytes->immutable-bytes (apply bytes (build-list 256 (lambda (x) (if (< x 128) 0 255))))))
(define filter-swatch-color (rgba 72 144 216 255))
(define (rgba-list c) (list (rgba-red c) (rgba-green c) (rgba-blue c) (rgba-alpha c)))
(define (filter-pixel cf color)
  (with-skia ([s (make-surface 3 3)]
              [p (make-paint #:color color #:color-filter cf #:antialias? #f)])
    (draw-rect (surface-canvas s) 0 0 3 3 p)
    (surface-pixel s 1 1)))
;; These constructors are shared by the combined visual registry and doctor.
;; No native objects are allocated when this module is required.
(define (make-probe-color-filter name)
  (case name
    [(identity) (make-hsla-matrix-filter identity-hsla)]
    [(hue) (make-hsla-matrix-filter hue-third-hsla)]
    [(desaturate) (make-hsla-matrix-filter saturation-zero-hsla)]
    [(lighting) (make-lighting-color-filter (rgb 180 255 140) (rgb 30 0 20))]
    [(encode) (make-linear-to-srgb-gamma-color-filter)]
    [(decode) (make-srgb-to-linear-gamma-color-filter)]
    [(rgb-table) (make-table-argb-color-filter #:red inverse-table #:green inverse-table #:blue inverse-table)]
    [(threshold) (make-table-argb-color-filter #:red threshold-table #:green threshold-table #:blue threshold-table)]
    [(luma) (make-luma-color-filter)]
    [(contrast) (make-high-contrast-color-filter #:grayscale? #t #:invert-style 'lightness #:contrast 0.25)]
    [(lerp)
     (with-skia ([a (make-probe-color-filter 'identity)] [b (make-probe-color-filter 'rgb-table)])
       (make-lerp-color-filter 0.35 a b))]
    [(compose)
     (with-skia ([a (make-probe-color-filter 'encode)] [b (make-probe-color-filter 'decode)])
       (make-compose-color-filter b a))]
    [else (raise-argument-error 'make-probe-color-filter "known probe filter name" name)]))
