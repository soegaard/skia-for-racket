#lang racket/base
;; One backend-independent registry. The same callback is run directly on CPU
;; and GPU surfaces; it does not use output groups or intermediate CPU panels.
(require racket/list "../main.rkt")
(provide gpu-scene-names gpu-scene-width gpu-scene-height draw-gpu-scene)
(define gpu-scene-width 420)
(define gpu-scene-height 260)
(define gpu-scene-names '(paths gradients images filters runtime text mesh perspective))
(define (label c text x y size)
  (with-skia ([font (make-font #:size size #:hinting 'none #:linear-metrics? #t #:subpixel? #t)]
              [ink (make-paint #:color "#17354B")])
    (draw-simple-text c text x y font ink)))
(define (box c x y w h color)
  (with-skia ([p (make-paint #:color color #:antialias? #f)]) (draw-rect c x y w h p)))
(define (frame c name)
  (canvas-clear! c 'transparent)
  (box c 16 16 388 228 'white)
  (box c 0 0 8 8 (rgb 255 0 0))
  (box c 412 0 8 8 (rgb 0 255 0))
  (box c 0 252 8 8 (rgb 0 0 255))
  (box c 412 252 8 8 (rgb 255 255 0))
  (label c (string-append "GPU / CPU   " (symbol->string name)) 28 42 17))
(define (source-image)
  (define pixels (make-bytes (* 32 24 4)))
  (for* ([y (in-range 24)] [x (in-range 32)])
    (define i (* 4 (+ x (* 32 y))))
    (bytes-set! pixels i (if (< x 11) 230 35))
    (bytes-set! pixels (+ i 1) (if (< y 12) 170 70))
    (bytes-set! pixels (+ i 2) (if (< x 11) 35 215))
    (bytes-set! pixels (+ i 3) (if (= (modulo x 9) 0) 96 255)))
  (rgba-bytes->image 32 24 pixels))
(define (draw-gpu-scene c name)
  (unless (memq name gpu-scene-names) (error 'draw-gpu-scene "unknown scene ~a" name))
  (frame c name)
  (case name
    [(paths)
     (with-skia ([path (make-path)]
                 [fill (make-paint #:color (rgba 30 135 185 210))]
                 [line (make-paint #:color "#E57529" #:style 'stroke #:stroke-width 5)])
       (path-move-to! path 34 188)
       (path-cubic-to! path 52 50 180 52 198 168)
       (path-quad-to! path 224 236 310 152)
       (path-line-to! path 370 222) (path-line-to! path 34 222) (path-close! path)
       (draw-path c path fill) (draw-path c path line)
       (with-canvas-state c
         (canvas-clip-rect! c 250 62 124 86)
         (canvas-translate! c 310 101) (canvas-rotate! c 22)
         (draw-rounded-rect c -70 -40 140 80 18 18 fill)))]
    [(gradients)
     (with-skia ([linear (make-linear-gradient-shader 28 0 392 0
                          (list (rgb 220 70 45) (rgb 25 155 175) (rgb 45 65 190)))]
                 [radial (make-radial-gradient-shader 300 172 61 '(white "#147DA0" "#25335C"))]
                 [a (make-paint #:shader linear)] [b (make-paint #:shader radial)])
       (draw-rounded-rect c 28 60 364 65 12 12 a)
       (draw-rect c 28 145 183 79 a)
       (draw-circle c 302 180 52 b))]
    [(images)
     (with-skia ([im (source-image)] [p (make-paint #:color (rgba 255 255 255 180))])
       (draw-image-rect c im 28 62 192 144 #:sampling 'nearest)
       (with-canvas-state c
         (canvas-translate! c 278 122) (canvas-rotate! c 16)
         (draw-image-rect c im -47 -39 110 82 #:sampling 'linear #:paint p))
       (draw-image-subrect c im 3 4 15 13 260 180 114 48 #:sampling 'nearest))]
    [(filters)
     (with-skia ([blur (make-blur-image-filter 4 4)]
                 [shadow (make-drop-shadow-image-filter 7 8 4 4 (rgba 0 0 0 140))]
                 [a (make-paint #:color "#157DA2" #:image-filter blur)]
                 [b (make-paint #:color "#E79536" #:image-filter shadow)])
       (draw-circle c 112 148 63 a)
       (draw-rounded-rect c 225 85 145 121 18 18 b))]
    [(runtime)
     (with-skia ([effect (make-runtime-effect
                         "uniform float2 extent; half4 main(float2 p) { float2 uv=p/extent; float k=0.5+0.5*sin(uv.x*19.0+uv.y*7.0); return half4(uv.x,0.2+0.65*k,uv.y,1.0); }")]
                 [shader (runtime-effect->shader effect #:uniforms (hash 'extent '(364 164)))]
                 [paint (make-paint #:shader shader)])
       (with-canvas-state c
         (canvas-translate! c 28 62)
         (draw-rounded-rect c 0 0 364 164 14 14 paint)))]
    [(text)
     (with-skia ([font (make-font #:size 31 #:hinting 'none #:linear-metrics? #t #:subpixel? #t)]
                 [shaper (make-shaper font)]
                 [paint (make-paint #:color "#176F9B")])
       (draw-simple-text c "office affinity AV" 28 100 font paint)
       (define run (shape-text shaper "office affinity AV" #:language "en"))
       (draw-shaped-run c shaper run 28 148 paint)
       (with-canvas-state c
         (canvas-translate! c 34 214) (canvas-rotate! c -4)
         (draw-simple-text c "x + y = 2026" 0 0 font paint)))]
    [(mesh)
     (with-skia ([triangles (make-vertices 'triangles '((35 222) (132 65) (210 222)
                                                       (212 65) (386 88) (344 222))
                             #:colors '("#E77029" "#157FA5" "#52AF9D"
                                        "#344999" "#F0B12E" "#209A87"))]
                 [paint (make-paint #:color 'white)])
       (draw-vertices c triangles paint))]
    [(perspective)
     (with-skia ([gradient (make-linear-gradient-shader 0 0 300 150 '("#168EA2" "#EB953B"))]
                 [paint (make-paint #:shader gradient)]
                 [line (make-paint #:color "#203855" #:stroke-width 2)])
       (with-canvas-matrix c (make-matrix3 1 0.10 38 0.05 1 67 0.0012 0.0007 1)
         (draw-rect c 0 0 330 188 paint)
         (for ([x (in-range 0 331 30)]) (draw-line c x 0 x 188 line)))
       (label c "homogeneous 3 x 3" 180 231 12))])
  (void))
