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

(define LRE (string #\u202A))
(define RLE (string #\u202B))
(define PDF (string #\u202C))
(define LRO (string #\u202D))
(define RLO (string #\u202E))
(define LRI (string #\u2066))
(define RLI (string #\u2067))
(define FSI (string #\u2068))
(define PDI (string #\u2069))

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
    (for ([spec '((30 30 "RLO override")
                  (355 30 "LRO override")
                  (680 30 "RLI isolate")
                  (30 365 "LRI in RTL paragraph")
                  (355 365 "FSI chooses direction")
                  (680 365 "scope survives wrapping"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title)
      (guides c (+ x 20) (+ y 48) 230 145))

    (define a
      (layout-mixed-text sh fm
                         (string-append "left " RLO "abc 123" PDF " right")
                         #:width 230))
    (draw-mixed-text-layout c a 50 90 blue)
    (small-label c "Latin segment forced RTL" 50 250)

    (define b
      (layout-mixed-text sh fm
                         (string-append "שלום " LRO "אבג 123" PDF " סוף")
                         #:width 230 #:direction 'rtl))
    (draw-mixed-text-layout c b 375 90 orange)
    (small-label c "Hebrew segment forced LTR" 375 250)

    (define c1
      (layout-mixed-text sh fm
                         (string-append "before " RLI "שלום 123" PDI " after")
                         #:width 230))
    (draw-mixed-text-layout c c1 700 90 teal)
    (small-label c "isolate direction does not leak" 700 250)

    (define d
      (layout-mixed-text sh fm
                         (string-append "שלום " LRI "abc 123" PDI " עולם")
                         #:width 230 #:direction 'rtl))
    (draw-mixed-text-layout c d 50 425 blue)
    (small-label c "LTR island inside RTL paragraph" 50 585)

    (define e
      (layout-mixed-text sh fm
                         (string-append "A " FSI "مرحبا 123" PDI " B")
                         #:width 230))
    (draw-mixed-text-layout c e 375 425 orange)
    (small-label c "FSI follows first strong character" 375 585)

    (define f
      (layout-mixed-text sh fm
                         (string-append RLO
                                        "alpha beta gamma delta epsilon zeta"
                                        PDF)
                         #:width 225))
    (draw-mixed-text-layout c f 700 425 teal)
    (small-label c "one override spans multiple visual lines" 700 585)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "bidi-controls.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
