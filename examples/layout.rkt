#lang racket/base
(require racket/match "../main.rkt")

(define bg "#F3F5F9")
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

(define (draw-layout-box c sh text x y w paint #:align [align 'start]
                         #:direction [direction 'auto]
                         #:script [script #f] #:language [language #f])
  (define layout (layout-text sh text #:width w #:align align
                              #:direction direction #:script script #:language language))
  (draw-text-layout c layout x y paint)
  layout)

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [latin-face (make-typeface)]
              [fm (default-font-manager)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")]
              [small-font (make-font #:size 12)]
              [small-paint (make-paint #:color ink)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "greedy wrapping")
                  (355 30 "center alignment")
                  (680 30 "right alignment")
                  (30 365 "explicit lines")
                  (355 365 "RTL paragraph")
                  (680 365 "line metrics"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (with-skia ([font (make-font latin-face #:size 25)]
                [sh (make-shaper font)])
      (define a (draw-layout-box c sh
                    "A paragraph is shaped line by line and wrapped at whitespace."
                    50 85 245 blue))
      (draw-simple-text c (format "~a lines" (text-layout-line-count a))
                        50 305 small-font small-paint)

      (draw-layout-box c sh "centered text can wrap onto several lines"
                       375 95 250 teal #:align 'center)

      (draw-layout-box c sh "right aligned paragraph text"
                       700 105 250 orange #:align 'right)

      (define explicit (draw-layout-box c sh "first line\n\nthird line"
                                        50 425 245 blue))
      (draw-simple-text c (format "~a lines including blank line"
                                  (text-layout-line-count explicit))
                        50 620 small-font small-paint)

      (define metrics (draw-layout-box c sh
                        "Baselines are derived from font metrics. The layout reports width, height, and line spacing."
                        700 430 245 teal))
      (draw-simple-text c
                        (format "~ax~a  step ~a"
                                (inexact->exact (round (text-layout-width metrics)))
                                (inexact->exact (round (text-layout-height metrics)))
                                (inexact->exact (round (text-layout-line-height metrics))))
                        700 625 small-font small-paint))

    (define arabic-face (font-manager-match-character fm #\م #:languages '("ar")))
    (when arabic-face
      (call-with-skia-resource
       arabic-face
       (lambda (tf)
         (with-skia ([font (make-font tf #:size 30)]
                     [sh (make-shaper font)])
           (draw-layout-box c sh "مرحبا بالعالم هذا نص عربي متعدد الكلمات"
                            375 435 250 orange #:align 'start
                            #:direction 'rtl #:script 'arab #:language "ar")))))

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "layout.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
