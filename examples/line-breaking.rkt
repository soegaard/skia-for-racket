#lang racket/base
(require racket/list racket/match racket/string "../main.rkt")

(define bg "#F4F6F9")
(define panel-fill "#FFFFFF")
(define frame-color "#CBD5E1")
(define ink "#20304C")

(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 12)]
              [text (make-paint #:color ink)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 18) (+ y 30) font text)))

(define (line-label layout)
  (format "~a line~a"
          (mixed-text-layout-line-count layout)
          (if (= (mixed-text-layout-line-count layout) 1) "" "s")))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 28)]
              [sh (make-shaper font)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")]
              [small-font (make-font #:size 12)]
              [small-paint (make-paint #:color ink)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "unspaced CJK")
                  (355 30 "CJK punctuation")
                  (680 30 "hyphens + numbers")
                  (30 365 "mixed scripts")
                  (355 365 "grapheme clusters")
                  (680 365 "hard + no-break spaces"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (define l1
      (layout-mixed-text sh fm "世界中文排版測試沒有空格也能換行"
                         #:width 230 #:language "zh"))
    (draw-mixed-text-layout c l1 50 90 blue)
    (draw-simple-text c (line-label l1) 50 250 small-font small-paint)

    (define l2
      (layout-mixed-text sh fm "（世界）中文，標點不能跑到錯誤的位置。"
                         #:width 230 #:language "zh"))
    (draw-mixed-text-layout c l2 375 90 orange)
    (draw-simple-text c "opening/closing punctuation kept with text"
                      375 250 small-font small-paint)

    (define l3
      (layout-mixed-text sh fm "alpha-beta-gamma 12,345.67 delta"
                         #:width 235 #:language "en"))
    (draw-mixed-text-layout c l3 700 90 teal)
    (draw-simple-text c "hyphen breaks; numeric expression stays intact"
                      700 250 small-font small-paint)

    (define l4
      (layout-mixed-text
       sh fm "Racket 世界 שלום مرحبا 123 — mixed line breaking"
       #:width 235))
    (draw-mixed-text-layout c l4 50 425 blue)
    (draw-simple-text c (line-label l4) 50 625 small-font small-paint)

    (define combining (string-append "Cafe" (string #\u0301) " 世界 "))
    (define emoji (string (integer->char #x1F469) #\u200D
                          (integer->char #x1F4BB)))
    (define l5
      (layout-mixed-text sh fm (string-append combining emoji " text")
                         #:width 220))
    (draw-mixed-text-layout c l5 375 425 orange)
    (draw-simple-text c "combining marks / ZWJ cluster stay together"
                      375 625 small-font small-paint)

    (define nbsp (string #\u00A0))
    (define ls (string #\u2028))
    (define l6
      (layout-mixed-text sh fm
                         (string-append "hard break" ls "no" nbsp "break space")
                         #:width 220))
    (draw-mixed-text-layout c l6 700 425 teal)
    (draw-simple-text c "U+2028 forces; NBSP glues" 700 625 small-font small-paint)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "line-breaking.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
