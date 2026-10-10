#lang racket

(require skia)

(define width 720)
(define height 900)

(define background-top "#0B1026")
(define background-middle "#182950")
(define background-bottom "#304A73")
(define warm-color "#FFAE5D")
(define hot-color "#F35B74")
(define cool-color "#45C2C7")
(define light-color "#F8F1E5")

(define (draw-background canvas)
  (define shader
    (make-linear-gradient-shader
     0 0 0 height
     (list background-top
           background-middle
           background-bottom)
     #:positions '(0 3/5 1)))
  (define paint (make-paint #:shader shader))
  (draw-rect canvas 0 0 width height paint))

(define (draw-orb canvas)
  (define shader
    (make-radial-gradient-shader
     520 190 165
     (list "#FFF1B8"
           warm-color
           (rgba 243 91 116 0))
     #:positions '(0 3/5 1)))
  (define paint (make-paint #:shader shader))
  (draw-circle canvas 520 190 165 paint))

(define (draw-transparent-shapes canvas)
  (define cool-paint
    (make-paint #:color (rgba 69 194 199 62)))
  (define hot-paint
    (make-paint #:color (rgba 243 91 116 52)))
  (draw-circle canvas 120 255 92 cool-paint)
  (draw-circle canvas 195 330 72 hot-paint)
  (draw-rounded-rect canvas 68 220 220 180 32 32 cool-paint))

(define (draw-repeat-band canvas)
  (define shader
    (make-linear-gradient-shader
     60 0 156 0
     (list (rgba 69 194 199 0)
           (rgba 69 194 199 200)
           (rgba 243 91 116 170)
           (rgba 69 194 199 0))
     #:positions '(0 7/20 13/20 1)
     #:tile-mode 'repeat))
  (define paint (make-paint #:shader shader))
  (draw-rounded-rect canvas 60 418 600 96 20 20 paint))

(define (make-checker-image)
  (define surface
    (make-surface 32 32 #:background 'transparent))
  (define canvas (surface-canvas surface))
  (define light
    (make-paint #:color (rgba 248 241 229 55)))
  (define cool
    (make-paint #:color (rgba 69 194 199 26)))
  (draw-rect canvas 0 0 16 16 light)
  (draw-rect canvas 16 16 16 16 light)
  (draw-rect canvas 16 0 16 16 cool)
  (draw-rect canvas 0 16 16 16 cool)
  (surface-snapshot surface))

(define (draw-pattern-strip canvas)
  (define image (make-checker-image))
  (define shader
    (make-image-shader image
                       #:tile-x 'repeat
                       #:tile-y 'repeat
                       #:sampling 'nearest))
  (define paint (make-paint #:shader shader))
  (draw-rounded-rect canvas 82 696 556 56 12 12 paint))

(define (draw-blended-panel canvas)
  (define base
    (make-linear-gradient-shader
     60 548 660 786
     (list (rgba 55 80 170 230)
           (rgba 126 78 198 205))))
  (define glow
    (make-radial-gradient-shader
     545 660 250
     (list (rgba 255 174 93 230)
           (rgba 243 91 116 0))))
  (define shader
    (make-blend-shader 'screen base glow))
  (define paint (make-paint #:shader shader))
  (define border
    (make-paint #:color (rgba 248 241 229 50)
                #:style 'stroke
                #:stroke-width 2))
  (draw-rounded-rect canvas 60 548 600 238 30 30 paint)
  (draw-rounded-rect canvas 60 548 600 238 30 30 border))

(define (draw-copy canvas)
  (define kicker-font (make-font #:size 14))
  (define title-font (make-font #:size 58))
  (define subtitle-font (make-font #:size 18))
  (define title-paint
    (make-paint #:color light-color))
  (define quiet-paint
    (make-paint #:color (rgba 248 241 229 185)))
  (draw-simple-text canvas
                    "SKIA / STUDY 05"
                    58 76
                    kicker-font quiet-paint)
  (draw-simple-text canvas
                    "NIGHT / SIGNAL"
                    58 842
                    title-font title-paint)
  (draw-simple-text canvas
                    "PAINTS  /  GRADIENTS  /  SHADERS"
                    62 876
                    subtitle-font quiet-paint))

(define (draw-poster canvas)
  (draw-background canvas)
  (draw-transparent-shapes canvas)
  (draw-orb canvas)
  (draw-repeat-band canvas)
  (draw-blended-panel canvas)
  (draw-pattern-strip canvas)
  (draw-copy canvas))

(module+ main
  (define surface
    (make-surface width height))
  (draw-poster (surface-canvas surface))
  (save-png surface "poster.png" #:exists 'replace))
