#lang racket/base
(require racket/list racket/match "../main.rkt")

(define bg "#F4F6F9")
(define panel-fill "#FFFFFF")
(define frame-color "#CBD5E1")
(define guide-color "#E2E8F0")
(define ink "#20304C")

(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 12)]
              [text (make-paint #:color ink)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 18) (+ y 30) font text)))

(define (small-label c text x y)
  (with-skia ([font (make-font #:size 12)]
              [paint (make-paint #:color ink)])
    (draw-simple-text c text x y font paint)))

(define (guides c x y w h)
  (with-skia ([p (make-paint #:color guide-color #:style 'stroke #:stroke-width 1)])
    (draw-line c x y x (+ y h) p)
    (draw-line c (+ x w) y (+ x w) (+ y h) p)))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 28)]
              [sh (make-shaper font)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "Latin inter-word")
                  (355 30 "CJK inter-character")
                  (680 30 "Han + kana")
                  (30 365 "Arabic kashida")
                  (355 365 "Arabic + spaces")
                  (680 365 "mixed scripts"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title)
      (guides c (+ x 20) (+ y 48) 230 145))

    (define latin
      (layout-text sh "alpha beta gamma"
                   #:width 230 #:align 'justify-all))
    (draw-text-layout c latin 50 90 blue)
    (small-label c "U+0020 remains an expansion point" 50 250)

    (define cjk
      (layout-mixed-text sh fm "世界中文排版"
                         #:width 230 #:align 'justify-all #:language "zh"))
    (draw-mixed-text-layout c cjk 375 90 orange)
    (small-label c "unspaced CJK fills the measure" 375 250)

    (define japanese
      (layout-mixed-text sh fm "世界かなカナ"
                         #:width 230 #:align 'justify-all #:language "ja"))
    (draw-mixed-text-layout c japanese 700 90 teal)
    (small-label c "spacing crosses Han/kana run edges" 700 250)

    (define arabic-word
      (layout-mixed-text sh fm "مرحبابكم"
                         #:width 230 #:align 'justify-all
                         #:direction 'rtl #:language "ar"))
    (draw-mixed-text-layout c arabic-word 50 425 blue)
    (small-label c "joining-compatible tatweel elongation" 50 585)

    (define arabic-spaces
      (layout-mixed-text sh fm "مرحبا بكم في العالم"
                         #:width 230 #:align 'justify-all
                         #:direction 'rtl #:language "ar"))
    (draw-mixed-text-layout c arabic-spaces 375 425 orange)
    (small-label c "kashida and word spaces share slack" 375 585)

    (define mixed
      (layout-mixed-text sh fm "Racket 世界かな"
                         #:width 230 #:align 'justify-all #:language "ja"))
    (draw-mixed-text-layout c mixed 700 425 teal)
    (small-label c "opportunities distribute across runs" 700 585)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "script-justification.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
