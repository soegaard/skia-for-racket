#lang racket/base

;; Always runs in DrDr on supported installations. The known font is original
;; project-generated data; the extra script-font checks use a declared package.
(require rackunit racket/class racket/list racket/path
         (prefix-in draw: racket/draw) (prefix-in pict: pict)
         "../main.rkt" "../bitmap.rkt" "../pict.rkt"
         "../private/native-loader.rkt" "../private/harfbuzz-native.rkt"
         "../private/catalog-fonts.rkt" "typeface-fixtures.rkt")

(module+ test
  (test-case "ordinary installed native dependencies select a managed pair"
    (skia-check!) (harfbuzz-check!)
    (unless (or (getenv "RACKET_SKIA_LIBRARY") (getenv "RACKET_HARFBUZZ_LIBRARY"))
      (check-equal? (hash-ref (hash-ref (native-library-report) 'loader) 'origin) "managed")
      (check-equal? (hash-ref (harfbuzz-library-report) 'origin) "managed"))
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
  (test-case "declared font package covers Arabic Hebrew and Han/kana"
    (for ([text '("مرحبا بالعالم" "שלום" "日本語中文ひらがな")]
          [filename '("NotoSansArabic-Regular.ttf" "NotoSansHebrew-Regular.ttf" "NotoSansCJKjp-Regular.otf")])
      (with-skia ([face (typeface-from-file (catalog-font-path filename))]
                  [font (make-font face #:size 20)] [shaper (make-shaper font)])
        (check-true (for/and ([g (in-vector (font-text->glyphs font text))]) (positive? g)))
        (check-true (positive? (shaped-run-glyph-count (shape-text shaper text)))))))
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
