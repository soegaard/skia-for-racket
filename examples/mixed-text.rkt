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

(define (run-summary line)
  (string-join
   (for/list ([r (in-list (mixed-text-line-runs line))])
     (format "~a/~a/~a"
             (mixed-text-run-direction r)
             (or (mixed-text-run-script r) 'common)
             (or (mixed-text-run-family r) 'base)))
   "  "))

(define (preview s [limit 42])
  (if (> (string-length s) limit)
      (string-append (substring s 0 limit) "...")
      s))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 30)]
              [sh (make-shaper font)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#18A999")]
              [orange (make-paint #:color "#F38C42")]
              [small-font (make-font #:size 12)]
              [small-paint (make-paint #:color ink)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "English + Hebrew")
                  (355 30 "Arabic + numbers")
                  (680 30 "font fallback")
                  (30 365 "mixed wrapping")
                  (355 365 "bidi punctuation")
                  (680 365 "resolved runs"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (define l1 (layout-mixed-text sh fm "Racket שלום Skia" #:width 245))
    (draw-mixed-text-layout c l1 50 90 blue)
    (define line1 (car (mixed-text-layout-lines l1)))
    (draw-simple-text c
                      (format "~a visual runs" (length (mixed-text-line-runs line1)))
                      50 250 small-font small-paint)

    (define l2
      (layout-mixed-text sh fm "Version 12: مرحبا 123 بالعالم"
                         #:width 250 #:direction 'auto #:language "ar"))
    (draw-mixed-text-layout c l2 375 92 orange)
    (draw-simple-text c
                      (format "~a lines" (mixed-text-layout-line-count l2))
                      375 250 small-font small-paint)

    (define l3
      (layout-mixed-text sh fm "Skia 世界 Ελληνικά"
                         #:width 250 #:language "zh"))
    (draw-mixed-text-layout c l3 700 92 teal)
    (define fallback-families
      (remove-duplicates
       (filter values
               (append*
                (for/list ([ln (in-list (mixed-text-layout-lines l3))])
                  (map mixed-text-run-family (mixed-text-line-runs ln)))))))
    (draw-simple-text c
                      (preview (format "fallback: ~s" fallback-families) 34)
                      700 250 small-font small-paint)

    (define l4
      (layout-mixed-text
       sh fm "English שלום world مرحبا numbers 123 and more text"
       #:width 235))
    (draw-mixed-text-layout c l4 50 425 blue)
    (draw-simple-text c
                      (format "~a wrapped lines" (mixed-text-layout-line-count l4))
                      50 625 small-font small-paint)

    (define l5
      (layout-mixed-text sh fm "ABC (שלום 123) DEF [مرحبا 45]"
                         #:width 250))
    (draw-mixed-text-layout c l5 375 430 orange)
    (draw-simple-text c "brackets + embedded number runs"
                      375 625 small-font small-paint)

    (define l6 (layout-mixed-text sh fm "abc שלום 123 مرحبا" #:width 250))
    (draw-mixed-text-layout c l6 700 425 teal)
    (define summaries
      (for/list ([ln (in-list (mixed-text-layout-lines l6))])
        (run-summary ln)))
    (for ([summary (in-list summaries)] [i (in-naturals)])
      (draw-simple-text c (preview summary 39)
                        700 (+ 555 (* i 18)) small-font small-paint))

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (if (zero? (vector-length (current-command-line-arguments)))
        "mixed-text.png"
        (vector-ref (current-command-line-arguments) 0)))
  (main out)
  (printf "Wrote ~a\n" out))
