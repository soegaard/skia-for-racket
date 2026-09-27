#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/color-filter-types.rkt"
         "../tests/color-filter-fixtures.rkt")
(provide color-filter-doctor!)
(define (color-filter-doctor!)
  (unless (= (ctype-sizeof _sk-high-contrast-config) 12)
    (error 'doctor "high-contrast ABI is not 12 bytes"))
  (define config (make-sk-high-contrast-config #t 2 0.25))
  (unless (and (= (ptr-ref config _uint8 0) 1) (= (ptr-ref config _int 1) 2)
               (= (ptr-ref config _float 2) 0.25))
    (error 'doctor "high-contrast ABI offsets disagree"))
  (with-skia ([encode (make-linear-to-srgb-gamma-color-filter)]
              [decode (make-srgb-to-linear-gamma-color-filter)]
              [hue (make-hsla-matrix-filter hue-third-hsla)]
              [luma (make-luma-color-filter)]
              [table (make-table-argb-color-filter #:red inverse-table)]
              [all (make-table-color-filter identity-table)]
              [light (make-lighting-color-filter 'white 'black)]
              [contrast (make-high-contrast-color-filter #:grayscale? #t)]
              [lerp (make-lerp-color-filter 0.5 encode decode)])
    (define enc (rgba-red (filter-pixel encode (rgb 128 128 128))))
    (define dec (rgba-red (filter-pixel decode (rgb 128 128 128))))
    (unless (and (<= 186 enc 190) (<= 53 dec 57)
                 (> (rgba-green (filter-pixel hue 'red)) 250)
                 (equal? (filter-pixel luma 'white) (rgba 0 0 0 255))
                 (equal? (filter-pixel table 'red) (rgb 0 0 0)))
      (error 'doctor "CPU color-filter sample mismatch: encode=~a decode=~a" enc dec))
    (for ([cf (in-list (list all light contrast lerp))])
      (unless (rgba? (filter-pixel cf filter-swatch-color))
        (error 'doctor "CPU color filter did not render")))
    (printf "CPU color filters passed: HSLA, gamma ~a/~a, tables, luma, contrast, lighting, retained lerp; high-contrast=12\n" enc dec)))
(module+ main (color-filter-doctor!))
