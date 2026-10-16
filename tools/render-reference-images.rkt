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

;; Stage 8: sixty-four additional CPU-raster reference images.

(define (make-stage8-tile-image)
  (with-skia ([surface (make-surface 24 24 #:background "#F4D35E")]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas surface) 0 0 12 12 blue)
    (draw-rect (surface-canvas surface) 12 12 12 12 blue)
    (surface-snapshot surface)))

(define (make-stage8-quadrant-image)
  (with-skia ([surface (make-surface 40 40)]
              [red (make-paint #:color 'red)]
              [blue (make-paint #:color 'blue)]
              [green (make-paint #:color 'green)]
              [yellow (make-paint #:color 'yellow)])
    (draw-rect (surface-canvas surface) 0 0 20 20 red)
    (draw-rect (surface-canvas surface) 20 0 20 20 blue)
    (draw-rect (surface-canvas surface) 0 20 20 20 green)
    (draw-rect (surface-canvas surface) 20 20 20 20 yellow)
    (surface-snapshot surface)))

;; Shaders and gradients.

(render-reference-image
 "two-point-conical-offset.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-two-point-conical-gradient-shader
                        35 50 5 145 50 55
                        '("#F4D35E" "#326DE6"))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "image-shader-repeat-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([image (make-stage8-tile-image)]
               [shader (make-image-shader image #:tile-x 'repeat #:tile-y 'repeat)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "image-shader-mirror-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([tile (make-surface 24 24 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-rect (surface-canvas tile) 0 0 12 24 blue)
     (with-skia ([image (surface-snapshot tile)]
                 [shader (make-image-shader image #:tile-x 'mirror #:tile-y 'mirror)]
                 [paint (make-paint #:shader shader)])
       (draw-paint canvas paint)))))

(render-reference-image
 "blend-shader-overlay-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([back (make-linear-gradient-shader
                      0 0 180 0 '("#326DE6" "#F4D35E"))]
               [front (make-radial-gradient-shader 90 50 55 '(white "#E94F37"))]
               [shader (make-blend-shader 'overlay back front)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "shader-local-rotate-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([base (make-linear-gradient-shader
                      0 0 24 0 '(red blue) #:tile-mode 'repeat)]
               [rotated (shader-with-local-matrix base (matrix-rotate-degrees 30))]
               [paint (make-paint #:shader rotated)])
     (draw-paint canvas paint))))

(render-reference-image
 "fractal-noise-tiled-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-fractal-noise-shader
                        0.035 0.045 4 11 #:tile-size '(90 50))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "turbulence-tiled-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-turbulence-shader
                        0.055 0.04 3 19 #:tile-size '(90 50))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "shader-filter-invert-stage8.png" 180 100
 (lambda (canvas)
   (with-skia ([base (make-linear-gradient-shader 0 0 180 0 '(red blue))]
               [filter
                (make-color-matrix-filter
                 '(-1 0 0 0 1
                   0 -1 0 0 1
                   0 0 -1 0 1
                   0 0 0 1 0))]
               [shader (shader-with-color-filter base filter)]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

;; Path effects and mask filters.

(render-reference-image
 "dash-phase-stage8.png" 200 90
 (lambda (canvas)
   (with-skia ([a (make-dash-path-effect '(12 7) 0)]
               [b (make-dash-path-effect '(12 7) 8)]
               [pa (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 5 #:path-effect a)]
               [pb (make-paint #:color "#E94F37" #:style 'stroke
                               #:stroke-width 5 #:path-effect b)])
     (draw-line canvas 15 30 185 30 pa)
     (draw-line canvas 15 62 185 62 pb)))
 #:background 'white)

(render-reference-image
 "corner-radius-stage8.png" 200 100
 (lambda (canvas)
   (for ([radius '(4 16)] [y '(30 72)] [color '("#326DE6" "#E94F37")])
     (with-skia ([effect (make-corner-path-effect radius)]
                 [paint (make-paint #:color color #:style 'stroke
                                    #:stroke-width 5 #:path-effect effect)])
       (draw-polygon canvas
                     `((15 ,y) (65 ,(- y 20)) (115 ,(+ y 10)) (185 ,(- y 15)))
                     paint #:closed? #f))))
 #:background 'white)

(render-reference-image
 "discrete-seed-stage8.png" 200 90
 (lambda (canvas)
   (with-skia ([a (make-discrete-path-effect 11 5 3)]
               [b (make-discrete-path-effect 11 5 29)]
               [pa (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 4 #:path-effect a)]
               [pb (make-paint #:color "#E94F37" #:style 'stroke
                               #:stroke-width 4 #:path-effect b)])
     (draw-line canvas 15 30 185 30 pa)
     (draw-line canvas 15 62 185 62 pb)))
 #:background 'white)

(render-reference-image
 "trim-inverted-stage8.png" 160 110
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [effect (make-trim-path-effect 0.20 0.70 #:mode 'inverted)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 7 #:cap 'round
                                  #:path-effect effect)])
     (path-add-circle! path 80 55 38)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "compose-path-effects-stage8.png" 210 100
 (lambda (canvas)
   (with-skia ([dash (make-dash-path-effect '(15 7))]
               [corner (make-corner-path-effect 10)]
               [effect (make-compose-path-effect dash corner)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 5 #:path-effect effect)])
     (draw-polygon canvas '((15 80) (65 20) (115 80) (195 25))
                   paint #:closed? #f)))
 #:background 'white)

(render-reference-image
 "sum-path-effects-stage8.png" 210 100
 (lambda (canvas)
   (with-skia ([wide (make-dash-path-effect '(22 12))]
               [fine (make-dash-path-effect '(5 9) 3)]
               [effect (make-sum-path-effect wide fine)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 5 #:path-effect effect)])
     (draw-line canvas 15 50 195 50 paint)))
 #:background 'white)

(render-reference-image
 "stamp-morph-stage8.png" 220 110
 (lambda (canvas)
   (with-skia ([stamp (make-path '((move 0 -6) (line 12 0) (line 0 6) (close)))]
               [guide (make-path '((move 15 70) (cubic 70 10 150 100 205 35)))]
               [effect (make-1d-path-effect stamp 20 0 #:style 'morph)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 2 #:path-effect effect)])
     (draw-path canvas guide paint)))
 #:background 'white)

(render-reference-image
 "blur-mask-styles-stage8.png" 240 110
 (lambda (canvas)
   (for ([style '(normal solid outer inner)]
         [x '(35 92 149 206)])
     (with-skia ([mask (make-blur-mask-filter 7 #:style style)]
                 [paint (make-paint #:color "#326DE6" #:mask-filter mask)])
       (draw-circle canvas x 55 20 paint))))
 #:background 'white)

;; Image filters.

(render-reference-image
 "blur-anisotropic-stage8.png" 200 100
 (lambda (canvas)
   (with-skia ([filter (make-blur-image-filter 12 2)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-circle canvas 100 50 26 paint)))
 #:background 'white)

(render-reference-image
 "shadow-only-stage8.png" 200 100
 (lambda (canvas)
   (with-skia ([filter (make-drop-shadow-only-image-filter
                        12 10 5 5 (rgba 32 52 78 170))]
               [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
     (draw-rounded-rect canvas 45 22 90 48 10 10 paint)))
 #:background 'white)

(render-reference-image
 "compose-filter-stage8.png" 220 110
 (lambda (canvas)
   (with-skia ([blur (make-blur-image-filter 5 5)]
               [shift (make-offset-image-filter 45 20)]
               [filter (make-compose-image-filter shift blur)]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-circle canvas 45 42 20 paint)))
 #:background 'white)

(render-reference-image
 "merge-three-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([shift1 (make-offset-image-filter 55 0)]
               [shift2 (make-offset-image-filter 110 0)]
               [filter (make-merge-image-filter (list #f shift1 shift2))]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-circle canvas 30 50 17 paint)))
 #:background 'white)

(render-reference-image
 "morphology-stage8.png" 240 100
 (lambda (canvas)
   (with-skia ([plain (make-paint #:color "#326DE6")]
               [dilate-filter (make-dilate-image-filter 6 6)]
               [erode-filter (make-erode-image-filter 6 6)]
               [dilate (make-paint #:color "#326DE6" #:image-filter dilate-filter)]
               [erode (make-paint #:color "#326DE6" #:image-filter erode-filter)])
     (draw-rect canvas 20 25 45 50 plain)
     (draw-rect canvas 97 25 45 50 dilate)
     (draw-rect canvas 174 25 45 50 erode)))
 #:background 'white)

(render-reference-image
 "convolution-emboss-stage8.png" 200 100
 (lambda (canvas)
   (with-skia ([filter
                (make-matrix-convolution-image-filter
                 3 3 '(-2 -1 0 -1 1 1 0 1 2)
                 #:bias 128)]
               [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
     (draw-rounded-rect canvas 45 22 110 56 10 10 paint)))
 #:background 'white)

(render-reference-image
 "image-source-filter-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([source-surface (make-surface 40 40 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-circle (surface-canvas source-surface) 20 20 13 blue)
     (with-skia ([image (surface-snapshot source-surface)]
                 [filter (make-image-source-filter
                          image #:destination '(20 10 180 80)
                          #:sampling 'nearest)]
                 [paint (make-paint #:image-filter filter)])
       (draw-paint canvas paint))))
 #:background 'white)

(render-reference-image
 "matrix-transform-filter-stage8.png" 220 120
 (lambda (canvas)
   (with-skia ([filter
                (make-matrix-transform-image-filter
                 (matrix-compose (matrix-translate 105 58)
                                 (matrix-rotate-degrees 24)
                                 (matrix-translate -55 -30)))]
               [paint (make-paint #:color "#326DE6" #:image-filter filter)])
     (draw-rect canvas 20 20 90 50 paint)))
 #:background 'white)

;; Drawing primitives.

(render-reference-image
 "line-caps-stage8.png" 220 110
 (lambda (canvas)
   (for ([cap '(butt round square)]
         [y '(25 55 85)]
         [color '("#326DE6" "#E94F37" "#EFA02B")])
     (with-skia ([paint (make-paint #:color color #:style 'stroke
                                    #:stroke-width 14 #:cap cap)])
       (draw-line canvas 45 y 175 y paint))))
 #:background 'white)

(render-reference-image
 "line-joins-stage8.png" 240 120
 (lambda (canvas)
   (for ([join '(miter round bevel)]
         [x '(45 120 195)]
         [color '("#326DE6" "#E94F37" "#EFA02B")])
     (with-skia ([paint (make-paint #:color color #:style 'stroke
                                    #:stroke-width 12 #:join join)])
       (draw-polygon canvas
                     `((,(- x 28) 90) (,x 28) (,(+ x 28) 90))
                     paint #:closed? #f))))
 #:background 'white)

(render-reference-image
 "point-caps-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([round (make-paint #:color "#326DE6"
                                  #:stroke-width 18 #:cap 'round)]
               [square (make-paint #:color "#E94F37"
                                   #:stroke-width 18 #:cap 'square)])
     (for ([x '(25 60 95 130 165 200)])
       (draw-point canvas x 32 round)
       (draw-point canvas x 70 square))))
 #:background 'white)

(render-reference-image
 "arc-open-stage8.png" 200 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 6 #:cap 'round)])
     (draw-arc canvas 30 15 140 70 20 230 paint)))
 #:background 'white)

(render-reference-image
 "arc-wedges-stage8.png" 220 110
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (draw-arc canvas 20 15 80 80 -50 120 blue #:use-center? #t)
     (draw-arc canvas 120 15 80 80 40 220 orange #:use-center? #t)))
 #:background 'white)

(render-reference-image
 "circle-oval-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (draw-circle canvas 60 50 30 blue)
     (draw-oval canvas 125 22 75 56 orange)))
 #:background 'white)

(render-reference-image
 "rounded-rect-radii-stage8.png" 240 110
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-rounded-rect canvas 10 25 65 60 0 0 paint)
     (draw-rounded-rect canvas 88 25 65 60 10 10 paint)
     (draw-rounded-rect canvas 166 25 65 60 28 28 paint)))
 #:background 'white)

(render-reference-image
 "draw-color-blends-stage8.png" 240 100
 (lambda (canvas)
   (canvas-clear! canvas "#EFA02B")
   (for ([mode '(multiply screen difference)]
         [x '(0 80 160)])
     (with-canvas-state canvas
       (canvas-clip-rect! canvas x 0 80 100)
       (draw-color canvas "#326DE6" #:blend-mode mode)))))

;; Paths.

(render-reference-image
 "relative-path-stage8.png" 200 110
 (lambda (canvas)
   (with-skia ([path (make-path '((move 20 85)
                                  (rline 35 -55)
                                  (rline 35 55)
                                  (rline 35 -55)
                                  (rline 35 55)))]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 5 #:join 'round)])
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "quad-cubic-stage8.png" 240 120
 (lambda (canvas)
   (with-skia ([quad (make-path '((move 15 95) (quad 60 10 110 95)))]
               [cubic (make-path '((move 130 95)
                                   (cubic 145 10 210 10 225 95)))]
               [blue (make-paint #:color "#326DE6" #:style 'stroke
                                 #:stroke-width 5)]
               [orange (make-paint #:color "#EFA02B" #:style 'stroke
                                   #:stroke-width 5)])
     (draw-path canvas quad blue)
     (draw-path canvas cubic orange)))
 #:background 'white)

(render-reference-image
 "path-oval-rrect-stage8.png" 240 110
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 5)])
     (path-add-oval! path 15 22 90 65)
     (path-add-rounded-rect! path 135 22 90 65 18 18)
     (draw-path canvas path paint)))
 #:background 'white)

(render-reference-image
 "reverse-difference-stage8.png" 180 110
 (lambda (canvas)
   (with-skia ([a (make-path)] [b (make-path)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-circle! a 65 55 38)
     (path-add-circle! b 108 55 31)
     (with-skia ([result (path-reverse-difference a b)])
       (draw-path canvas result paint))))
 #:background 'white)

(render-reference-image
 "simplify-path-stage8.png" 200 110
 (lambda (canvas)
   (with-skia ([path (make-path '((move 20 90) (line 100 15)
                                  (line 180 90) (line 40 45)
                                  (line 160 45) (close)))]
               [paint (make-paint #:color "#326DE6")])
     (with-skia ([simple (path-simplify path)])
       (draw-path canvas simple paint))))
 #:background 'white)

(render-reference-image
 "as-winding-stage8.png" 200 110
 (lambda (canvas)
   (with-skia ([path (make-path #:fill-rule 'even-odd)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-circle! path 100 55 43)
     (path-add-circle! path 100 55 20)
     (with-skia ([winding (path-as-winding path)])
       (draw-path canvas winding paint))))
 #:background 'white)

(render-reference-image
 "measure-tangent-stage8.png" 240 120
 (lambda (canvas)
   (with-skia ([path (make-path '((move 20 90)
                                  (cubic 70 10 170 10 220 90)))]
               [measure (make-path-measure path)]
               [curve (make-paint #:color "#BBBBBB" #:style 'stroke
                                  #:stroke-width 3)]
               [mark (make-paint #:color "#326DE6")]
               [tangent (make-paint #:color "#326DE6" #:style 'stroke
                                    #:stroke-width 3)])
     (draw-path canvas path curve)
     (define distance (/ (path-measure-length measure) 2))
     (define-values (x y tx ty)
       (path-measure-position+tangent measure distance))
     (draw-circle canvas x y 6 mark)
     (draw-line canvas x y
                (+ x (* 30 tx)) (+ y (* 30 ty))
                tangent)))
 #:background 'white)

(render-reference-image
 "svg-path-stage8.png" 220 120
 (lambda (canvas)
   (with-skia ([path
                (svg-path->path
                 "M20 38 C20 12 55 12 55 38 C55 12 90 12 90 38 C90 65 55 88 55 88 C55 88 20 65 20 38 Z")]
               [paint (make-paint #:color "#E94F37")])
     (with-canvas-state canvas
       (canvas-translate! canvas 45 5)
       (canvas-scale! canvas 1.25 1.15)
       (draw-path canvas path paint))))
 #:background 'white)

;; Images.

(render-reference-image
 "nearest-upscale-stage8.png" 180 90
 (lambda (canvas)
   (with-skia ([image (rgba-bytes->image
                       2 2
                       (bytes 255 0 0 255   0 0 255 255
                              0 128 0 255   255 215 0 255))])
     (draw-image-rect canvas image 20 10 140 70 #:sampling 'nearest)))
 #:background 'white)

(render-reference-image
 "linear-upscale-stage8.png" 180 90
 (lambda (canvas)
   (with-skia ([image (rgba-bytes->image
                       2 2
                       (bytes 255 0 0 255   0 0 255 255
                              0 128 0 255   255 215 0 255))])
     (draw-image-rect canvas image 20 10 140 70 #:sampling 'linear)))
 #:background 'white)

(render-reference-image
 "stretch-image-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 60 60 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-circle (surface-canvas source) 30 30 20 blue)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-rect canvas image 15 25 190 50))))
 #:background 'white)

(render-reference-image
 "subrect-crop-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")]
               [red (make-paint #:color "#E94F37")])
     (draw-circle (surface-canvas source) 22 25 17 blue)
     (draw-circle (surface-canvas source) 58 25 17 red)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-subrect canvas image
                           40 0 40 50
                           35 15 150 70))))
 #:background 'white)

(render-reference-image
 "subset-quadrants-stage8.png" 240 110
 (lambda (canvas)
   (with-skia ([image (make-stage8-quadrant-image)])
     (for ([x0 '(0 20 0 20)] [y0 '(0 0 20 20)] [x '(10 70 130 190)])
       (with-skia ([part (image-subset image x0 y0 20 20)])
         (draw-image-rect canvas part x 25 40 60 #:sampling 'nearest)))))
 #:background 'white)

(render-reference-image
 "image-alpha-rows-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 80 50)]
               [blue (make-paint #:color (rgba 50 109 230 120))]
               [red (make-paint #:color (rgba 233 79 55 180))])
     (draw-circle (surface-canvas source) 28 25 22 blue)
     (draw-circle (surface-canvas source) 52 25 22 red)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-rect canvas image 30 15 160 70))))
 #:background "#F4D35E")

(render-reference-image
 "image-grid-repeat-stage8.png" 220 110
 (lambda (canvas)
   (with-skia ([tile (make-surface 30 30 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-circle (surface-canvas tile) 15 15 10 blue)
     (with-skia ([image (surface-snapshot tile)])
       (for* ([row (in-range 3)] [column (in-range 6)])
         (draw-image canvas image
                     (+ 10 (* column 34)) (+ 8 (* row 34)))))))
 #:background 'white)

(render-reference-image
 "image-native-size-stage8.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-rounded-rect (surface-canvas source) 10 8 60 34 8 8 blue)
     (with-skia ([image (surface-snapshot source)])
       (draw-image canvas image 20 25))))
 #:background 'white)

;; Text blobs.

(render-reference-image
 "blob-run-origins-stage8.png" 280 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 28)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (text-blob-builder-add-run! builder font (font-text->glyphs font "TOP")
                                #:origin '(20 38))
     (text-blob-builder-add-run! builder font (font-text->glyphs font "BOTTOM")
                                #:origin '(95 92))
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "blob-positioned-wave-stage8.png" 280 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#326DE6")])
     (define glyphs (font-text->glyphs font "WAVE"))
     (text-blob-builder-add-positioned-run!
      builder font glyphs '((15 65) (75 42) (135 70) (200 35)))
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "blob-horizontal-spacing-stage8.png" 280 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (define glyphs (font-text->glyphs font "ABCD"))
     (text-blob-builder-add-horizontal-run! builder font glyphs
                                           '(0 45 115 205) #:y 0)
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 20 62 paint))))
 #:background 'white)

(render-reference-image
 "blob-transformed-fan-stage8.png" 300 130
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#326DE6")])
     (define glyphs (font-text->glyphs font "FAN"))
     (text-blob-builder-add-transformed-run!
      builder font glyphs
      (list (make-atlas-transform 65 95 #:rotation -28)
            (make-atlas-transform 145 78 #:rotation 0)
            (make-atlas-transform 225 95 #:rotation 28)))
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "blob-shaped-run-stage8.png" 280 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 34)]
               [shaper (make-shaper font)]
               [builder (make-text-blob-builder)]
               [paint (make-paint #:color "#20344E")])
     (define text "office")
     (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
     (text-blob-builder-add-shaped-run! builder shaper run
                                       #:origin '(25 62) #:text text)
     (with-skia ([blob (text-blob-builder-finish! builder)])
       (draw-text-blob canvas blob 0 0 paint))))
 #:background 'white)

(render-reference-image
 "glyphs-to-path-stage8.png" 240 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 42)]
               [paint (make-paint #:color "#326DE6")])
     (define glyphs (font-text->glyphs font "PATH"))
     (with-skia ([path
                  (positioned-glyphs->path
                   font glyphs '((10 65) (60 65) (115 65) (170 65)))])
       (draw-path canvas path paint))))
 #:background 'white)

(render-reference-image
 "text-path-offset-stage8.png" 330 130
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [shaper (make-shaper font)]
               [path (make-path '((move 15 72) (line 315 72)))]
               [guide (make-paint #:color "#BBBBBB" #:style 'stroke)]
               [paint (make-paint #:color "#20344E")])
     (draw-path canvas path guide)
     (define run (shape-text shaper "offset from the path"
                             #:direction 'ltr #:script 'latn))
     (draw-shaped-run/on-path canvas shaper run path paint
                              #:start-offset 25 #:normal-offset -14)))
 #:background 'white)

(render-reference-image
 "text-path-circle-stage8.png" 260 180
 (lambda (canvas)
   (with-skia ([font (make-font #:size 22)]
               [shaper (make-shaper font)]
               [path (make-path)]
               [guide (make-paint #:color "#CCCCCC" #:style 'stroke)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-circle! path 130 90 65)
     (draw-path canvas path guide)
     (define run (shape-text shaper "ROUND"
                             #:direction 'ltr #:script 'latn))
     (draw-shaped-run/on-path canvas shaper run path paint
                              #:start-offset 20 #:normal-offset -6)))
 #:background 'white)

;; Text layout.

(render-reference-image
 "layout-left-stage8.png" 300 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "One two three four five six."
                    #:width 260 #:align 'left))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "layout-right-stage8.png" 300 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "One two three four five six."
                    #:width 260 #:align 'right))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "layout-center-stage8b.png" 300 120
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "One two three four five six."
                    #:width 260 #:align 'center))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "layout-justify-stage8.png" 320 130
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper
                    "One two three four five six seven eight nine."
                    #:width 280 #:align 'justify))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "layout-justify-all-stage8.png" 320 130
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper
                    "One two three four five six seven eight nine."
                    #:width 280 #:align 'justify-all))
     (draw-text-layout canvas layout 20 16 paint)))
 #:background 'white)

(render-reference-image
 "layout-rtl-stage8.png" 300 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 22)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "אבג דהו זחט" #:width 260
                    #:direction 'rtl #:align 'start))
     (draw-text-layout canvas layout 20 18 paint)))
 #:background 'white)

(render-reference-image
 "layout-nowrap-stage8.png" 360 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "Wrapping is disabled for this long single line."
                    #:width #f))
     (draw-text-layout canvas layout 10 20 paint)))
 #:background 'white)

(render-reference-image
 "layout-narrow-stage8.png" 260 170
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "A narrow box produces many short wrapped lines."
                    #:width 105 #:line-height 24))
     (draw-text-layout canvas layout 20 14 paint)))
 #:background 'white)
;; Stage 9: retained visual examples after consolidation.



;; canvases

(render-reference-image
 "canvas-reset-transform-stage9.png" 200 110
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (canvas-translate! canvas 95 20)
     (draw-rect canvas 0 0 70 45 blue)
     (canvas-reset-transform! canvas)
     (draw-rect canvas 20 45 70 45 orange))
)
 #:background 'white)

(render-reference-image
 "canvas-set-transform-stage9.png" 200 110
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (canvas-set-transform!
      canvas
      (matrix-compose (matrix-translate 55 25)
                      (matrix-scale 1.6 0.75)))
     (draw-rect canvas 0 0 70 65 paint))
)
 #:background 'white)

(render-reference-image
 "canvas-nested-state-stage9.png" 200 110
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (draw-rounded-rect canvas 15 18 55 40 8 8 blue)
     (with-canvas-state canvas
       (canvas-translate! canvas 62 18)
       (draw-rounded-rect canvas 15 18 55 40 8 8 orange)
       (with-canvas-state canvas
         (canvas-translate! canvas 62 18)
         (canvas-rotate! canvas 12)
         (draw-rounded-rect canvas 15 18 55 40 8 8 blue))))
)
 #:background 'white)

(render-reference-image
 "clip-antialias-stage9.png" 220 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")]
               [separator (make-paint #:color "#BCC5CF" #:style 'stroke #:stroke-width 1)])
     (with-canvas-state canvas
       (canvas-clip-rect! canvas 15.5 15.5 75 68 #:antialias? #f)
       (draw-paint canvas paint))
     (with-canvas-state canvas
       (canvas-clip-rect! canvas 129.5 15.5 75 68 #:antialias? #t)
       (draw-paint canvas paint))
     (draw-line canvas 110 8 110 92 separator))
)
 #:background 'white)

(render-reference-image
 "clip-path-circle-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-circle! path 90 50 38)
     (canvas-clip-path! canvas path #:antialias? #t)
     (draw-paint canvas paint))
)
 #:background 'white)

(render-reference-image
 "clip-rrect-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (define shape (make-rounded-rect 22 15 136 70 #:radii 24))
     (canvas-clip-rounded-rect! canvas shape #:antialias? #t)
     (draw-paint canvas paint))
)
 #:background 'white)

(render-reference-image
 "transform-order-stage9.png" 240 110
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (with-canvas-state canvas
       (canvas-clip-rect! canvas 0 0 120 110)
       (canvas-translate! canvas 20 25)
       (canvas-scale! canvas 1.6 1)
       (draw-rect canvas 0 0 45 55 blue))
     (with-canvas-state canvas
       (canvas-clip-rect! canvas 120 0 120 110)
       (canvas-scale! canvas 1.6 1)
       (canvas-translate! canvas 82 25)
       (draw-rect canvas 0 0 45 55 orange)))
)
 #:background 'white)

(render-reference-image
 "rotate-around-point-stage9.png" 200 120
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")]
               [axis (make-paint #:color "#AEB7C2" #:style 'stroke #:stroke-width 1)])
     (draw-line canvas 100 12 100 108 axis)
     (draw-line canvas 18 60 182 60 axis)
     (with-canvas-state canvas
       (canvas-translate! canvas 100 60)
       (canvas-rotate! canvas 30)
       (draw-rect canvas -55 -20 110 40 paint)))
)
 #:background 'white)



;; paints

(render-reference-image
 "paint-hairline-stage9.png" 200 90
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6" #:style 'stroke
                                  #:stroke-width 0 #:antialias? #t)])
     (draw-line canvas 15 20 185 20 paint)
     (draw-line canvas 15 45 185 55 paint)
     (draw-line canvas 15 75 185 60 paint))
)
 #:background 'white)

(render-reference-image
 "paint-alpha-stage9.png" 200 100
 (lambda (canvas)
   (with-skia ([orange (make-paint #:color "#EFA02B")]
               [blue (make-paint #:color (rgba 50 109 230 145))])
     (draw-circle canvas 78 50 34 orange)
     (draw-circle canvas 120 50 34 blue))
)
 #:background 'white)

(render-reference-image
 "paint-antialias-stage9.png" 220 100
 (lambda (canvas)
   (with-skia ([hard (make-paint #:color "#326DE6" #:style 'stroke
                                 #:stroke-width 7 #:antialias? #f)]
               [smooth (make-paint #:color "#326DE6" #:style 'stroke
                                   #:stroke-width 7 #:antialias? #t)]
               [separator (make-paint #:color "#BCC5CF" #:style 'stroke #:stroke-width 1)])
     (draw-line canvas 18 82 94 18 hard)
     (draw-line canvas 128 82 204 18 smooth)
     (draw-line canvas 110 8 110 92 separator))
)
 #:background 'white)

;; shaders

(render-reference-image
 "image-shader-decal-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([source (make-surface 12 12 #:background 'red)]
               [blue (make-paint #:color "#326DE6")])
     (draw-rect (surface-canvas source) 6 0 6 12 blue)
     (with-skia ([image (surface-snapshot source)]
                 [base (make-image-shader image #:tile-x 'decal #:tile-y 'decal
                                          #:sampling 'nearest)]
                 [shader (shader-with-local-matrix base (matrix-scale 8 8))]
                 [paint (make-paint #:shader shader)])
       (draw-paint canvas paint)))
)
 #:background 'white)

(render-reference-image
 "empty-shader-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([blue-shader (make-color-shader "#326DE6")]
               [empty-shader (make-empty-shader)]
               [blue (make-paint #:shader blue-shader)]
               [empty (make-paint #:shader empty-shader)]
               [border (make-paint #:color "#607080" #:style 'stroke #:stroke-width 2)])
     (draw-rect canvas 15 18 65 64 blue)
     (draw-rect canvas 100 18 65 64 empty)
     (draw-rect canvas 100 18 65 64 border))
)
 #:background 'white)



;; path-effects

(render-reference-image
 "gamma-mask-stage9.png" 220 100
 (lambda (canvas)
   (with-skia ([light (make-gamma-mask-filter 0.5)]
               [dark (make-gamma-mask-filter 2.0)]
               [p1 (make-paint #:color "#326DE6" #:mask-filter light)]
               [p2 (make-paint #:color "#326DE6" #:mask-filter dark)])
     (draw-circle canvas 65 50 34 p1)
     (draw-circle canvas 155 50 34 p2))
)
 #:background 'white)



;; image-filters

(render-reference-image
 "shader-source-filter-stage9.png" 200 100
 (lambda (canvas)
   (with-skia ([shader (make-linear-gradient-shader 20 0 180 0 '(red blue))]
               [filter (make-shader-image-filter shader #:crop '(10 10 180 80))]
               [paint (make-paint #:color 'white #:image-filter filter)])
     (draw-paint canvas paint))
)
 #:background 'white)



;; drawing

(render-reference-image
 "arc-chord-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-arc canvas 28 18 124 64 205 250 paint #:use-center? #f))
)
 #:background 'white)

(render-reference-image
 "draw-color-clipped-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [orange (make-paint #:color "#EFA02B")])
     (draw-paint canvas orange)
     (path-add-circle! path 90 50 36)
     (canvas-clip-path! canvas path #:antialias? #t)
     (draw-color canvas "#326DE6"))
)
 #:background 'white)



;; paths

(render-reference-image
 "path-polygon-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([path (make-path)]
               [paint (make-paint #:color "#326DE6")])
     (path-add-polygon! path '((90 12) (160 42) (136 88) (44 88) (20 42)))
     (draw-path canvas path paint))
)
 #:background 'white)

(render-reference-image
 "path-extend-stage9.png" 220 100
 (lambda (canvas)
   (with-skia ([source-a (make-path '((move 60 24) (line 92 76)))]
               [append-path (make-path '((move 18 76) (line 50 24)))]
               [source-b (make-path '((move 170 24) (line 202 76)))]
               [extend-path (make-path '((move 128 76) (line 160 24)))]
               [blue (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5
                                 #:cap 'round)]
               [orange (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 5
                                   #:cap 'round)])
     (path-add-path! append-path source-a #:mode 'append)
     (path-add-path! extend-path source-b #:mode 'extend)
     (draw-path canvas append-path blue)
     (draw-path canvas extend-path orange))
)
 #:background 'white)

;; images

;; Additional Reference visual examples.

(render-reference-image
 "float-source-space-stage10.png" 210 80
 (lambda (canvas)
   (with-skia ([srgb-paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                                #:color-space 'srgb)]
               [linear-paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                                  #:color-space 'linear-srgb)])
     (draw-rect canvas 15 15 80 50 srgb-paint)
     (draw-rect canvas 115 15 80 50 linear-paint)))
 #:background 'white)

(render-reference-image
 "float-radial-stage10.png" 180 100
 (lambda (canvas)
   (with-skia ([shader
                (make-radial-gradient-color4f-shader
                 '(90 50) 55
                 (list (make-color4f 1 1 1) (make-color4f 0.2 0.43 0.9))
                 #:color-space 'srgb)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 180 100 paint)))
 #:background 'white)

(render-reference-image
 "float-sweep-stage10.png" 180 100
 (lambda (canvas)
   (with-skia ([shader
                (make-sweep-gradient-color4f-shader
                 '(90 50)
                 (list (make-color4f 1 0 0)
                       (make-color4f 0 1 0)
                       (make-color4f 0 0 1)
                       (make-color4f 1 0 0))
                 #:color-space 'srgb)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 180 100 paint)))
 #:background 'white)

(render-reference-image
 "float-conical-stage10.png" 190 105
 (lambda (canvas)
   (with-skia ([shader
                (make-two-point-conical-gradient-color4f-shader
                 '(55 52) 5 '(135 52) 58
                 (list (make-color4f 1 0.63 0.17) (make-color4f 0.2 0.43 0.9))
                 #:color-space 'srgb)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 190 105 paint)))
 #:background 'white)

(render-reference-image
 "lattice-native-stage10.png" 200 120
 (lambda (canvas)
   (with-skia ([source (make-surface 30 30 #:background "#F4D35E")]
               [blue (make-paint #:color "#326DE6")])
     (draw-rect (surface-canvas source) 0 0 30 7 blue)
     (draw-rect (surface-canvas source) 0 23 30 7 blue)
     (draw-rect (surface-canvas source) 0 0 7 30 blue)
     (draw-rect (surface-canvas source) 23 0 7 30 blue)
     (with-skia ([image (surface-snapshot source)])
       (define lattice (make-image-lattice '(7 23) '(7 23)))
       (draw-image-lattice canvas image lattice 15 10 170 100 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "lattice-fixed-color-stage10.png" 200 120
 (lambda (canvas)
   (with-skia ([source (make-surface 30 30 #:background "#E8EEF9")])
     (with-skia ([image (surface-snapshot source)])
       (define lattice
         (make-image-lattice
          '(10 20) '(10 20)
          #:cell-types '(default fixed-color default
                         fixed-color transparent fixed-color
                         default fixed-color default)
          #:colors '(white "#326DE6" white
                     "#10988E" transparent "#EFA02B"
                     white "#E94F37" white)))
       (draw-image-lattice canvas image lattice 15 10 170 100 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "atlas-tints-stage10.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 20 20 #:background 'white)])
     (with-skia ([image (surface-snapshot source)])
       (draw-atlas canvas image
                   (list (make-atlas-transform 20 20 #:scale 2.5)
                         (make-atlas-transform 90 20 #:scale 2.5)
                         (make-atlas-transform 160 20 #:scale 2.5))
                   '((0 0 20 20) (0 0 20 20) (0 0 20 20))
                   #:colors '(red green blue)
                   #:blend-mode 'modulate
                   #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "portable-nine-alpha-stage10.png" 200 120
 (lambda (canvas)
   (with-skia ([source (make-surface 30 30 #:background "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (draw-circle (surface-canvas source) 15 15 8 orange)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-nine/portable canvas image '(8 8 14 14) 15 10 170 100
                                 #:sampling 'nearest #:alpha 128))))
 #:background 'white)

(render-reference-image
 "portable-lattice-stage10.png" 200 120
 (lambda (canvas)
   (with-skia ([source (make-surface 30 30 #:background "#E8EEF9")]
               [blue (make-paint #:color "#326DE6")])
     (draw-rect (surface-canvas source) 0 0 10 30 blue)
     (draw-rect (surface-canvas source) 20 0 10 30 blue)
     (with-skia ([image (surface-snapshot source)])
       (define lattice (make-image-lattice '(10 20) '(10 20)))
       (draw-image-lattice/portable canvas image lattice 15 10 170 100 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "portable-atlas-alpha-stage10.png" 220 100
 (lambda (canvas)
   (with-skia ([source (make-surface 18 18 #:background "#326DE6")])
     (with-skia ([image (surface-snapshot source)])
       (draw-atlas/portable canvas image
                            (list (make-atlas-transform 25 20 #:scale 2.5)
                                  (make-atlas-transform 95 20 #:scale 2.5)
                                  (make-atlas-transform 165 20 #:scale 2.5))
                            '((0 0 18 18) (0 0 18 18) (0 0 18 18))
                            #:sampling 'nearest #:alpha 110))))
 #:background 'white)

(render-reference-image
 "font-embolden-stage10.png" 280 105
 (lambda (canvas)
   (with-skia ([normal (make-font #:size 36)]
               [bold (make-font #:size 36 #:embolden? #t)]
               [paint (make-paint #:color "#20344E")])
     (draw-simple-text canvas "Skia" 15 42 normal paint)
     (draw-simple-text canvas "Skia" 15 92 bold paint)))
 #:background 'white)

(render-reference-image
 "font-break-prefix-stage10.png" 320 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 30)]
               [gray (make-paint #:color "#A0A7B0")]
               [blue (make-paint #:color "#326DE6")]
               [rule (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
     (define text "Skia for Racket")
     (draw-simple-text canvas text 15 55 font gray)
     (define-values (count width) (font-break-text font text 145))
     (draw-simple-text canvas (substring text 0 count) 15 55 font blue)
     (draw-line canvas 15 70 (+ 15 width) 70 rule)))
 #:background 'white)

(render-reference-image
 "shaping-kern-stage10.png" 320 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 38)]
               [shaper (make-shaper font)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")])
     (define kerned (shape-text shaper "AVATAR" #:direction 'ltr #:script 'latn))
     (define unkerned (shape-text shaper "AVATAR" #:direction 'ltr #:script 'latn
                                  #:features '("kern=0")))
     (draw-shaped-run canvas shaper kerned 20 42 blue)
     (draw-shaped-run canvas shaper unkerned 20 94 orange)))
 #:background 'white)

(render-reference-image
 "shaped-positions-stage10.png" 320 110
 (lambda (canvas)
   (with-skia ([font (make-font #:size 38)]
               [shaper (make-shaper font)]
               [text-paint (make-paint #:color "#20344E")]
               [mark (make-paint #:color "#E94F37")])
     (define run (shape-text shaper "office" #:direction 'ltr #:script 'latn))
     (draw-shaped-run canvas shaper run 20 62 text-paint)
     (for ([position (in-list (shaped-run-positions run))])
       (draw-circle canvas (+ 20 (car position)) (+ 62 (cadr position)) 2.5 mark))))
 #:background 'white)

(render-reference-image
 "shaped-advance-stage10.png" 320 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 38)]
               [shaper (make-shaper font)]
               [text-paint (make-paint #:color "#20344E")]
               [rule (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
     (define run (shape-text shaper "Skia" #:direction 'ltr #:script 'latn))
     (define advance (abs (shaped-run-advance-x run)))
     (draw-shaped-run canvas shaper run 20 58 text-paint)
     (draw-line canvas 20 75 (+ 20 advance) 75 rule)))
 #:background 'white)

(render-reference-image
 "picture-shader-mirror-stage10.png" 220 110
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 36 36
                  (lambda (pc)
                    (with-skia ([blue (make-paint #:color "#326DE6")]
                                [orange (make-paint #:color "#EFA02B")])
                      (draw-rect pc 0 0 36 36 blue)
                      (draw-circle pc 10 18 8 orange))))]
               [shader (make-picture-shader picture #:tile-x 'mirror #:tile-y 'mirror)]
               [paint (make-paint #:shader shader)])
     (draw-rect canvas 0 0 220 110 paint)))
 #:background 'white)

(render-reference-image
 "picture-image-background-stage10.png" 220 110
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture 50 35
                  (lambda (pc)
                    (with-skia ([blue (make-paint #:color (rgba 50 109 230 180))])
                      (draw-circle pc 25 18 15 blue))))]
               [image (picture->image picture 160 90 #:background "#F4D35E")])
     (draw-image canvas image 30 10)))
 #:background 'white)

(render-reference-image
 "picture-nested-stage10.png" 220 110
 (lambda (canvas)
   (with-skia ([child
                (call-with-picture 35 35
                  (lambda (pc)
                    (with-skia ([orange (make-paint #:color "#EFA02B")])
                      (draw-circle pc 18 18 13 orange))))])
     (with-skia ([parent
                  (call-with-picture 100 60
                    (lambda (pc)
                      (with-skia ([blue (make-paint #:color "#326DE6")])
                        (draw-rounded-rect pc 0 0 100 60 12 12 blue))
                      (draw-picture pc child #:x 10 #:y 12)
                      (draw-picture pc child #:x 55 #:y 12)))])
       (draw-picture canvas parent #:x 60 #:y 25))))
 #:background 'white)

(render-reference-image
 "drawable-to-picture-stage10.png" 220 110
 (lambda (canvas)
   (with-skia ([drawable
                (call-with-drawable 60 40
                  (lambda (dc)
                    (with-skia ([blue (make-paint #:color "#326DE6")]
                                [orange (make-paint #:color "#EFA02B")])
                      (draw-rounded-rect dc 0 0 60 40 10 10 blue)
                      (draw-circle dc 30 20 10 orange))))]
               [picture (drawable->picture drawable)])
     (draw-picture canvas picture #:x 25 #:y 20)
     (draw-picture canvas picture #:x 120 #:y 35 #:width 80 #:height 54)))
 #:background 'white)

(render-reference-image
 "output-page-no-clip-stage10.png" 220 120
 (lambda (canvas)
   (define page
     (make-output-page 220 120
       (lambda (pc)
         (with-skia ([blue (make-paint #:color "#326DE6")])
           (draw-circle pc 0 0 45 blue)))
       #:margins 25 #:clip? #f #:background "#EEF1F4"))
   (with-skia ([image (output-page->image page #:dpi 72)])
     (draw-image canvas image 0 0)))
 #:background 'white)

(render-reference-image
 "output-page-background-stage10.png" 220 120
 (lambda (canvas)
   (define page
     (make-output-page 220 120
       (lambda (pc)
         (with-skia ([orange (make-paint #:color "#EFA02B")])
           (draw-circle pc 90 45 32 orange)))
       #:margins 20 #:background "#326DE6"))
   (with-skia ([image (output-page->image page #:dpi 72)])
     (draw-image canvas image 0 0)))
 #:background 'white)

(render-reference-image
 "draw-output-page-rotated-stage10.png" 240 140
 (lambda (canvas)
   (define page
     (make-output-page 100 60
       (lambda (pc)
         (with-skia ([blue (make-paint #:color "#326DE6")])
           (draw-rounded-rect pc 0 0 100 60 10 10 blue)))
       #:background "#EEF1F4"))
   (with-canvas-state canvas
     (canvas-translate! canvas 70 35)
     (canvas-rotate! canvas 12)
     (draw-output-page canvas page)))
 #:background 'white)
