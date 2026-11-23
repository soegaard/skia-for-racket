#lang racket/base

;; Run explicitly after ordinary setup, also for rebuilt documentation packages.
(require json rackunit skia "../private/catalog-fonts.rkt"
         (only-in skia/private/native-package-paths native-file-sha256))
(module+ main
  (define shapes
    (for/list ([filename '("NotoSans-Regular.ttf" "NotoSansArabic-Regular.ttf"
                           "NotoSansHebrew-Regular.ttf" "NotoSansCJKjp-Regular.otf")]
               [text '("AV" "مرحبا بالعالم" "שלום" "日本語中文ひらがな")])
      (with-skia ([face (typeface-from-file (catalog-font-path filename))]
                  [font (make-font face #:size 20)] [shaper (make-shaper font)])
        (check-true (for/and ([g (in-vector (font-text->glyphs font text))]) (positive? g)))
        (define run (shape-text shaper text))
        (check-true (positive? (shaped-run-glyph-count run)))
        (check-true (positive? (shaped-run-advance-x run)))
        (hasheq 'font filename 'font_sha256 (native-file-sha256 (catalog-font-path filename))
                'glyphs (vector->list (shaped-run-glyphs run)) 'advance (shaped-run-advance-x run)))))
  (write-json (hasheq 'schema 1 'status "passed" 'package "skia-doc" 'shapes shapes))
  (newline))
