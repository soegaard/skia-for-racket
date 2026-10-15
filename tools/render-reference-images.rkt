#lang racket/base

(require racket/file
         racket/runtime-path
         skia)

(define-runtime-path output-directory "../scribblings/reference/images")

(define device-scale 2)

(define (output-path filename)
  (build-path output-directory filename))

(define (make-reference-surface width height [background #f])
  (if background
      (make-surface (* device-scale width)
                    (* device-scale height)
                    #:background background)
      (make-surface (* device-scale width)
                    (* device-scale height))))

(define (render-reference-image filename width height draw
                                #:background [background #f])
  (make-directory* output-directory)
  (with-skia ([surface (make-reference-surface width height background)])
    (define canvas (surface-canvas surface))
    (canvas-scale! canvas device-scale device-scale)
    (draw canvas)
    (define path (output-path filename))
    (save-png surface path #:exists 'replace)
    (printf "wrote ~a\n" path)))

(render-reference-image
 "rectangle.png" 160 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-rect canvas 20 20 120 60 paint)))
 #:background 'white)

(render-reference-image
 "polyline.png" 120 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:style 'stroke
                                  #:stroke-width 3
                                  #:cap 'round)])
     (draw-polygon canvas '((10 60) (55 15) (100 60)) paint #:closed? #f)))
 #:background 'white)

(render-reference-image
 "gradient.png" 120 40
 (lambda (canvas)
   (with-skia ([shader (make-linear-gradient-shader 0 0 120 0 '(red blue))]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 120 40 paint))))

(render-reference-image
 "dashed-line.png" 100 30
 (lambda (canvas)
   (with-skia ([dash (make-dash-path-effect '(8 4))]
               [paint (make-paint #:color 'blue
                                  #:style 'stroke
                                  #:stroke-width 3
                                  #:path-effect dash)])
     ;; Preserve the lifetime point demonstrated by the Reference example.
     (skia-close! dash)
     (draw-line canvas 10 15 90 15 paint)))
 #:background 'white)

(render-reference-image
 "image-pair.png" 80 40
 (lambda (canvas)
   (with-skia ([image (rgba-bytes->image
                       2 1
                       (bytes 255 0 0 255
                              0 0 255 255))])
     (draw-image-rect canvas image 0 0 80 40 #:sampling 'nearest))))

(render-reference-image
 "simple-text.png" 240 80
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [paint (make-paint #:color 'black)])
     (draw-simple-text canvas "Skia" 16 48 font paint)))
 #:background 'white)

(render-reference-image
 "shaped-text.png" 240 80
 (lambda (canvas)
   (with-skia ([font (make-font #:size 28)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color 'black)])
     (draw-shaped-text canvas shaper "office" 16 48 paint
                       #:direction 'ltr
                       #:script 'latn
                       #:language "en")))
 #:background 'white)

(render-reference-image
 "canvas-state.png" 100 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (with-canvas-state canvas
       (canvas-translate! canvas 20 10)
       (canvas-clip-rect! canvas 0 0 40 30)
       (draw-rect canvas 0 0 60 50 paint))))
 #:background 'white)

(render-reference-image
 "canvas-layer.png" 160 100
 (lambda (canvas)
   (with-skia ([group-paint (make-paint #:color (rgba 0 0 0 128))]
               [ink (make-paint #:color 'red)])
     (with-canvas-layer canvas #:paint group-paint #:bounds '(0 0 160 100)
       (draw-rect canvas 20 20 80 60 ink)
       (draw-rect canvas 60 20 80 60 ink))))
 #:background 'white)

(render-reference-image
 "paint-styles.png" 180 80
 (lambda (canvas)
   (with-skia ([fill (make-paint #:color "#326DE6")]
               [outline (make-paint #:color 'black #:style 'stroke #:stroke-width 3)])
     (draw-rounded-rect canvas 15 15 60 50 8 8 fill)
     (draw-rounded-rect canvas 105 15 60 50 8 8 outline)))
 #:background 'white)

(render-reference-image
 "color-filter.png" 160 70
 (lambda (canvas)
   (with-skia ([filter
                (make-color-matrix-filter
                 '(0 0 0 0 1
                   0 0 0 0 0
                   0 0 0 0 0
                   0 0 0 1 0))]
               [source (make-paint #:color 'blue)]
               [filtered (make-paint #:color 'blue #:color-filter filter)])
     (draw-rect canvas 20 15 45 40 source)
     (draw-rect canvas 95 15 45 40 filtered)))
 #:background 'white)

(render-reference-image
 "image-filter-merge.png" 150 60
 (lambda (canvas)
   (with-skia ([shift (make-offset-image-filter 55 0)]
               [both (make-merge-image-filter (list #f shift))]
               [paint (make-paint #:color 'blue #:image-filter both)])
     (draw-rect canvas 15 15 30 30 paint)))
 #:background 'white)

(render-reference-image
 "runtime-effect-bands.png" 180 60
 (lambda (canvas)
   (with-skia ([effect
                (make-runtime-effect
                 "half4 main(float2 p) { half t=half(0.5+0.5*sin(p.x*0.08)); return half4(t,0,1-t,1); }")]
               [shader (runtime-effect->shader effect)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint)))
 #:background 'white)

(render-reference-image
 "path-hole.png" 160 100
 (lambda (canvas)
   (with-skia ([outer (make-path)]
               [hole (make-path)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-rect! outer 20 15 120 70)
     (path-add-circle! hole 80 50 22)
     (with-skia ([result (path-combine
                         (list (list 'union outer) (list 'difference hole)))])
       (draw-path canvas result paint))))
 #:background 'white)

(render-reference-image
 "rounded-rect.png" 160 90
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (define shape
       (make-rounded-rect 20 15 120 60
                          #:radii '((24 24) (8 8) (24 8) (8 24))))
     (draw-rrect canvas shape paint)))
 #:background 'white)

(render-reference-image
 "region.png" 155 80
 (lambda (canvas)
   (with-skia ([region (make-region '((15 15 55 50) (90 15 50 50)))]
               [paint (make-paint #:color "#326DE6")])
     (draw-region canvas region paint)))
 #:background 'white)

(render-reference-image
 "affine-transform.png" 180 120
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (with-canvas-state canvas
       (canvas-concat! canvas
                       (matrix-compose (matrix-translate 90 60)
                                       (matrix-rotate-degrees 25)))
       (draw-rect canvas -45 -20 90 40 paint))))
 #:background 'white)

(render-reference-image
 "projective-transform.png" 180 110
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (with-canvas-matrix canvas
         (make-matrix3 1 0 25
                       0 1 20
                       0.004 0 1)
       (draw-rect canvas 0 0 110 60 paint))))
 #:background 'white)
