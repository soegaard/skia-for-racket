#lang racket/base

;; These integration tests run explicitly for skia-doc, including in DrDr.
(require rackunit skia "../private/catalog-fonts.rkt")
(module+ test
  (test-case "documentation fonts covers Arabic Hebrew and Han/kana"
    (for ([text '("مرحبا بالعالم" "שלום" "日本語中文ひらがな")]
          [filename '("NotoSansArabic-Regular.ttf" "NotoSansHebrew-Regular.ttf" "NotoSansCJKjp-Regular.otf")])
      (with-skia ([face (typeface-from-file (catalog-font-path filename))]
                  [font (make-font face #:size 20)] [shaper (make-shaper font)])
        (check-true (for/and ([g (in-vector (font-text->glyphs font text))]) (positive? g)))
        (check-true (positive? (shaped-run-glyph-count (shape-text shaper text)))))))
)
