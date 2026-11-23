#lang racket

;;;
;;; Moonlight
;;;

;; Builds the moonlit landscape used by the introductory Quick tutorial.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

;;;
;;; Scene Dimensions and Palette
;;;

; width : exact-integer?
;   Specifies width in the drawing's local coordinate units.
(define width 800)

; height : exact-integer?
;   Specifies height in the drawing's local coordinate units.
(define height 500)

; lake-top : exact-integer?
;   Sets the horizon where the lake begins in the landscape's local coordinates.
(define lake-top 330)

; sky-top : string?
;   Specifies the sky top color used by this drawing.
(define sky-top "#0B1026")

; sky-bottom : string?
;   Specifies the sky bottom color used by this drawing.
(define sky-bottom "#344A78")

; back-mountain-color : string?
;   Specifies the back mountain color color used by this drawing.
(define back-mountain-color "#596480")

; front-mountain-color : string?
;   Specifies the front mountain color color used by this drawing.
(define front-mountain-color "#29334D")

; lake-top-color : string?
;   Specifies the lake top color color used by this drawing.
(define lake-top-color "#263F63")

; lake-bottom-color : string?
;   Specifies the lake bottom color color used by this drawing.
(define lake-bottom-color "#0D192B")

; moon-color : string?
;   Specifies the moon color color used by this drawing.
(define moon-color "#F6E7B0")

; star-color : string?
;   Specifies the star color color used by this drawing.
(define star-color "#E8ECF5")

; cabin-color : string?
;   Specifies the cabin color color used by this drawing.
(define cabin-color "#49352F")

; roof-color : string?
;   Specifies the roof color color used by this drawing.
(define roof-color "#182238")

; door-color : string?
;   Specifies the door color color used by this drawing.
(define door-color "#291F1D")

; window-color : string?
;   Specifies the window color color used by this drawing.
(define window-color "#FFD47A")

; tree-color : string?
;   Specifies the tree color color used by this drawing.
(define tree-color "#182A31")

; text-color : string?
;   Specifies the text color color used by this drawing.
(define text-color "#E8ECF5")

;;;
;;; Landscape Geometry
;;;

; stars : list?
;   Orders star center coordinates and radii for the reproducible night sky.
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

; back-mountains : list?
;   Orders the path commands defining the distant mountain silhouette.
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

; front-mountains : list?
;   Orders the path commands defining the foreground mountain silhouette.
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

; reflection-streaks : list?
;   Orders the lake-reflection marks used below the moon.
(define reflection-streaks
  '((355 26)
    (372 42)
    (392 62)
    (414 88)
    (438 112)
    (466 140)))

;;;
;;; Sky, Mountains, and Water
;;;

; draw-sky : canvas? -> void?
;   Draws the sky component in the current canvas coordinate system.
(define (draw-sky canvas)
  (define shader (make-linear-gradient-shader
    0 0 0 lake-top
    (list sky-top sky-bottom)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas 0 0 width height paint))

; draw-stars : canvas? -> void?
;   Draws the stars component in the current canvas coordinate system.
(define (draw-stars canvas)
  (define paint (make-paint #:color star-color))
  (for ([star (in-list stars)])
    (draw-circle canvas
                 (first star)
                 (second star)
                 (third star)
                 paint)))

; draw-moon : canvas? -> void?
;   Draws the moon component in the current canvas coordinate system.
(define (draw-moon canvas)
  (define paint (make-paint #:color moon-color))
  (draw-circle canvas 650 90 42 paint))

; draw-mountains : canvas? -> void?
;   Draws the mountains component in the current canvas coordinate system.
(define (draw-mountains canvas)
  (define back-path (make-path back-mountains))
  (define back-paint (make-paint #:color back-mountain-color))
  (define front-path (make-path front-mountains))
  (define front-paint (make-paint #:color front-mountain-color))
  (draw-path canvas back-path back-paint)
  (draw-path canvas front-path front-paint))

; draw-lake : canvas? -> void?
;   Draws the lake component in the current canvas coordinate system.
(define (draw-lake canvas)
  (define shader (make-linear-gradient-shader
    0 lake-top 0 height
    (list lake-top-color lake-bottom-color)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas
             0 lake-top
             width (- height lake-top)
             paint))

; draw-reflection : canvas? -> void?
;   Draws the reflection component in the current canvas coordinate system.
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

;;;
;;; Cabin and Trees
;;;

; draw-cabin : canvas? real? real? -> void?
;   Draws the cabin component in the current canvas coordinate system.
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

; draw-tree : canvas? -> void?
;   Draws the tree component in the current canvas coordinate system.
(define (draw-tree canvas)
  (define paint (make-paint #:color tree-color))
  (draw-rect canvas -3 -18 6 18 paint)
  (draw-polygon canvas '((-18 -12) (0 -50) (18 -12)) paint)
  (draw-polygon canvas '((-15 -32) (0 -65) (15 -32)) paint)
  (draw-polygon canvas '((-12 -50) (0 -80) (12 -50)) paint))

; draw-tree-at : canvas? real? real? real? -> void?
;   Draws the tree at component in the current canvas coordinate system.
(define (draw-tree-at canvas x y scale)
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (canvas-scale! canvas scale)
    (draw-tree canvas)))

; draw-trees : canvas? -> void?
;   Draws the trees component in the current canvas coordinate system.
(define (draw-trees canvas)
  (draw-tree-at canvas 85 lake-top 1.15)
  (draw-tree-at canvas 150 lake-top 0.80)
  (draw-tree-at canvas 495 lake-top 0.75)
  (draw-tree-at canvas 680 lake-top 1.15)
  (draw-tree-at canvas 735 lake-top 0.85)
  (draw-tree-at canvas 775 lake-top 0.65))

;;;
;;; Scene Assembly
;;;

; draw-title : canvas? -> void?
;   Draws the title component in the current canvas coordinate system.
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

; draw-moonlight : canvas? -> void?
;   Draws the moonlight component in the current canvas coordinate system.
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

;;;
;;; Raster and Vector Export
;;;

; save-raster : path-string? -> void?
;   Renders the raster example to the selected output destination.
(define (save-raster filename)
  (define surface (make-surface width height))
  (draw-moonlight (surface-canvas surface))
  (save-png surface filename #:exists 'replace))

; save-vector : path-string? symbol? -> void?
;   Exports the drawing through the output-page API to a vector document.
(define (save-vector filename format)
  (define page
    (make-output-page width height draw-moonlight
                      #:unit 'px))
  (save-output page filename format #:exists 'replace))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (save-raster "moonlight.png")
  (save-vector "moonlight.pdf" 'pdf)
  (save-vector "moonlight.svg" 'svg))
