#lang racket

(require skia)

(define width 800)
(define height 500)
(define lake-top 330)

(define sky-top "#0B1026")
(define sky-bottom "#344A78")
(define back-mountain-color "#596480")
(define front-mountain-color "#29334D")
(define lake-top-color "#263F63")
(define lake-bottom-color "#0D192B")
(define moon-color "#F6E7B0")
(define star-color "#E8ECF5")
(define cabin-color "#49352F")
(define roof-color "#182238")
(define door-color "#291F1D")
(define window-color "#FFD47A")
(define tree-color "#182A31")
(define text-color "#E8ECF5")

(define stars
  '((100 75 2)
    (170 135 2)
    (255 65 3)
    (330 120 2)
    (420 55 2)
    (510 145 2)
    (730 55 2)
    (760 150 3)
    (85 205 2)
    (375 185 2)))

(define back-mountains
  '((move 0 330)
    (line 0 285)
    (line 95 210)
    (line 160 275)
    (line 265 170)
    (line 365 280)
    (line 475 205)
    (line 585 285)
    (line 690 215)
    (line 800 290)
    (line 800 330)
    (close)))

(define front-mountains
  '((move 0 330)
    (line 0 305)
    (line 120 235)
    (line 205 305)
    (line 325 220)
    (line 445 320)
    (line 565 255)
    (line 705 325)
    (line 800 280)
    (line 800 330)
    (close)))

(define reflection-streaks
  '((355 26)
    (372 42)
    (392 62)
    (414 88)
    (438 112)
    (466 140)))

(define (draw-sky canvas)
  (define shader (make-linear-gradient-shader
    0 0 0 lake-top
    (list sky-top sky-bottom)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas 0 0 width height paint))

(define (draw-stars canvas)
  (define paint (make-paint #:color star-color))
  (for ([star (in-list stars)])
    (draw-circle canvas
                 (first star)
                 (second star)
                 (third star)
                 paint)))

(define (draw-moon canvas)
  (define paint (make-paint #:color moon-color))
  (draw-circle canvas 650 90 42 paint))

(define (draw-mountains canvas)
  (define back-path (make-path back-mountains))
  (define back-paint (make-paint #:color back-mountain-color))
  (define front-path (make-path front-mountains))
  (define front-paint (make-paint #:color front-mountain-color))
  (draw-path canvas back-path back-paint)
  (draw-path canvas front-path front-paint))

(define (draw-lake canvas)
  (define shader (make-linear-gradient-shader
    0 lake-top 0 height
    (list lake-top-color lake-bottom-color)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas
             0 lake-top
             width (- height lake-top)
             paint))

(define (draw-reflection canvas)
  (with-canvas-state canvas
    (canvas-clip-rect! canvas
                       0 lake-top
                       width (- height lake-top))
    (let ()
      (define paint (make-paint #:color (rgba 246 231 176 55)))
      (for ([streak (in-list reflection-streaks)])
        (define y (first streak))
        (define w (second streak))
        (draw-rounded-rect canvas
                           (- 650 (/ w 2)) y
                           w 4
                           2 2
                           paint)))))

(define (draw-cabin canvas x y)
  (define body-paint (make-paint #:color cabin-color))
  (define roof-paint (make-paint #:color roof-color))
  (define window-paint (make-paint #:color window-color))
  (define door-paint (make-paint #:color door-color))
  (draw-rect canvas x y 95 60 body-paint)
  (draw-polygon canvas
                (list (list (- x 13) (+ y 4))
                      (list (+ x 47) (- y 38))
                      (list (+ x 107) (+ y 4)))
                roof-paint)
  (draw-rect canvas (+ x 20) (+ y 17) 25 20 window-paint)
  (draw-rect canvas (+ x 63) (+ y 32) 20 28 door-paint))

(define (draw-tree canvas)
  (define paint (make-paint #:color tree-color))
  (draw-rect canvas -3 -18 6 18 paint)
  (draw-polygon canvas '((-18 -12) (0 -50) (18 -12)) paint)
  (draw-polygon canvas '((-15 -32) (0 -65) (15 -32)) paint)
  (draw-polygon canvas '((-12 -50) (0 -80) (12 -50)) paint))

(define (draw-tree-at canvas x y scale)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-tree canvas)))

(define (draw-trees canvas)
  (draw-tree-at canvas 85 lake-top 1.15)
  (draw-tree-at canvas 150 lake-top 0.80)
  (draw-tree-at canvas 495 lake-top 0.75)
  (draw-tree-at canvas 680 lake-top 1.15)
  (draw-tree-at canvas 735 lake-top 0.85)
  (draw-tree-at canvas 775 lake-top 0.65))

(define (draw-title canvas)
  (define title-font (make-font #:size 36))
  (define small-font (make-font #:size 15))
  (define paint (make-paint #:color text-color))
  (draw-simple-text canvas
                    "MOONLIGHT"
                    45 445
                    title-font paint)
  (draw-simple-text canvas
                    "A quiet night by the lake"
                    47 474
                    small-font paint))

(define (draw-moonlight canvas)
  (draw-sky canvas)
  (draw-stars canvas)
  (draw-moon canvas)
  (draw-mountains canvas)
  (draw-lake canvas)
  (draw-reflection canvas)
  (draw-cabin canvas 545 270)
  (draw-trees canvas)
  (draw-title canvas))

(define (save-raster filename)
  (define surface (make-surface width height))
  (draw-moonlight (surface-canvas surface))
  (save-png surface filename #:exists 'replace))

(define (save-vector filename format)
  (define page
    (make-output-page width height draw-moonlight
                      #:unit 'px))
  (save-output page filename format #:exists 'replace))

(module+ main
  (save-raster "moonlight.png")
  (save-vector "moonlight.pdf" 'pdf)
  (save-vector "moonlight.svg" 'svg))
