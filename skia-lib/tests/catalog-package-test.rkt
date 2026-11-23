#lang racket/base

;; Always runs in DrDr on supported installations. The known font is original
;; project-generated data. Multilingual Noto coverage belongs to skia-doc.
(require rackunit racket/class racket/list racket/path
         (prefix-in draw: racket/draw) (prefix-in pict: pict)
         "../main.rkt" "../bitmap.rkt" "../pict.rkt"
         "../private/native-loader.rkt" "../private/harfbuzz-native.rkt"
         "typeface-fixtures.rkt")

(module+ test
  (test-case "the qualified installed native route selects a paired payload"
    (skia-check!) (harfbuzz-check!)
    (unless (or (getenv "RACKET_SKIA_LIBRARY") (getenv "RACKET_HARFBUZZ_LIBRARY"))
      (define expected (if (eq? (system-type 'os) 'windows) "upstream-download" "managed"))
      (check-equal? (hash-ref (hash-ref (native-library-report) 'loader) 'origin) expected)
      (check-equal? (hash-ref (harfbuzz-library-report) 'origin) expected))
    (check-equal? (skia-native-version) "119.0")
    (check-equal? (harfbuzz-native-version) "8.3.1"))
  (test-case "asymmetric raster and lossless PNG preserve exact interior pixels"
    (with-skia ([s (make-surface 9 7 #:background (rgb 7 11 17))]
                [paint (make-paint #:color (rgb 231 53 79))])
      (draw-rect (surface-canvas s) 1 2 4 3 paint)
      (check-equal? (surface-pixel s 2 3) (rgb 231 53 79))
      (check-equal? (surface-pixel s 8 0) (rgb 7 11 17))
      (with-skia ([im (image-from-bytes (surface->png-bytes s))])
        (check-equal? (image->rgba-bytes im) (surface->rgba-bytes s)))))
  (test-case "HarfBuzz shapes the licensed original AV fixture"
    (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
                [font (make-font face #:size 20)] [shaper (make-shaper font)])
      (define run (shape-text shaper "AV"))
      (check-equal? (shaped-run-glyphs run) '#(2 3))
      (check-true (> (shaped-run-advance-x run) 0))))
  (test-case "path and vector document output execute on CPU"
    (with-skia ([p (make-path '((move 1 1) (line 10 1) (line 5 8) (close)))]
                [paint (make-paint #:color 'red)])
      (define (draw c) (draw-path c p paint))
      (check-true (path-contains? p 5 3))
      (define svg (call-with-svg-bytes 16 12 draw))
      (check-true (regexp-match? #rx#"<svg" svg))
      (define pdf (call-with-pdf-bytes (lambda (doc) (call-with-pdf-page doc 16 12 draw))))
      (check-true (regexp-match? #rx#"^%PDF-" pdf))))
  (test-case "picture bitmap and pict bridges run without a display"
    (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
                [picture (call-with-picture 9 7 (lambda (c) (draw-rect c 0 0 9 7 paint)))]
                [surface (make-surface 9 7)])
      (draw-picture (surface-canvas surface) picture)
      (define bitmap (surface->bitmap surface))
      (check-true (is-a? bitmap draw:bitmap%))
      (check-equal? (send bitmap get-width) 9)
      (define sample (make-bytes 4))
      (send bitmap get-argb-pixels 2 3 1 1 sample)
      (check-equal? sample (bytes 255 255 0 0))
      (define converted (picture->pict picture))
      (check-= (pict:pict-width converted) 9 0)
      (define rendered (pict:pict->bitmap converted))
      (send rendered get-argb-pixels 2 3 1 1 sample)
      (check-equal? sample (bytes 255 255 0 0))))
  (test-case "invalid arguments and closed resources remain errors"
    (check-exn exn:fail:contract? (lambda () (make-surface -1 7)))
    (define surface (make-surface 3 3))
    (skia-close! surface)
    (check-exn exn:fail? (lambda () (surface->png-bytes surface)))))
