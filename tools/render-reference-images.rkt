#lang racket/base

(require racket/file
         racket/runtime-path
         racket/class
         skia
         skia/pict
         (only-in skia/codec-scanlines
                  codec-scanline-from-bytes codec-scanline-read!
                  scanline-batch-first-row scanline-batch->raster-buffer)
         (only-in skia/codec-incremental
                  make-codec-incremental codec-incremental-feed!
                  codec-incremental-step! incremental-progress-state
                  codec-incremental-snapshot incremental-snapshot->raster-buffer)
         (prefix-in pict: pict))

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


;; Stage 4: additional visual examples for float colors, specialized canvases,
;; documents and output, raster buffers and codecs, and the pict bridge.

(render-reference-image
 "float-gradient.png" 64 16
 (lambda (canvas)
   (with-skia ([shader
                (make-linear-gradient-color4f-shader
                 '(0 0) '(64 0)
                 (list (make-color4f 1 0 0) (make-color4f 0 0 1))
                 #:color-space 'srgb
                 #:stops '(0 1))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "nway-canvas.png" 16 16
 (lambda (canvas)
   (with-skia ([ink (make-paint #:color 'blue #:antialias? #f)])
     (draw-rect canvas 2 2 8 8 ink))))

(render-reference-image
 "pdf-document.png" 120 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (draw-rect canvas 10 10 100 60 paint)))
 #:background 'white)

(render-reference-image
 "svg-document.png" 120 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (draw-circle canvas 60 40 24 paint)))
 #:background 'white)

(render-reference-image
 "output-page-preview.png" 120 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (draw-circle canvas 20 20 16 paint)))
 #:background 'white)

(render-reference-image
 "raster-buffer-checker.png" 64 48
 (lambda (canvas)
   (with-skia ([dark (make-paint #:color "#326DE6")]
               [light (make-paint #:color "#E8EEF9")])
     (for ([row '(0 1 2)]
           [y '(0 16 32)])
       (for ([col '(0 1 2 3)]
             [x '(0 16 32 48)])
         (draw-rect canvas x y 16 16
                    (if (even? (+ row col)) dark light))))))
 #:background 'white)

(render-reference-image
 "codec-image.png" 48 32
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-rounded-rect canvas 6 6 36 20 6 6 paint)))
 #:background 'white)

(let ()
  (define icon
    (with-skia ([surface (make-surface 240 140 #:background 'white)]
                [paint (make-paint #:color 'blue)])
      (draw-circle (surface-canvas surface) 70 70 45 paint)
      (surface->pict surface #:backing-scale 2)))
  (define bitmap (pict:pict->bitmap (pict:scale icon device-scale)))
  (define path (output-path "pict-bridge.png"))
  (make-directory* output-directory)
  (send bitmap save-file path 'png)
  (printf "wrote ~a\n" path))

;; Stage 6: thirty-two additional reference figures. Six already had generator
;; entries from the earlier broad rendering pass; the twenty-six entries below
;; are new in this stage.

(render-reference-image
 "color-swatches.png" 210 70
 (lambda (canvas)
   (with-skia ([red-paint (make-paint #:color 'red)]
               [orange-paint (make-paint #:color 'orange)]
               [green-paint (make-paint #:color 'green)]
               [blue-paint (make-paint #:color "#326DE6")]
               [purple-paint (make-paint #:color 'purple)])
     (draw-rect canvas 10 10 34 50 red-paint)
     (draw-rect canvas 49 10 34 50 orange-paint)
     (draw-rect canvas 88 10 34 50 green-paint)
     (draw-rect canvas 127 10 34 50 blue-paint)
     (draw-rect canvas 166 10 34 50 purple-paint)))
 #:background 'white)

(render-reference-image
 "conical-gradient.png" 160 90
 (lambda (canvas)
   (with-skia ([shader
                (make-two-point-conical-gradient-shader
                 45 45 6 115 45 52 '(white "#326DE6"))]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 160 90 paint))))

(render-reference-image
 "image-shader-tiles.png" 160 90
 (lambda (canvas)
   (with-skia ([source (make-surface 20 20 #:background 'red)]
               [blue (make-paint #:color "#326DE6")])
     (draw-rect (surface-canvas source) 10 0 10 10 blue)
     (draw-rect (surface-canvas source) 0 10 10 10 blue)
     (with-skia ([image (surface-snapshot source)]
                 [shader (make-image-shader image #:tile-x 'repeat #:tile-y 'repeat)]
                 [paint (make-paint #:shader shader)])
       (draw-rect canvas 0 0 160 90 paint))))
 #:background 'white)

(render-reference-image
 "blend-shader.png" 180 90
 (lambda (canvas)
   (with-skia ([destination
                (make-linear-gradient-shader 0 0 180 0 '("#F4D35E" "#326DE6"))]
               [source
                (make-radial-gradient-shader 90 45 55 '(white "#E85D75"))]
               [shader (make-blend-shader 'multiply destination source)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 180 90 paint))))

(render-reference-image
 "discrete-path-effect.png" 180 90
 (lambda (canvas)
   (with-skia ([effect (make-discrete-path-effect 12 5 7)]
               [paint (make-paint #:color "#326DE6"
                                  #:style 'stroke
                                  #:stroke-width 4
                                  #:path-effect effect)])
     (draw-line canvas 15 45 165 45 paint)))
 #:background 'white)

(render-reference-image
 "trim-path-effect.png" 160 110
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [effect (make-trim-path-effect 0.10 0.72)]
               [paint (make-paint #:color "#326DE6"
                                  #:style 'stroke
                                  #:stroke-width 6
                                  #:cap 'round
                                  #:path-effect effect)])
     (path-add-circle! path 80 55 38)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "stamp-path-effect.png" 190 90
 (lambda (canvas)
   (with-skia ([stamp (make-path '((move 0 -5) (line 10 0) (line 0 5) (close)))]
               [line (make-path '((move 15 45) (cubic 60 10 130 80 175 45)))]
               [effect (make-1d-path-effect stamp 18 0 #:style 'rotate)]
               [paint (make-paint #:color "#326DE6"
                                  #:style 'stroke
                                  #:stroke-width 2
                                  #:path-effect effect)])
     (draw-path canvas line paint)))
 #:background 'white)

(render-reference-image
 "lighting-color-filter.png" 180 80
 (lambda (canvas)
   (with-skia ([filter (make-lighting-color-filter "#808080" "#500000")]
               [plain (make-paint #:color "#326DE6")]
               [filtered (make-paint #:color "#326DE6" #:color-filter filter)])
     (draw-rounded-rect canvas 15 18 60 44 8 8 plain)
     (draw-rounded-rect canvas 105 18 60 44 8 8 filtered)))
 #:background 'white)

(render-reference-image
 "dilate-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([plain (make-paint #:color "#326DE6")]
               [filter (make-dilate-image-filter 6 6)]
               [filtered (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-circle canvas 50 45 18 plain)
     (draw-circle canvas 125 45 18 filtered)))
 #:background 'white)

(render-reference-image
 "erode-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([plain (make-paint #:color "#326DE6")]
               [filter (make-erode-image-filter 6 6)]
               [filtered (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-rect canvas 25 20 50 50 plain)
     (draw-rect canvas 105 20 50 50 filtered)))
 #:background 'white)

(render-reference-image
 "matrix-convolution.png" 180 90
 (lambda (canvas)
   (with-skia ([filter
                (make-matrix-convolution-image-filter
                 3 3 '(0 -1 0 -1 5 -1 0 -1 0))]
               [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
     (draw-circle canvas 90 45 28 paint)))
 #:background 'white)

(render-reference-image
 "points-modes.png" 220 90
 (lambda (canvas)
   (with-skia ([points-paint
                (make-paint #:color "#326DE6" #:stroke-width 8 #:cap 'round)]
               [lines-paint
                (make-paint #:color "#EFA02B" #:stroke-width 4 #:cap 'round)]
               [poly-paint
                (make-paint #:color "#20344E" #:stroke-width 4 #:cap 'round)])
     (draw-points canvas '((20 25) (40 45) (60 25)) points-paint #:mode 'points)
     (draw-points canvas '((85 25) (105 55) (125 25) (145 55)) lines-paint #:mode 'lines)
     (draw-points canvas '((165 55) (185 20) (205 55)) poly-paint #:mode 'polygon)))
 #:background 'white)

(render-reference-image
 "arc-wedge.png" 190 90
 (lambda (canvas)
   (with-skia ([stroke (make-paint #:color "#326DE6"
                                   #:style 'stroke
                                   #:stroke-width 5)]
               [fill (make-paint #:color "#EFA02B")])
     (draw-arc canvas 15 10 70 70 25 250 stroke)
     (draw-arc canvas 105 10 70 70 25 250 fill #:use-center? #t)))
 #:background 'white)

(render-reference-image
 "double-rounded-rect.png" 180 100
 (lambda (canvas)
   (define outer (make-rounded-rect 20 15 140 70 #:radii 20))
   (define inner (make-rounded-rect 55 35 70 30 #:radii 10))
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-double-rounded-rect canvas outer inner paint)))
 #:background 'white)

(render-reference-image
 "region-clip.png" 180 90
 (lambda (canvas)
   (with-skia ([region (make-region '((15 15 65 60) (105 15 60 60)))]
               [shader (make-linear-gradient-shader 0 0 180 0 '("#326DE6" "#EFA02B"))]
               [paint (make-paint #:shader shader)])
     (canvas-clip-region! canvas region)
     (draw-paint canvas paint)))
 #:background 'white)

(render-reference-image
 "image-subrect.png" 220 90
 (lambda (canvas)
   (with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-circle (surface-canvas source) 40 25 18 blue)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-rect canvas image 10 15 80 50 #:sampling 'nearest)
       (draw-image-subrect canvas image 20 5 40 40 125 5 80 80 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "font-bounds.png" 250 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 40)]
               [text-paint (make-paint #:color 'black)]
               [bounds-paint (make-paint #:color 'red #:style 'stroke #:stroke-width 1)]
               [baseline-paint (make-paint #:color "#888888" #:style 'stroke #:stroke-width 1)])
     (define x 25)
     (define y 62)
     (define-values (bx by bw bh) (simple-text-bounds font "Skia"))
     (draw-line canvas 10 y 235 y baseline-paint)
     (draw-simple-text canvas "Skia" x y font text-paint)
     (draw-rect canvas (+ x bx) (+ y by) bw bh bounds-paint)))
 #:background 'white)

(render-reference-image
 "glyph-outline.png" 140 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 70)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
     (define outlines (font-glyph-paths font (font-text->glyphs font "A")))
     (define outline (vector-ref outlines 0))
     (when outline
       (call-with-skia-resource outline
         (lambda (path)
           (with-canvas-state canvas
             (canvas-translate! canvas 35 78)
             (draw-path canvas path paint)))))))
 #:background 'white)

(render-reference-image
 "text-on-path.png" 330 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [shaper (make-shaper font)]
               [path (make-path '((move 15 80) (cubic 85 15 245 15 315 80)))]
               [guide (make-paint #:color "#BBBBBB" #:style 'stroke #:stroke-width 1)]
               [text-paint (make-paint #:color "#20344E")])
     (draw-path canvas path guide)
     (define run (shape-text shaper "Text follows the curve"
                             #:direction 'ltr #:script 'latn #:language "en"))
     (draw-shaped-run/on-path canvas shaper run path text-paint #:start-offset 10)))
 #:background 'white)

(render-reference-image
 "multi-run-text-blob.png" 260 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (text-blob-builder-add-run! builder font (font-text->glyphs font "small")
                                #:origin '(15 38))
     (font-set-size! font 42)
     (text-blob-builder-add-run! builder font (font-text->glyphs font " BIG")
                                #:origin '(105 68))
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "justified-text.png" 320 125
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper
                    "Skia makes drawing fast, portable, and expressive."
                    #:width 280 #:align 'justify-all #:line-height 28))
     (draw-text-layout canvas layout 20 15 paint)))
 #:background 'white)

(render-reference-image
 "picture-shader.png" 180 100
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 36 36
                  (lambda (picture-canvas)
                    (with-skia ([blue (make-paint #:color "#326DE6")]
                                [orange (make-paint #:color "#EFA02B")])
                      (draw-rect picture-canvas 0 0 36 36 blue)
                      (draw-circle picture-canvas 18 18 10 orange))))]
               [shader (make-picture-shader picture #:tile-x 'repeat #:tile-y 'repeat)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 180 100 paint)))
 #:background 'white)

(render-reference-image
 "draw-rasterized.png" 190 105
 (lambda (canvas)
   (draw-rasterized canvas 30 22 120 55
     (lambda (raster-canvas)
       (with-skia ([filter (make-blur-image-filter 5 5)]
                   [paint (make-paint #:color "#326DE6" #:image-filter filter)])
         (draw-rounded-rect raster-canvas 10 8 100 38 10 10 paint)))
     #:scale 2
     #:padding 10))
 #:background 'white)

(render-reference-image
 "raster-buffer-canvas.png" 180 100
 (lambda (canvas)
   (with-skia ([buffer (make-raster-buffer 160 80)])
     (call-with-raster-buffer-canvas
      buffer
      (lambda (buffer-canvas)
        (with-skia ([blue (make-paint #:color "#326DE6")]
                    [orange (make-paint #:color "#EFA02B")])
          (canvas-clear! buffer-canvas 'white)
          (draw-rounded-rect buffer-canvas 15 15 80 50 10 10 blue)
          (draw-circle buffer-canvas 120 40 22 orange))))
     (with-skia ([image (raster-buffer->image buffer)])
       (draw-image canvas image 10 10))))
 #:background 'white)

(render-reference-image
 "scanline-batches.png" 90 60
 (lambda (canvas)
   (with-skia ([source (make-surface 90 60 #:background 'red)]
               [green (make-paint #:color 'green)]
               [blue (make-paint #:color 'blue)])
     (draw-rect (surface-canvas source) 0 20 90 20 green)
     (draw-rect (surface-canvas source) 0 40 90 20 blue)
     (with-skia ([image (surface-snapshot source)]
                 [session (codec-scanline-from-bytes (image->jpeg-bytes image))])
       (for ([count '(20 20 20)])
         (define batch (codec-scanline-read! session count))
         (define first-row (scanline-batch-first-row batch))
         (with-skia ([buffer (scanline-batch->raster-buffer batch)]
                     [part (raster-buffer->image buffer)])
           (draw-image canvas part 0 first-row))))))
 #:background 'white)

(render-reference-image
 "incremental-final.png" 100 70
 (lambda (canvas)
   (with-skia ([source (make-surface 100 70 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")]
               [session (make-codec-incremental)])
     (draw-circle (surface-canvas source) 50 35 24 blue)
     (define encoded (surface->png-bytes source))
     (codec-incremental-feed! session (subbytes encoded 0 1))
     (codec-incremental-step! session)
     (codec-incremental-feed! session (subbytes encoded 1) #:final? #t)
     (define progress (codec-incremental-step! session))
     (unless (eq? (incremental-progress-state progress) 'complete)
       (error 'render-reference-images "incremental decode did not complete"))
     (define snapshot (codec-incremental-snapshot session))
     (with-skia ([buffer (incremental-snapshot->raster-buffer snapshot)]
                 [image (raster-buffer->image buffer)])
       (draw-image canvas image 0 0))))
 #:background 'white)
