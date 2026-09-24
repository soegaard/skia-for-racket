#lang racket/base
(require racket/match "../main.rkt")

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

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [stroke (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5 #:antialias? #t)]
              [fill (make-paint #:color "#F38C42" #:antialias? #t)]
              [teal (make-paint #:color "#18A999" #:antialias? #t)]
              [slate (make-paint #:color "#20304C" #:style 'stroke #:stroke-width 3 #:antialias? #t)]
              [font (make-font #:size 12)]
              [text (make-paint #:color label-color)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "SVG parse")
                  (355 30 "relative commands")
                  (680 30 "conics")
                  (30 365 "rounded rects")
                  (355 365 "path composition")
                  (680 365 "SVG serialize"))])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))

    (with-skia ([p (svg-path->path "M 80 160 C 80 110, 120 80, 160 110 C 200 80, 240 110, 240 160 C 240 210, 190 245, 160 270 C 130 245, 80 210, 80 160 Z")])
      (draw-path c p fill)
      (draw-path c p stroke))

    (with-skia ([p (make-path '((move 410 130) (rline 70 0) (rline 25 55) (rline -60 50) (rline -65 -30) (close)))])
      (draw-path c p teal)
      (draw-path c p slate))

    (with-skia ([p (make-path)])
      (path-move-to! p 770 245)
      (path-conic-to! p 705 100 840 95 0.45)
      (path-conic-to! p 910 220 825 270 0.45)
      (draw-path c p stroke))

    (with-skia ([p (make-path)])
      (path-add-rounded-rect! p 70 425 210 170 30 30)
      (draw-path c p teal)
      (draw-path c p slate))

    (with-skia ([base (make-path '((move 425 430) (line 560 430) (line 560 560) (line 425 560) (close)))]
                [bubble (svg-path->path "M 0 40 Q 0 0 40 0 L 120 0 Q 160 0 160 40 L 160 80 Q 160 120 120 120 L 50 120 L 24 148 L 32 120 Q 0 116 0 80 Z")])
      (path-add-path! bubble base #:dx 10 #:dy 12)
      (draw-path c bubble fill)
      (draw-path c bubble stroke))

    (with-skia ([p (svg-path->path "M 735 438 L 892 438 L 942 512 L 812 590 L 710 530 Z")])
      (draw-path c p teal)
      (draw-path c p slate)
      (draw-simple-text c (path->svg-path p) 700 640 font text))

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out (vector-ref (current-command-line-arguments) 0))
  (main out)
  (printf "Wrote ~a
" out))
