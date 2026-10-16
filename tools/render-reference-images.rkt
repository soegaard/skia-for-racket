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


;; Stage 3: visual examples for the broader drawing, text, recording, and
;; structured-drawing reference chapters.

(render-reference-image
 "radial-gradient.png" 120 80
 (lambda (canvas)
   (with-skia ([shader (make-radial-gradient-shader 60 40 50 '(white "#326DE6"))]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 120 80 paint))))

(render-reference-image
 "sweep-gradient.png" 120 80
 (lambda (canvas)
   (with-skia ([shader
                (make-sweep-gradient-shader
                 60 40 '(red yellow green cyan blue magenta red))]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 120 80 paint))))

(render-reference-image
 "corner-path-effect.png" 160 90
 (lambda (canvas)
   (with-skia ([effect (make-corner-path-effect 12)]
               [paint (make-paint #:color "#326DE6"
                                  #:style 'stroke
                                  #:stroke-width 5
                                  #:path-effect effect)])
     (draw-polygon canvas '((15 70) (55 20) (95 70) (145 20))
                   paint #:closed? #f)))
 #:background 'white)

(render-reference-image
 "blur-mask-filter.png" 160 90
 (lambda (canvas)
   (with-skia ([mask (make-blur-mask-filter 8)]
               [paint (make-paint #:color "#326DE6" #:mask-filter mask)])
     (draw-circle canvas 80 45 24 paint)))
 #:background 'white)

(render-reference-image
 "blur-image-filter.png" 160 90
 (lambda (canvas)
   (with-skia ([filter (make-blur-image-filter 6 6)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-rounded-rect canvas 35 25 90 40 8 8 paint)))
 #:background 'white)

(render-reference-image
 "drop-shadow-filter.png" 180 100
 (lambda (canvas)
   (with-skia ([filter
                (make-drop-shadow-image-filter 8 8 5 5
                                               (rgba 0 0 0 140))]
               [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
     (draw-rounded-rect canvas 40 25 90 45 8 8 paint)))
 #:background 'white)

(render-reference-image
 "primitive-gallery.png" 220 120
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")]
               [stroke (make-paint #:color "#20344E"
                                   #:style 'stroke
                                   #:stroke-width 4)])
     (draw-rect canvas 15 20 45 35 blue)
     (draw-circle canvas 100 38 22 orange)
     (draw-oval canvas 140 18 65 40 stroke)
     (draw-rounded-rect canvas 35 75 150 30 10 10 blue)))
 #:background 'white)

(render-reference-image
 "bezier-path.png" 180 100
 (lambda (canvas)
   (with-skia ([path
                (make-path
                 '((move 15 75)
                   (cubic 45 10 135 10 165 75)))]
               [paint (make-paint #:color "#326DE6"
                                  #:style 'stroke
                                  #:stroke-width 5)])
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "fill-rules.png" 190 90
 (lambda (canvas)
   (with-skia ([even-odd (make-path #:fill-rule 'even-odd)]
               [winding (make-path #:fill-rule 'winding)]
               [paint (make-paint #:color "#326DE6")])
     (for ([path (in-list (list even-odd winding))]
           [x (in-list '(48 142))])
       (path-add-circle! path x 45 34)
       (path-add-circle! path x 45 15))
     (draw-path canvas even-odd paint)
     (draw-path canvas winding paint)))
 #:background 'white)

(render-reference-image
 "mesh-triangle.png" 160 120
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'white)]
               [mesh (make-vertices 'triangles
                                    '((15 105) (145 105) (80 15))
                                    #:colors '(red green blue))])
     (draw-vertices canvas mesh paint)))
 #:background 'white)

(render-reference-image
 "cubic-patch.png" 180 120
 (lambda (canvas)
   (define patch
     (make-cubic-patch
      '((20 20) (60 0) (120 0) (160 20)
        (180 50) (180 70) (160 100)
        (120 120) (60 120) (20 100)
        (0 70) (0 50))
      #:colors '(red blue green yellow)))
   (with-skia ([paint (make-paint #:color 'white)])
     (draw-patch canvas patch paint)))
 #:background 'white)

(define (make-nine-patch-source)
  (with-skia ([surface (make-surface 30 30 #:background "#F4D35E")]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas surface) 0 0 30 8 blue)
    (draw-rect (surface-canvas surface) 0 22 30 8 blue)
    (surface-snapshot surface)))

(render-reference-image
 "nine-patch.png" 180 110
 (lambda (canvas)
   (with-skia ([image (make-nine-patch-source)])
     (draw-image-nine canvas image '(8 8 14 14) 15 10 150 90)))
 #:background 'white)

(define (make-atlas-source)
  (with-skia ([surface (make-surface 32 16 #:background 'red)]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas surface) 16 0 16 16 blue)
    (surface-snapshot surface)))

(render-reference-image
 "atlas-batch.png" 180 90
 (lambda (canvas)
   (with-skia ([image (make-atlas-source)])
     (draw-atlas
      canvas image
      (list (make-atlas-transform 20 20 #:scale 2)
            (make-atlas-transform 90 15 #:scale 3)
            (make-atlas-transform 145 55 #:scale 1.5 #:rotation 25))
      '((0 0 16 16) (16 0 16 16) (0 0 16 16))
      #:sampling 'nearest)))
 #:background 'white)

(render-reference-image
 "portable-markers.png" 180 90
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (draw-markers canvas '((25 25) (55 45) (85 25))
                   18 blue #:shape 'circle)
     (draw-markers canvas '((115 25) (145 45) (165 25))
                   16 orange #:shape 'square)))
 #:background 'white)

(render-reference-image
 "portable-atlas.png" 120 60
 (lambda (canvas)
   (with-skia ([source (make-surface 2 2 #:background 'red)]
               [image (surface-snapshot source)])
     (draw-atlas/portable
      canvas image
      (list (make-atlas-transform 10 10 #:scale 10)
            (make-atlas-transform 70 10 #:scale 20))
      '((0 0 2 2) (0 0 2 2))
      #:sampling 'nearest)))
 #:background 'white)

(render-reference-image
 "image-filter-placement.png" 120 80
 (lambda (canvas)
   (with-skia ([source-surface (make-surface 40 25 #:background 'red)]
               [image (surface-snapshot source-surface)]
               [filter (make-offset-image-filter 30 15)])
     (define-values (result source offset)
       (image-apply-filter image filter #:clip '(0 0 120 80)))
     (call-with-skia-resource result
       (lambda (result)
         (with-skia ([part (apply image-subset result (vector->list source))])
           (draw-image canvas part
                       (vector-ref offset 0)
                       (vector-ref offset 1)))))))
 #:background 'white)

(render-reference-image
 "text-blob.png" 180 80
 (lambda (canvas)
   (with-skia ([font (make-font #:size 30)]
               [blob
                (make-positioned-text-blob
                 font (font-text->glyphs font "AB") '((0 0) (55 0)))]
               [paint (make-paint #:color 'black)])
     (draw-text-blob canvas blob 20 55 paint)))
 #:background 'white)

(render-reference-image
 "text-layout.png" 260 150
 (lambda (canvas)
   (with-skia ([font (make-font #:size 20)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color 'black)])
     (define layout
       (layout-text shaper "A short paragraph with several words."
                    #:width 220 #:line-height 28))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "mixed-text-layout.png" 300 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 22)]
               [shaper (make-shaper font)]
               [manager (make-font-manager)]
               [paint (make-paint #:color 'black)])
     (define layout
       (layout-mixed-text shaper manager "ABC אבג 123" #:width 260))
     (draw-mixed-text-layout canvas layout 20 20 paint)))
 #:background 'white)

(render-reference-image
 "recording.png" 100 40
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 40 20
                  (lambda (recording-canvas)
                    (with-skia ([paint (make-paint #:color 'blue)])
                      (draw-rect recording-canvas 0 0 40 20 paint))))])
     (draw-picture canvas picture #:x 10 #:y 10)))
 #:background 'white)

(render-reference-image
 "drawable.png" 120 50
 (lambda (canvas)
   (with-skia ([drawable
                (call-with-drawable 40 30
                  (lambda (recording-canvas)
                    (with-skia ([paint (make-paint #:color 'red)])
                      (draw-rect recording-canvas 5 5 30 20 paint))))])
     (draw-drawable canvas drawable #:matrix (matrix-translate 5 10))
     (draw-drawable canvas drawable
                    #:matrix (matrix-translate 65 10)
                    #:mode 'immediate)))
 #:background 'white)

(render-reference-image
 "output-group.png" 120 80
 (lambda (canvas)
   (with-skia ([ink (make-paint #:color 'red)])
     (draw-output-group canvas 20 20 60 40
       (lambda (group-canvas)
         (draw-rect group-canvas 0 0 60 40 ink))
       #:policy 'raster
       #:scale 2
       #:padding 4)))
 #:background 'white)
