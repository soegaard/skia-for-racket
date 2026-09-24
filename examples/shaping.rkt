#lang racket/base
(require racket/match "../main.rkt")

(define bg "#F4F6F9")
(define panel-fill "#FFFFFF")
(define frame-color "#CBD5E1")
(define ink "#20304C")

(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 13)]
              [text (make-paint #:color ink)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 18) (+ y 30) font text)))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [latin-face (make-typeface)]
              [arabic-face (or (font-manager-match-character fm #\م #:languages '("ar"))
                               (make-typeface))]
              [hebrew-face (or (font-manager-match-character fm #\ש #:languages '("he"))
                               (make-typeface))]
              [latin-font (make-font latin-face #:size 46)]
              [arabic-font (make-font arabic-face #:size 52)]
              [hebrew-font (make-font hebrew-face #:size 48)]
              [latin-shaper (make-shaper latin-font)]
              [arabic-shaper (make-shaper arabic-font)]
              [hebrew-shaper (make-shaper hebrew-font)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")]
              [small-font (make-font #:size 13)]
              [text-paint (make-paint #:color ink)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "Latin shaping")
                  (355 30 "Arabic / RTL")
                  (680 30 "Hebrew / RTL")
                  (30 365 "combining marks")
                  (355 365 "OpenType features")
                  (680 365 "clusters / positions"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (define latin-run (draw-shaped-text c latin-shaper "office" 58 175 blue
                                        #:language "en"))
    (draw-simple-text c
                      (format "~a glyphs, advance ~a"
                              (shaped-run-glyph-count latin-run)
                              (shaped-run-advance-x latin-run))
                      50 230 small-font text-paint)

    (define arabic-run (draw-shaped-text c arabic-shaper "مرحبا" 590 180 orange
                                         #:direction 'rtl #:script 'arab #:language "ar"))
    (draw-simple-text c
                      (format "~a glyphs" (shaped-run-glyph-count arabic-run))
                      375 230 small-font text-paint)

    (define hebrew-run (draw-shaped-text c hebrew-shaper "שלום" 910 180 teal
                                         #:direction 'rtl #:script 'hebr #:language "he"))
    (draw-simple-text c
                      (format "clusters ~s" (shaped-run-clusters hebrew-run))
                      700 230 small-font text-paint)

    (define combining-run
      (draw-shaped-text c latin-shaper (string-append "A" (string #\u0301) "  cafe" (string #\u0301))
                        60 520 teal #:language "en"))
    (draw-simple-text c
                      (format "~a glyphs from combining input" (shaped-run-glyph-count combining-run))
                      50 585 small-font text-paint)

    (define liga-on (shape-text latin-shaper "office" #:language "en"))
    (define liga-off (shape-text latin-shaper "office" #:language "en" #:features '("liga=0")))
    (draw-shaped-run c latin-shaper liga-on 385 485 blue)
    (draw-shaped-run c latin-shaper liga-off 385 555 orange)
    (draw-simple-text c
                      (format "default ~a glyphs; liga=0 ~a"
                              (shaped-run-glyph-count liga-on)
                              (shaped-run-glyph-count liga-off))
                      375 610 small-font text-paint)

    (define cluster-run (shape-text latin-shaper "Skia" #:language "en"))
    (draw-shaped-run c latin-shaper cluster-run 710 500 blue)
    (draw-simple-text c (format "clusters: ~s" (shaped-run-clusters cluster-run))
                      700 555 small-font text-paint)
    (draw-simple-text c (format "positions: ~s" (shaped-run-positions cluster-run))
                      700 585 small-font text-paint)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "shaping.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
