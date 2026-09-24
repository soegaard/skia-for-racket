#lang racket/base
(require racket/match racket/list "../main.rkt")

(define bg "#F4F6F9")
(define panel-fill "#FFFFFF")
(define frame-color "#CBD5E1")
(define label-color "#20304C")

(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 12)]
              [text (make-paint #:color label-color)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 18) (+ y 30) font text)))

(define (trim s n)
  (if (> (string-length s) n)
      (string-append (substring s 0 n) "...")
      s))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [label-font (make-font #:size 13)]
              [label-paint (make-paint #:color label-color)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "FontManager")
                  (355 30 "family match")
                  (680 30 "character fallback")
                  (30 365 "positioned glyphs")
                  (355 365 "blob replay")
                  (680 365 "manual positions"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (define family-count (font-manager-family-count fm))
    (draw-simple-text c (format "~a font families" family-count)
                      50 95 label-font label-paint)
    (for ([name (in-list (take (font-manager-families fm) (min 5 family-count)))]
          [i (in-naturals)])
      (draw-simple-text c (trim name 28) 50 (+ 125 (* i 28)) label-font label-paint))

    (define first-family
      (and (positive? family-count) (font-manager-family-name fm 0)))
    (define family-face
      (and first-family (font-manager-match-family fm first-family #:weight 'normal)))
    (when family-face
      (call-with-skia-resource
       family-face
       (lambda (face)
         (with-skia ([font (make-font face #:size 38)])
           (draw-simple-text c (trim (typeface-family-name face) 22)
                             380 105 label-font label-paint)
           (draw-simple-text c "Racket Skia" 385 185 font blue)))))

    (define fallback-face (font-manager-match-character fm #\界 #:languages '("ja")))
    (when fallback-face
      (call-with-skia-resource
       fallback-face
       (lambda (face)
         (with-skia ([font (make-font face #:size 74)])
           (draw-simple-text c (trim (typeface-family-name face) 22)
                             705 105 label-font label-paint)
           (draw-simple-text c "界" 775 215 font orange)))))

    (with-skia ([tf (make-typeface)]
                [font (make-font tf #:size 48)])
      (define skia-glyphs (font-text->glyphs font "SKIA"))
      (with-skia ([blob (make-positioned-text-blob
                         font skia-glyphs
                         '((0 0) (48 0) (98 0) (142 0)))])
        (draw-text-blob c blob 70 530 teal)
        (draw-simple-text c "explicit glyph positions" 50 610 label-font label-paint))

      (define replay-glyphs (font-text->glyphs font "SK"))
      (with-skia ([blob (make-positioned-text-blob font replay-glyphs '((0 0) (52 0)))])
        (draw-text-blob c blob 390 465 blue)
        (draw-text-blob c blob 425 525 teal)
        (draw-text-blob c blob 460 585 orange))

      (define wave-glyphs (font-text->glyphs font "WAVE"))
      (with-skia ([wave (make-positioned-text-blob
                         font wave-glyphs
                         '((0 0) (48 -18) (96 0) (144 18)))])
        (draw-text-blob c wave 715 525 blue)
        (define-values (bx by bw bh) (text-blob-bounds wave))
        (draw-simple-text c
                          (format "bounds ~a×~a" (inexact->exact (round bw))
                                  (inexact->exact (round bh)))
                          700 620 label-font label-paint)))

    (save-png surface out #:exists 'replace)))

(module+ main
  (define args (current-command-line-arguments))
  (define out (if (zero? (vector-length args)) "text-blobs.png" (vector-ref args 0)))
  (main out)
  (printf "Wrote ~a\n" out))
