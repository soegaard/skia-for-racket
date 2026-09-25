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

(define thai-word "ภาษาไทย")
(define thai-text (string-append thai-word thai-word thai-word))

(define (thai-provider paragraph language)
  (if (and (equal? language "th") (string=? paragraph thai-text))
      (list (string-length thai-word)
            (* 2 (string-length thai-word)))
      '()))

(define (hyphen-provider paragraph language)
  (if (string=? paragraph "alphabeta")
      (list (make-layout-break-opportunity 5 "-"))
      '()))

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
    (for ([spec '((30 30 "SA default fallback")
                  (355 30 "external segmentation")
                  (680 30 "discretionary hyphen")
                  (30 365 "wide line: no hyphen")
                  (355 365 "provider + UAX #14")
                  (680 365 "mixed bidi + provider"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title)
      (guides c (+ x 20) (+ y 48) 230 145))

    (define a
      (layout-mixed-text sh fm thai-text #:width 220 #:language "th"))
    (draw-mixed-text-layout c a 50 90 blue)
    (small-label c "no built-in dictionary segmentation" 50 250)

    (define b
      (layout-mixed-text sh fm thai-text #:width 220 #:language "th"
                         #:break-provider thai-provider))
    (draw-mixed-text-layout c b 375 90 orange)
    (small-label c "provider supplies Thai word boundaries" 375 250)

    (define c1
      (layout-text sh "alphabeta" #:width 105
                   #:break-provider hyphen-provider))
    (draw-text-layout c c1 700 90 teal)
    (small-label c "hyphen appears only at selected break" 700 250)

    (define d
      (layout-text sh "alphabeta" #:width 230
                   #:break-provider hyphen-provider))
    (draw-text-layout c d 50 425 blue)
    (small-label c "unused opportunity does not alter text" 50 585)

    (define e
      (layout-text sh "alpha beta gamma" #:width 150
                   #:break-provider
                   (lambda (paragraph language)
                     (list (make-layout-break-opportunity 8 "-")))))
    (draw-text-layout c e 375 425 orange)
    (small-label c "provider supplements normal UAX #14" 375 585)

    (define mixed "Racketשלוםworld")
    (define f
      (layout-mixed-text sh fm mixed #:width 150
                         #:break-provider
                         (lambda (paragraph language) '(6 10))))
    (draw-mixed-text-layout c f 700 425 teal)
    (small-label c "paragraph bidi resolution is preserved" 700 585)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "break-providers.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
