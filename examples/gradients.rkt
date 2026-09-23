#lang racket/base
(require racket/cmdline "../main.rkt")

;; Visual smoke test for the shader layer: linear, radial, sweep, conical,
;; repeated-image, and blended shaders.  Coordinates are deliberately absolute
;; so each gradient's domain is visible directly in the panel where it is used.
(define (render-gradients filename)
  (define checker
    (bytes 50 109 230 255   226 234 250 255
           226 234 250 255  50 109 230 255))
  (with-skia ([s (make-surface 1000 700 #:background "#F3F5F9")]
              [card (make-paint #:color 'white)]
              [border (make-paint #:color "#D8DFEA" #:style 'stroke
                                  #:stroke-width 2)]
              [linear (make-linear-gradient-shader
                       55 55 295 275
                       '("#2D6CDF" "#15A596" "#F38C42")
                       #:positions '(0 0.55 1))]
              [linear-paint (make-paint #:shader linear)]
              [radial (make-radial-gradient-shader
                       500 160 125 '("#FFF3A3" "#F38C42" "#D43D6B"))]
              [radial-paint (make-paint #:shader radial)]
              [sweep (make-sweep-gradient-shader
                      825 160
                      '("#2D6CDF" "#15A596" "#F6C445" "#F38C42" "#2D6CDF")
                      #:positions '(0 1/4 1/2 3/4 1))]
              [sweep-paint (make-paint #:shader sweep)]
              [conical (make-two-point-conical-gradient-shader
                        80 500 8 285 500 105
                        '("#2D6CDF" "#A26BE3" "#F38C42"))]
              [conical-paint (make-paint #:shader conical)]
              [tile-image (rgba-bytes->image 2 2 checker)]
              [tile-shader (make-image-shader tile-image
                                              #:tile-x 'repeat #:tile-y 'repeat
                                              #:sampling 'nearest)]
              [tile-paint (make-paint #:shader tile-shader)]
              [blend-a (make-linear-gradient-shader
                        700 390 950 640
                        (list (rgba 255 65 85 255) (rgba 255 65 85 0)))]
              [blend-b (make-radial-gradient-shader
                        835 515 130
                        (list (rgba 45 109 230 255) (rgba 45 109 230 0)))]
              [blended (make-blend-shader 'screen blend-a blend-b)]
              [blend-paint (make-paint #:shader blended)])
    (define c (surface-canvas s))
    (for* ([x '(30 355 680)] [y '(30 365)])
      (draw-rounded-rect c x y 290 305 18 18 card)
      (draw-rounded-rect c x y 290 305 18 18 border))

    (draw-rounded-rect c 50 50 250 265 14 14 linear-paint)
    (draw-circle c 500 175 125 radial-paint)
    (draw-circle c 825 175 125 sweep-paint)
    (draw-rounded-rect c 50 390 250 255 14 14 conical-paint)
    ;; The 2x2 checker is intentionally magnified by the repeated image shader.
    (with-canvas-state c
      (canvas-scale! c 20)
      (draw-rect c (/ 375 20) (/ 390 20) (/ 250 20) (/ 255 20) tile-paint))
    (draw-rounded-rect c 700 390 250 255 14 14 blend-paint)
    (save-png s filename)))

(module+ main
  (define filename
    (command-line #:program "gradients.rkt"
                  #:args ([output "gradients.png"])
                  output))
  (render-gradients filename)
  (printf "Wrote ~a\n" filename))
