#lang racket/base
(require racket/match "../main.rkt")

(define bg "#F3F5F8")
(define panel-fill "#FFFFFF")
(define frame-color "#C8D1DC")
(define label-color "#20304C")

(define (panel c x y w h title)
  (with-skia ([fill (make-paint #:color panel-fill)]
              [stroke (make-paint #:color frame-color #:style 'stroke #:stroke-width 2)]
              [font (make-font #:size 12)]
              [text (make-paint #:color label-color)])
    (draw-rounded-rect c x y w h 16 16 fill)
    (draw-rounded-rect c x y w h 16 16 stroke)
    (draw-simple-text c title (+ x 20) (+ y 32) font text)))

(define (build-star-picture)
  (call-with-picture
   120 120
   (lambda (c)
     (with-skia ([ring (make-paint #:color "#326DE6")]
                 [center (make-paint #:color "#F38C42")])
       (for ([i (in-range 10)])
         (call-with-canvas-state
          c
          (lambda ()
            (canvas-translate! c 60 60)
            (canvas-rotate! c (* i 36))
            (draw-rounded-rect c 36 -6 18 12 6 6 ring))))
       (draw-circle c 60 60 14 center)))))

(define (build-badge-picture)
  (call-with-picture
   100 100
   (lambda (c)
     (with-skia ([ring (make-paint #:color "#326DE6")]
                 [inner (make-paint #:color 'white)]
                 [tri (make-paint #:color "#F38C42")]
                 [path (make-path '((move 50 28) (line 28 68) (line 72 68) (close)))])
       (draw-circle c 50 50 34 ring)
       (draw-circle c 50 50 22 inner)
       (draw-path c path tri)))))

(define (main out)
  (with-skia ([surface (make-surface 1000 700 #:background bg)]
              [star (build-star-picture)]
              [badge (build-badge-picture)])
    (define c (surface-canvas surface))
    (for ([spec '((30 30 "record once, replay twice")
                  (355 30 "scaled rasterization")
                  (680 30 "explicit recorder")
                  (30 365 "picture into image")
                  (355 365 "picture layering")
                  (680 365 "mixed replay") )])
      (match-define (list x y title) spec)
      (panel c x y 290 305 title))
    (draw-picture c star #:x 65 #:y 95)
    (draw-picture c star #:x 180 #:y 165 #:width 80 #:height 80)

    (draw-picture c badge #:x 390 #:y 95 #:width 210 #:height 210)

    (with-skia ([rec (make-picture-recorder)])
      (define rc (picture-recorder-begin-recording! rec 0 0 140 100))
      (with-skia ([fill (make-paint #:color "#18A999")]
                  [stroke (make-paint #:color "#20304C" #:style 'stroke #:stroke-width 4)])
        (draw-rounded-rect rc 12 18 116 64 16 16 fill)
        (draw-line rc 12 50 128 50 stroke))
      (with-skia ([recorded (picture-recorder-finish-recording! rec)])
        (draw-picture c recorded #:x 710 #:y 118)))

    (with-skia ([img (picture->image star 180 180)])
      (draw-image c img 87 432))

    (draw-picture c badge #:x 395 #:y 430)
    (draw-picture c star #:x 425 #:y 460 #:width 160 #:height 160)

    (draw-picture c star #:x 714 #:y 410)
    (draw-picture c badge #:x 746 #:y 505 #:width 120 #:height 120)

    (save-png surface out #:exists 'replace)))

(module+ main
  (define out
    (vector-ref (current-command-line-arguments) 0))
  (main out)
  (printf "Wrote ~a
" out))
