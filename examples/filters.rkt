#lang racket/base
(require racket/cmdline "../main.rkt")

;; Visual smoke test for the 0.6 filter layer: color filters, mask blur,
;; image blur, drop shadows, and composed image-filter graphs.
(define (render-filters filename)
  (define grayscale
    '(0.2126 0.7152 0.0722 0 0
      0.2126 0.7152 0.0722 0 0
      0.2126 0.7152 0.0722 0 0
      0      0      0      1 0))
  (define swap-rb
    '(0 0 1 0 0
      0 1 0 0 0
      1 0 0 0 0
      0 0 0 1 0))
  (with-skia ([s (make-surface 1000 700 #:background "#F3F5F9")]
              [card (make-paint #:color 'white)]
              [border (make-paint #:color "#D8DFEA" #:style 'stroke #:stroke-width 2)]
              [ink (make-paint #:color "#223149")]
              [hole (make-paint #:color "#F3F5F9")]
              [font (make-font #:size 20)]
              [base-gradient (make-linear-gradient-shader
                              55 105 295 255
                              '("#326DE6" "#16A598" "#F38C42"))]
              [gray (make-color-matrix-filter grayscale)]
              [gray-paint (make-paint #:shader base-gradient #:color-filter gray)]
              [tint (make-blend-color-filter (rgba 255 80 110 110) 'src-over)]
              [tint-gradient (make-linear-gradient-shader
                              380 105 620 255
                              '("#326DE6" "#16A598" "#F38C42"))]
              [tint-paint (make-paint #:shader tint-gradient #:color-filter tint)]
              [mask-blur (make-blur-mask-filter 10 #:style 'normal #:respect-ctm? #f)]
              [mask-paint (make-paint #:color "#326DE6" #:mask-filter mask-blur)]
              [image-blur (make-blur-image-filter 8 8)]
              [blur-paint (make-paint #:color "#16A598" #:image-filter image-blur)]
              [shadow (make-drop-shadow-image-filter 12 14 7 7 (rgba 20 35 60 150))]
              [shadow-paint (make-paint #:color "#F38C42" #:image-filter shadow)]
              [swap (make-color-matrix-filter swap-rb)]
              [swap-if (make-color-filter-image-filter swap)]
              [soft-if (make-blur-image-filter 4 4 #:input swap-if)]
              [composed (make-compose-image-filter swap-if soft-if)]
              [compose-paint (make-paint #:color "#E14B67" #:image-filter composed)])
    (define c (surface-canvas s))
    (for* ([x '(30 355 680)] [y '(30 365)])
      (draw-rounded-rect c x y 290 305 18 18 card)
      (draw-rounded-rect c x y 290 305 18 18 border))

    (draw-simple-text c "color matrix" 50 68 font ink)
    (draw-rounded-rect c 55 105 240 160 20 20 gray-paint)

    (draw-simple-text c "blend color filter" 375 68 font ink)
    (draw-rounded-rect c 380 105 240 160 20 20 tint-paint)

    (draw-simple-text c "mask blur" 700 68 font ink)
    (draw-circle c 825 185 62 mask-paint)
    (draw-circle c 825 185 28 hole)

    (draw-simple-text c "image blur" 50 403 font ink)
    (draw-rounded-rect c 92 445 165 120 22 22 blur-paint)

    (draw-simple-text c "drop shadow" 375 403 font ink)
    (draw-rounded-rect c 410 450 165 110 22 22 shadow-paint)

    (draw-simple-text c "composed filter graph" 700 403 font ink)
    (draw-circle c 825 515 72 compose-paint)
    (save-png s filename)))

(module+ main
  (define filename
    (command-line #:program "filters.rkt"
                  #:args ([output "filters.png"])
                  output))
  (render-filters filename)
  (printf "Wrote ~a\n" filename))
