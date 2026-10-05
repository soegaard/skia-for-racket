#lang racket/base
;; Public-API example using the host's default font. No installed-font identity
;; or numerical metric is assumed here; acceptance uses procedural fixtures.
(require "../main.rkt")
(module+ main
  (with-skia ([font (make-font #:size 32 #:embedded-bitmaps? #f #:baseline-snap? #f)]
              [face (font-typeface font)])
    (define text "AVATAR")
    (define glyphs (font-text->glyphs font text))
    (define-values (widths bounds) (font-glyph-widths+bounds font glyphs))
    (printf "Typeface: ~a\nAdvances: ~s\nBounds (x y w h): ~s\nPositions: ~s\n"
            (typeface-family-name face) widths bounds (font-glyph-positions font glyphs))
    (define-values (count measured) (font-break-text font text 100))
    (printf "Simple prefix: ~s (~a Racket characters, width ~a)\n"
            (substring text 0 count) count measured)
    (define paths (font-glyph-paths font glyphs))
    (dynamic-wind void
      (lambda ()
        (printf "Available monochrome outlines: ~a/~a\n"
                (for/sum ([p (in-vector paths)]) (if p 1 0)) (vector-length paths)))
      (lambda () (for ([p (in-vector paths)] #:when p) (skia-close! p))))))
