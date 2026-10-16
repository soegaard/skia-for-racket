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

;; Stage 7: sixty-four additional visual examples.

(define (draw-reference-checkerboard canvas x y width height [cell 10])
  (with-skia ([light (make-paint #:color "#F1F3F5")]
              [dark (make-paint #:color "#D9DEE4")])
    (for* ([row (in-range (ceiling (/ height cell)))]
           [col (in-range (ceiling (/ width cell)))])
      (define rx (+ x (* col cell)))
      (define ry (+ y (* row cell)))
      (draw-rect canvas rx ry
                 (min cell (- (+ x width) rx))
                 (min cell (- (+ y height) ry))
                 (if (even? (+ row col)) light dark)))))

(define (make-reference-quadrant-image)
  (with-skia ([surface (make-surface 4 4 #:background 'red)]
              [green (make-paint #:color 'green)]
              [blue (make-paint #:color 'blue)]
              [yellow (make-paint #:color 'yellow)])
    (define canvas (surface-canvas surface))
    (draw-rect canvas 2 0 2 2 green)
    (draw-rect canvas 0 2 2 2 blue)
    (draw-rect canvas 2 2 2 2 yellow)
    (surface-snapshot surface)))

(define (make-reference-motif-image)
  (with-skia ([surface (make-surface 40 30 #:background "#F4D35E")]
              [blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (define canvas (surface-canvas surface))
    (draw-circle canvas 12 15 9 blue)
    (draw-rect canvas 24 6 12 18 orange)
    (surface-snapshot surface)))

(define (make-reference-overlap-path operation)
  (with-skia ([left (make-path)] [right (make-path)])
    (path-add-circle! left 65 50 34)
    (path-add-circle! right 105 50 34)
    (path-op left right operation)))

(define (make-reference-region-result operation)
  (with-skia ([a (make-region '((20 15 90 55)))]
              [b (make-region '((70 30 80 50)))])
    (region-op a b operation)))

;; Paint styles and blending.

(render-reference-image
 "paint-caps.png" 180 100
 (lambda (canvas)
   (for ([cap '(butt round square)] [y '(20 50 80)])
     (with-skia ([paint (make-paint #:color "#326DE6"
                                    #:style 'stroke
                                    #:stroke-width 18
                                    #:cap cap)])
       (draw-line canvas 35 y 145 y paint))))
 #:background 'white)

(render-reference-image
 "paint-joins.png" 210 100
 (lambda (canvas)
   (for ([join '(miter round bevel)] [x '(10 80 150)])
     (with-skia ([paint (make-paint #:color "#326DE6"
                                    #:style 'stroke
                                    #:stroke-width 12
                                    #:join join
                                    #:miter-limit 8)])
       (draw-polygon canvas
                     (list (list (+ x 5) 80)
                           (list (+ x 30) 20)
                           (list (+ x 55) 80))
                     paint #:closed? #f))))
 #:background 'white)

(render-reference-image
 "paint-stroke-widths.png" 180 100
 (lambda (canvas)
   (for ([width '(2 8 18)] [y '(20 50 80)])
     (with-skia ([paint (make-paint #:color "#326DE6"
                                    #:style 'stroke
                                    #:stroke-width width
                                    #:cap 'round)])
       (draw-line canvas 20 y 160 y paint))))
 #:background 'white)

(render-reference-image
 "blend-multiply.png" 180 100
 (lambda (canvas)
   (with-skia ([background (make-paint #:color "#326DE6")]
               [source (make-paint #:color "#EFA02B" #:blend-mode 'multiply)])
     (draw-rect canvas 25 20 95 60 background)
     (draw-circle canvas 115 50 36 source)))
 #:background 'white)

(render-reference-image
 "blend-screen.png" 180 100
 (lambda (canvas)
   (with-skia ([background (make-paint #:color "#326DE6")]
               [source (make-paint #:color "#EFA02B" #:blend-mode 'screen)])
     (draw-rect canvas 25 20 95 60 background)
     (draw-circle canvas 115 50 36 source)))
 #:background 'white)

(render-reference-image
 "paint-stroke-and-fill.png" 180 100
 (lambda (canvas)
   (with-skia ([under (make-paint #:color "#EFA02B")]
               [paint (make-paint #:color (rgba 50 109 230 190)
                                  #:style 'stroke-and-fill
                                  #:stroke-width 10)])
     (draw-circle canvas 90 50 34 under)
     (draw-rounded-rect canvas 45 22 90 56 14 14 paint)))
 #:background 'white)

;; Canvas transforms and clipping.

(render-reference-image
 "canvas-translate.png" 180 100
 (lambda (canvas)
   (with-skia ([guide (make-paint #:color "#D9DEE4")]
               [paint (make-paint #:color "#326DE6")])
     (draw-rect canvas 20 20 50 35 guide)
     (with-canvas-state canvas
       (canvas-translate! canvas 75 30)
       (draw-rect canvas 20 20 50 35 paint))))
 #:background 'white)

(render-reference-image
 "canvas-scale.png" 180 110
 (lambda (canvas)
   (with-skia ([guide (make-paint #:color "#D9DEE4")]
               [paint (make-paint #:color "#326DE6")])
     (draw-rect canvas 18 18 45 30 guide)
     (with-canvas-state canvas
       (canvas-translate! canvas 75 20)
       (canvas-scale! canvas 1.8 1.6)
       (draw-rect canvas 0 0 45 30 paint))))
 #:background 'white)

(render-reference-image
 "canvas-rotate.png" 180 120
 (lambda (canvas)
   (with-skia ([guide (make-paint #:color "#D9DEE4")]
               [paint (make-paint #:color "#326DE6")])
     (draw-rect canvas 55 40 70 40 guide)
     (with-canvas-state canvas
       (canvas-translate! canvas 90 60)
       (canvas-rotate! canvas 28)
       (draw-rect canvas -35 -20 70 40 paint))))
 #:background 'white)

(render-reference-image
 "canvas-skew.png" 180 110
 (lambda (canvas)
   (with-skia ([guide (make-paint #:color "#D9DEE4")]
               [paint (make-paint #:color "#326DE6")])
     (draw-rect canvas 25 30 60 45 guide)
     (with-canvas-state canvas
       (canvas-translate! canvas 85 0)
       (canvas-skew! canvas 0.55 0)
       (draw-rect canvas 0 30 60 45 paint))))
 #:background 'white)

(render-reference-image
 "clip-intersect.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (canvas-clip-rect! canvas 20 15 120 70)
     (canvas-clip-rect! canvas 65 30 90 45 #:operation 'intersect)
     (draw-paint canvas paint)))
 #:background 'white)

(render-reference-image
 "clip-difference.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (canvas-clip-rect! canvas 20 15 140 70)
     (canvas-clip-rect! canvas 60 30 60 40 #:operation 'difference)
     (draw-paint canvas paint)))
 #:background 'white)

;; Shader transformations, noise, filtering, and tiling.

(render-reference-image
 "shader-local-matrix.png" 180 100
 (lambda (canvas)
   (with-skia ([base (make-linear-gradient-shader 0 0 30 0 '(red blue)
                                                 #:tile-mode 'repeat)]
               [scaled (shader-with-local-matrix base (matrix-scale 2 1))]
               [top (make-paint #:shader base)]
               [bottom (make-paint #:shader scaled)])
     (draw-rect canvas 0 0 180 45 top)
     (draw-rect canvas 0 55 180 45 bottom))))

(render-reference-image
 "fractal-noise.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-fractal-noise-shader 0.035 0.05 4 7)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "turbulence.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-turbulence-shader 0.035 0.05 4 7)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "shader-color-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([base (make-linear-gradient-shader 0 0 180 0 '(red yellow green blue))]
               [filter (make-luma-color-filter)]
               [filtered (shader-with-color-filter base filter)]
               [paint (make-paint #:shader filtered)])
     (draw-reference-checkerboard canvas 0 0 180 90)
     (draw-rect canvas 0 0 180 90 paint))))

(render-reference-image
 "raw-image-shader.png" 180 100
 (lambda (canvas)
   (with-skia ([image (make-reference-quadrant-image)]
               [shader (make-raw-image-shader image
                                              #:tile-x 'repeat
                                              #:tile-y 'repeat
                                              #:sampling 'nearest
                                              #:matrix (matrix-scale 12 12))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "gradient-tile-modes.png" 200 120
 (lambda (canvas)
   (with-skia ([background (make-paint #:color "#E9EDF2")])
     (draw-paint canvas background))
   (for ([mode '(clamp repeat mirror decal)]
         [y '(0 30 60 90)])
     (with-skia ([shader (make-linear-gradient-shader 30 0 70 0 '(red blue)
                                                     #:tile-mode mode)]
                 [paint (make-paint #:shader shader)])
       (draw-rect canvas 0 y 200 30 paint)))))

;; Color-filter composition.

(render-reference-image
 "blend-color-filter.png" 180 80
 (lambda (canvas)
   (with-skia ([filter (make-blend-color-filter 'orange 'screen)]
               [plain (make-paint #:color "#326DE6")]
               [filtered (make-paint #:color "#326DE6" #:color-filter filter)])
     (draw-rounded-rect canvas 18 18 60 44 8 8 plain)
     (draw-rounded-rect canvas 102 18 60 44 8 8 filtered)))
 #:background 'white)

(render-reference-image
 "compose-color-filter.png" 180 80
 (lambda (canvas)
   (with-skia ([inner (make-blend-color-filter 'red 'src)]
               [outer (make-blend-color-filter 'blue 'screen)]
               [filter (make-compose-color-filter outer inner)]
               [plain (make-paint #:color "#EFA02B")]
               [filtered (make-paint #:color "#EFA02B" #:color-filter filter)])
     (draw-rounded-rect canvas 18 18 60 44 8 8 plain)
     (draw-rounded-rect canvas 102 18 60 44 8 8 filtered)))
 #:background 'white)

(render-reference-image
 "lerp-color-filter.png" 180 80
 (lambda (canvas)
   (with-skia ([red-filter (make-blend-color-filter 'red 'src)]
               [blue-filter (make-blend-color-filter 'blue 'src)]
               [filter (make-lerp-color-filter 0.5 red-filter blue-filter)]
               [paint (make-paint #:color 'white #:color-filter filter)])
     (draw-rounded-rect canvas 35 16 110 48 10 10 paint)))
 #:background 'white)

(render-reference-image
 "luma-color-filter.png" 180 90
 (lambda (canvas)
   (draw-reference-checkerboard canvas 0 0 180 90)
   (with-skia ([shader (make-linear-gradient-shader 0 0 180 0 '(red yellow green cyan blue))]
               [filter (make-luma-color-filter)]
               [paint (make-paint #:shader shader #:color-filter filter)])
     (draw-rect canvas 0 0 180 90 paint))))

(render-reference-image
 "high-contrast-color-filter.png" 180 80
 (lambda (canvas)
   (with-skia ([shader (make-linear-gradient-shader 0 0 180 0 '(black white))]
               [filter (make-high-contrast-color-filter #:contrast 0.8)]
               [paint (make-paint #:shader shader #:color-filter filter)])
     (draw-rect canvas 0 0 180 80 paint))))

(render-reference-image
 "table-color-filter.png" 180 80
 (lambda (canvas)
   (define table
     (for/vector ([i (in-range 256)]) (min 255 (* 2 i))))
   (with-skia ([filter (make-table-color-filter table)]
               [plain (make-paint #:color "#326DE6")]
               [filtered (make-paint #:color "#326DE6" #:color-filter filter)])
     (draw-rounded-rect canvas 18 18 60 44 8 8 plain)
     (draw-rounded-rect canvas 102 18 60 44 8 8 filtered)))
 #:background 'white)

;; Image-filter graph examples.

(render-reference-image
 "offset-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([guide (make-paint #:color "#D9DEE4")]
               [filter (make-offset-image-filter 55 20)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-rect canvas 20 15 45 35 guide)
     (draw-rect canvas 20 15 45 35 paint)))
 #:background 'white)

(render-reference-image
 "blend-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([shift (make-offset-image-filter 55 0)]
               [filter (make-blend-image-filter 'src-over #f shift)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-rounded-rect canvas 20 25 50 40 8 8 paint)))
 #:background 'white)

(render-reference-image
 "arithmetic-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([shift (make-offset-image-filter 50 0)]
               [filter (make-arithmetic-image-filter 0 0.5 0.5 0 #f shift)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-circle canvas 45 45 25 paint)))
 #:background 'white)

(render-reference-image
 "crop-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([filter (make-crop-image-filter '(65 20 60 50))]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)]
               [outline (make-paint #:color "#9AA3AD" #:style 'stroke #:stroke-width 1)])
     (draw-rounded-rect canvas 25 10 120 70 10 10 paint)
     (draw-rect canvas 65 20 60 50 outline)))
 #:background 'white)

(render-reference-image
 "color-filter-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([color-filter
                (make-color-matrix-filter
                 '(0 0 0 0 1
                   0 0 0 0 0
                   0 0 0 0 0
                   0 0 0 1 0))]
               [filter (make-color-filter-image-filter color-filter)]
               [plain (make-paint #:color 'blue)]
               [filtered (make-paint #:color 'blue #:image-filter filter)])
     (draw-circle canvas 50 45 24 plain)
     (draw-circle canvas 130 45 24 filtered)))
 #:background 'white)

(render-reference-image
 "matrix-transform-image-filter.png" 190 110
 (lambda (canvas)
   (with-skia ([filter
                (make-matrix-transform-image-filter
                 (matrix-compose (matrix-translate 75 10)
                                 (matrix-rotate-degrees 22)))]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)]
               [guide (make-paint #:color "#D9DEE4")])
     (draw-rect canvas 20 35 60 35 guide)
     (draw-rect canvas 20 35 60 35 paint)))
 #:background 'white)

(render-reference-image
 "shader-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([shader (make-linear-gradient-shader 20 0 160 0 '(red yellow blue))]
               [filter (make-shader-image-filter shader #:crop '(20 15 140 60))]
               [paint (make-paint #:color 'white #:image-filter filter)])
     (draw-rect canvas 0 0 180 90 paint)))
 #:background 'white)

(render-reference-image
 "tile-image-filter.png" 180 90
 (lambda (canvas)
   (with-skia ([image (make-reference-motif-image)]
               [source (make-image-source-filter image)]
               [filter (make-tile-image-filter '(0 0 40 30) '(0 0 180 90)
                                               #:input source)]
               [paint (make-paint #:color 'white #:image-filter filter)])
     (draw-rect canvas 0 0 180 90 paint)))
 #:background 'white)

;; Path geometry, measurement, and set operations.

(render-reference-image
 "quadratic-path.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)])
     (path-move-to! path 15 80)
     (path-quad-to! path 90 5 165 80)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "conic-path.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)])
     (path-move-to! path 15 80)
     (path-conic-to! path 90 5 165 80 0.45)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "path-arc.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)])
     (path-add-arc! path 25 15 130 70 200 250)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "path-transform.png" 190 120
 (lambda (canvas)
   (with-skia ([source (make-path '((move 20 85) (line 70 20) (line 110 85) (close)))]
               [guide (make-paint #:color "#D9DEE4")]
               [paint (make-paint #:color "#326DE6")])
     (draw-path canvas source guide)
     (with-skia ([moved
                  (path-transform
                   source
                   (matrix-compose (matrix-translate 55 5)
                                   (matrix-rotate-degrees 12)))])
       (draw-path canvas moved paint))))
 #:background 'white)

(render-reference-image
 "path-measure-segment.png" 190 80
 (lambda (canvas)
   (with-skia ([path (make-path '((move 20 40) (line 170 40)))]
               [measure (make-path-measure path)]
               [guide (make-paint #:color "#C8CDD3" #:style 'stroke #:stroke-width 6)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 6)])
     (draw-path canvas path guide)
     (with-skia ([segment (path-measure-segment measure 35 120)])
       (draw-path canvas segment paint))))
 #:background 'white)

(render-reference-image
 "path-union.png" 170 100
 (lambda (canvas)
   (with-skia ([path (make-reference-overlap-path 'union)]
               [paint (make-paint #:color "#326DE6")])
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "path-intersection.png" 170 100
 (lambda (canvas)
   (with-skia ([path (make-reference-overlap-path 'intersect)]
               [paint (make-paint #:color "#326DE6")])
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "path-xor.png" 170 100
 (lambda (canvas)
   (with-skia ([path (make-reference-overlap-path 'xor)]
               [paint (make-paint #:color "#326DE6")])
     (draw-path canvas path paint)))
 #:background 'white)

;; Rounded rectangles and integer-region set operations.

(render-reference-image
 "rounded-rect-normalized.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")]
               [outline (make-paint #:color "#AAB1B9" #:style 'stroke #:stroke-width 1)])
     (define shape (make-rounded-rect 25 20 130 60 #:radii 80))
     (define normalized (rounded-rect-normalize shape))
     (draw-rect canvas 25 20 130 60 outline)
     (draw-rrect canvas normalized paint)))
 #:background 'white)

(render-reference-image
 "rounded-rect-nine-patch.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (define shape (make-nine-patch-rounded-rect 20 15 140 70 30 10 16 28))
     (draw-rrect canvas shape paint)))
 #:background 'white)

(render-reference-image
 "region-intersection.png" 180 100
 (lambda (canvas)
   (with-skia ([region (make-reference-region-result 'intersect)]
               [paint (make-paint #:color "#326DE6")])
     (draw-region canvas region paint)))
 #:background 'white)

(render-reference-image
 "region-xor.png" 180 100
 (lambda (canvas)
   (with-skia ([region (make-reference-region-result 'xor)]
               [paint (make-paint #:color "#326DE6")])
     (draw-region canvas region paint)))
 #:background 'white)

;; Image sampling, subsets, alpha, and reflected drawing.

(render-reference-image
 "sampling-comparison.png" 210 100
 (lambda (canvas)
   (with-skia ([image (make-reference-quadrant-image)])
     (draw-image-rect canvas image 10 10 85 80 #:sampling 'nearest)
     (draw-image-rect canvas image 115 10 85 80 #:sampling 'linear)))
 #:background 'white)

(render-reference-image
 "image-subset.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 80 60 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-circle (surface-canvas source) 40 30 22 blue)
     (with-skia ([image (surface-snapshot source)]
                 [part (image-subset image 20 10 40 40)])
       (draw-image-rect canvas image 10 20 80 60 #:sampling 'nearest)
       (draw-image-rect canvas part 125 5 80 80 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "image-alpha-paint.png" 200 90
 (lambda (canvas)
   (with-skia ([source (make-surface 40 40 #:background "#326DE6")]
               [image (surface-snapshot source)]
               [alpha-paint (make-paint #:color (rgba 255 255 255 100))]
               [background (make-paint #:color "#EFA02B")])
     (draw-rect canvas 0 0 200 90 background)
     (draw-image-rect canvas image 20 20 50 50 #:sampling 'nearest)
     (draw-image-rect canvas image 125 20 50 50 #:sampling 'nearest #:paint alpha-paint)))
 #:background 'white)

(render-reference-image
 "image-mirror.png" 220 90
 (lambda (canvas)
   (with-skia ([image
                (rgba-bytes->image 2 1
                                   (bytes 255 0 0 255 0 0 255 255))])
     (draw-image-rect canvas image 15 20 80 50 #:sampling 'nearest)
     (with-canvas-state canvas
       (canvas-translate! canvas 205 20)
       (canvas-scale! canvas -1 1)
       (draw-image-rect canvas image 0 0 80 50 #:sampling 'nearest))))
 #:background 'white)

;; Font controls and shaping.

(render-reference-image
 "font-sizes.png" 250 130
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [paint (make-paint #:color "#20344E")])
     (draw-simple-text canvas "Skia" 15 30 font paint)
     (font-set-size! font 30)
     (draw-simple-text canvas "Skia" 15 72 font paint)
     (font-set-size! font 44)
     (draw-simple-text canvas "Skia" 100 112 font paint)))
 #:background 'white)

(render-reference-image
 "font-scale-x.png" 260 100
 (lambda (canvas)
   (with-skia ([normal (make-font #:size 34)]
               [wide (make-font #:size 34)]
               [paint (make-paint #:color "#20344E")])
     (font-set-scale-x! wide 1.7)
     (draw-simple-text canvas "Skia" 15 42 normal paint)
     (draw-simple-text canvas "Skia" 15 86 wide paint)))
 #:background 'white)

(render-reference-image
 "font-skew-x.png" 260 100
 (lambda (canvas)
   (with-skia ([normal (make-font #:size 34)]
               [skewed (make-font #:size 34)]
               [paint (make-paint #:color "#20344E")])
     (font-set-skew-x! skewed 0.4)
     (draw-simple-text canvas "Skia" 15 42 normal paint)
     (draw-simple-text canvas "Skia" 15 86 skewed paint)))
 #:background 'white)

(render-reference-image
 "ligature-shaping.png" 300 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [shaper (make-shaper font)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (define default-run (shape-text shaper "office" #:language "en"))
     (define no-liga-run
       (shape-text shaper "office" #:language "en" #:features '("liga=0")))
     (draw-shaped-run canvas shaper default-run 20 42 blue)
     (draw-shaped-run canvas shaper no-liga-run 20 92 orange)))
 #:background 'white)

(render-reference-image
 "rtl-shaping.png" 260 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 36)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (draw-shaped-text canvas shaper "שלום" 230 58 paint
                       #:direction 'rtl #:script 'hebr)))
 #:background 'white)

(render-reference-image
 "shaped-outline.png" 240 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 60)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
     (define run (shape-text shaper "Skia" #:direction 'ltr #:script 'latn))
     (with-skia ([path (shaped-run->path shaper run)])
       (with-canvas-state canvas
         (canvas-translate! canvas 20 78)
         (draw-path canvas path paint)))))
 #:background 'white)

;; Text-blob positioning and paragraph layout.

(render-reference-image
 "horizontal-text-run.png" 240 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 32)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (define glyphs (font-text->glyphs font "ABC"))
     (text-blob-builder-add-horizontal-run! builder font glyphs '(0 55 125) #:y 0)
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 20 58 paint))))
 #:background 'white)

(render-reference-image
 "transformed-text-run.png" 260 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (define glyphs (font-text->glyphs font "ABC"))
     (text-blob-builder-add-transformed-run!
      builder font glyphs
      (list (make-atlas-transform 30 70 #:rotation -18)
            (make-atlas-transform 100 55 #:scale 1.2 #:rotation 8)
            (make-atlas-transform 185 75 #:scale 0.9 #:rotation 22)))
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "text-blob-intercepts.png" 240 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 42)]
               [blob
                (make-positioned-text-blob font
                                           (font-text->glyphs font "AB")
                                           '((0 55) (70 55)))]
               [text-paint (make-paint #:color "#20344E")]
               [band-paint (make-paint #:color (rgba 239 160 43 80))]
               [mark-paint (make-paint #:color "#D24A3A")])
     (draw-text-blob canvas blob 20 10 text-paint)
     (draw-rect canvas 20 45 190 10 band-paint)
     (for ([interval (in-vector (text-blob-intercepts blob 35 45))])
       (draw-rect canvas (+ 20 (car interval)) 48
                  (- (cadr interval) (car interval)) 4 mark-paint))))
 #:background 'white)

(render-reference-image
 "layout-center.png" 300 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 20)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "Centered lines wrap inside a fixed width."
                    #:width 260 #:align 'center #:line-height 30))
     (draw-text-layout canvas layout 20 15 paint)))
 #:background 'white)

(render-reference-image
 "layout-end.png" 300 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 22)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "End aligned" #:width 250 #:align 'end))
     (draw-text-layout canvas layout 20 20 paint)))
 #:background 'white)

(render-reference-image
 "layout-line-height.png" 320 160
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (define text "One two three four five six seven eight.")
     (define tight (layout-text shaper text #:width 130 #:line-height 20))
     (define loose (layout-text shaper text #:width 130 #:line-height 34))
     (draw-text-layout canvas tight 10 10 blue)
     (draw-text-layout canvas loose 175 10 orange)))
 #:background 'white)

;; Picture playback, rasterization, drawables, and output-page margins.

(render-reference-image
 "picture-scaled.png" 180 120
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 40 30
                  (lambda (picture-canvas)
                    (with-skia ([blue (make-paint #:color "#326DE6")]
                                [orange (make-paint #:color "#EFA02B")])
                      (draw-rect picture-canvas 0 0 40 30 blue)
                      (draw-circle picture-canvas 20 15 9 orange))))])
     (draw-picture canvas picture #:x 25 #:y 15 #:width 130 #:height 90)))
 #:background 'white)

(render-reference-image
 "picture-rasterized.png" 180 120
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 40 30
                  (lambda (picture-canvas)
                    (with-skia ([blue (make-paint #:color "#326DE6")]
                                [orange (make-paint #:color "#EFA02B")])
                      (draw-rect picture-canvas 0 0 40 30 blue)
                      (draw-circle picture-canvas 20 15 9 orange))))]
               [image (picture->image picture 130 90 #:background 'white)])
     (draw-image canvas image 25 15)))
 #:background 'white)

(render-reference-image
 "drawable-transformed.png" 200 120
 (lambda (canvas)
   (with-skia ([drawable
                (call-with-drawable 50 35
                  (lambda (recording-canvas)
                    (with-skia ([paint (make-paint #:color "#326DE6")])
                      (draw-rounded-rect recording-canvas 5 5 40 25 7 7 paint))))])
     (draw-drawable canvas drawable
                    #:matrix (matrix-compose (matrix-translate 40 45)
                                             (matrix-rotate-degrees -18)))
     (draw-drawable canvas drawable
                    #:matrix (matrix-compose (matrix-translate 120 30)
                                             (matrix-scale 1.25 1.25)
                                             (matrix-rotate-degrees 18))
                    #:mode 'immediate)))
 #:background 'white)

(render-reference-image
 "output-page-margins.png" 180 100
 (lambda (canvas)
   (define page
     (make-output-page
      180 100
      (lambda (page-canvas)
        (with-skia ([paint (make-paint #:color "#326DE6")])
          (draw-rect page-canvas 0 0 130 70 paint)))
      #:margins '(20 15 30 15)
      #:background "#EEF1F4"))
   (with-skia ([image (output-page->image page #:dpi 72)])
     (draw-image canvas image 0 0)))
 #:background 'white)
