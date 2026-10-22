#lang racket/base

;;;
;;; Reference Figure Renderer
;;;

;; Renders API examples and conceptual diagrams into the Reference image directory.
;; This documentation build tool keeps published figures tied to executable Skia drawing fixtures.

;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/list
         racket/runtime-path
         racket/class
         (prefix-in draw: racket/draw)
         skia
         skia/dc
         skia/dc-output
         skia/output
         skia/pict
         skia/racket-draw
         (only-in skia/codec-scanlines
                  codec-scanline-from-bytes codec-scanline-read!
                  scanline-batch-first-row scanline-batch->raster-buffer)
         (only-in skia/codec-incremental
                  make-codec-incremental codec-incremental-feed!
                  codec-incremental-step! incremental-progress-state
                  codec-incremental-snapshot incremental-snapshot->raster-buffer)
         (prefix-in pict: pict))


;;;
;;; Rendering and Annotation Helpers
;;;

; output-directory : path?
;   Locates ../scribblings/reference/images relative to this module, independent of the invoking
;   directory.
(define-runtime-path output-directory "../scribblings/reference/images")


; device-scale : exact-positive-integer?
;   Sets the PNG backing resolution to twice the logical dimensions used in manual examples.
(define device-scale 2)


; output-path : path-string? -> path?
;   Resolves a generated image filename beneath the Reference image directory.
(define (output-path filename)
  (build-path output-directory filename))

;; Conceptual figures use the same small visual vocabulary throughout the
;; Reference.  Keep the annotations in this generator: their coordinates are
;; derived from the fixture below rather than being hand-drawn after rendering.

; one-decimal : real? -> string?
;   Formats measured diagram values rounded to one decimal place.
(define (one-decimal value)
  (number->string (/ (round (* 10.0 value)) 10.0)))


; draw-arrow : canvas? real? real? real? real? paint? -> void?
;   Draws a directed line and a filled triangular head at its second endpoint.
(define (draw-arrow canvas x1 y1 x2 y2 paint)
  (draw-line canvas x1 y1 x2 y2 paint)
  (define angle (atan (- y2 y1) (- x2 x1)))
  (define wing 6)
  (define (point delta)
    (list (+ x2 (* wing (cos (+ angle delta))))
          (+ y2 (* wing (sin (+ angle delta))))))
  (draw-polygon canvas (list (list x2 y2) (point 2.55) (point -2.55)) paint))


; draw-corner-bracket : canvas? real? real? real? real? paint? -> void?
;   Marks a rectangle's four corners without obscuring the content inside it.
(define (draw-corner-bracket canvas x y width height paint)
  (define size 7)
  (for ([x0 (list x (+ x width))] [sx '(1 -1)])
    (for ([y0 (list y (+ y height))] [sy '(1 -1)])
      (draw-line canvas x0 y0 (+ x0 (* sx size)) y0 paint)
      (draw-line canvas x0 y0 x0 (+ y0 (* sy size)) paint))))


; make-reference-surface : exact-positive-integer? exact-positive-integer? [any/c] -> surface?
;   Creates an owned raster surface at the presentation scale, optionally initializing its
;   background.
(define (make-reference-surface width height [background #f])
  (if background
      (make-surface (* device-scale width)
                    (* device-scale height)
                    #:background background)
      (make-surface (* device-scale width)
                    (* device-scale height))))


; render-reference-image : path-string? exact-positive-integer? exact-positive-integer? procedure?
; [#:background any/c] -> void?
;   Draws in logical coordinates on a scaled surface and replaces the named Reference PNG.
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

;; Some examples deliberately replace the canvas transform or inspect
;; single-device-pixel coverage.  Render those programs at their literal target
;; size, then enlarge the captured result for the Reference's 2x PNG convention.
;; Applying `device-scale` before their program would change the example itself.

; render-native-scale-reference-image : path-string? exact-positive-integer? exact-positive-integer?
; procedure? [#:background any/c #:sampling symbol?] -> void?
;   Renders at literal example dimensions before enlarging the completed image, preserving examples
;   that reset the canvas matrix.
(define (render-native-scale-reference-image filename width height draw
                                              #:background [background #f]
                                              #:sampling [sampling 'nearest])
  (make-directory* output-directory)
  (with-skia ([source (if background
                          (make-surface width height #:background background)
                          (make-surface width height))])
    (draw (surface-canvas source))
    (with-skia ([image (surface-snapshot source)]
                [presentation (make-surface (* device-scale width)
                                            (* device-scale height))])
      (draw-image-rect (surface-canvas presentation) image 0 0
                       (* device-scale width) (* device-scale height)
                       #:sampling sampling)
      (define path (output-path filename))
      (save-png presentation path #:exists 'replace)
      (printf "wrote ~a\n" path))))

;; Hebrew fixtures must use one face with verified coverage.  Font-manager
;; fallback selects that face once; it does not supply a different face while
;; shaping the displayed string.  The log records the host-dependent face and
;; native versions used for a regenerated fixture.

; call-with-hebrew-font : string? real? string? procedure? -> any
;   Scopes a fallback face and font covering the requested Hebrew text and records the chosen
;   native versions.
(define (call-with-hebrew-font label size text proc)
  (with-skia ([manager (make-font-manager)])
    (define face
      (font-manager-match-character manager (string-ref text 0) #:languages '("he")))
    (unless face (error label "no Hebrew-capable typeface is available"))
    (with-skia ([chosen-face face] [font (make-font chosen-face #:size size)])
      (unless (for/and ([char (in-string text)] #:unless (char-whitespace? char))
                (positive? (font-char->glyph font char)))
        (error label "the selected typeface does not cover ~s" text))
      (printf "~a: Hebrew face ~a; Skia ~a; HarfBuzz ~a\n"
              label (typeface-family-name chosen-face)
              (skia-native-version) (harfbuzz-native-version))
      (proc font))))


; make-reference-bottom-up-bmp : -> bytes?
;   Builds a two-by-three bottom-up 24-bit BMP with distinct colors and padded rows for decoder
;   diagrams.
(define (make-reference-bottom-up-bmp)
  ;; Two pixels per row, three rows, uncompressed BGR24, four-byte row alignment.
  ;; Top-to-bottom colors: red/green, blue/white, yellow/black.
  (define output (make-bytes 78))
  (define (put offset value size)
    (bytes-copy! output offset (integer->integer-bytes value size #f #f)))
  (bytes-copy! output 0 #"BM")
  (for ([offset '(2 10 14 18 22 26 28 34)] [value '(78 54 40 2 3 1 24 24)]
        [size '(4 4 4 4 4 2 2 4)])
    (put offset value size))
  (bytes-copy! output 54 (bytes 0 255 255 0 0 0 0 0))
  (bytes-copy! output 62 (bytes 255 0 0 255 255 255 0 0))
  (bytes-copy! output 70 (bytes 0 0 255 0 255 0 0 0))
  output)

;;;
;;; Core Drawing, Canvas State, Effects, and Transforms
;;;

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
 "draw-path-roundtrip.png" 200 150
 (lambda (canvas)
   (define source-path (new draw:dc-path%))
   (send source-path rectangle 2 2 20 14)
   (with-skia ([path (dc-path->skia-path source-path #:fill-style 'winding)])
     (define-values (copy fill-style) (skia-path->dc-path path))
     (define bitmap (draw:make-bitmap 24 18 #t))
     (define bitmap-dc (new draw:bitmap-dc% [bitmap bitmap]))
     (send bitmap-dc set-pen "black" 1 'transparent)
     (send bitmap-dc set-brush "blue" 'solid)
     (send bitmap-dc draw-path copy 0 0 fill-style)
     (send bitmap-dc set-bitmap #f)
     (with-skia ([image (bitmap->image bitmap #:mask #f)]
                 [font (make-font #:size 13)]
                 [label (make-paint #:color "#20344E")]
                 [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
       (draw-simple-text canvas "Draw -> Skia -> Draw (winding)" 20 20 font label)
       (draw-image-rect canvas image 20 30 160 120 #:sampling 'nearest)
       (draw-rect canvas 20 30 160 120 outline))))
 #:background 'white)

(render-reference-image
 "draw-path-conic-approximation.png" 280 150
 (lambda (canvas)
   (with-skia ([path (make-path '((move 0 0) (conic 10 20 20 0 0.5)))]
               [native-surface (make-surface 24 24 #:background 'white)]
               [native-paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1.5)])
     (define-values (copy fill-style) (skia-path->dc-path path #:conic-subdivisions 4))
     (draw-path (surface-canvas native-surface) path native-paint)
     (define bitmap (draw:make-bitmap 24 24 #t))
     (define bitmap-dc (new draw:bitmap-dc% [bitmap bitmap]))
     (send bitmap-dc set-pen "blue" 2 'solid)
     (send bitmap-dc set-brush "black" 'transparent)
     (send bitmap-dc draw-path copy 1 1 fill-style)
     (send bitmap-dc set-bitmap #f)
     (with-skia ([native-image (surface-snapshot native-surface)]
                 [draw-image (bitmap->image bitmap #:mask #f)]
                 [font (make-font #:size 12)]
                 [label (make-paint #:color "#20344E")]
                 [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
       (draw-simple-text canvas "native Skia conic" 20 20 font label)
       (draw-simple-text canvas "Draw approx., power 4" 150 20 font label)
       (draw-image-rect canvas native-image 20 32 110 110 #:sampling 'nearest)
       (draw-image-rect canvas draw-image 150 32 110 110 #:sampling 'nearest)
       (draw-rect canvas 20 32 110 110 outline)
       (draw-rect canvas 150 32 110 110 outline))))
 #:background 'white)

(render-reference-image
 "image-rgba-alpha.png" 200 100
 (lambda (canvas)
   (with-skia ([image (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 128))]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas "opaque red" 20 20 font label)
     (draw-simple-text canvas "blue alpha 128" 105 20 font label)
     (for* ([row (in-range 3)] [column (in-range 8)])
       (draw-rect canvas (+ 20 (* column 20)) (+ 35 (* row 20)) 20 20
                  (if (even? (+ row column)) light dark)))
     (draw-image-rect canvas image 20 35 160 50 #:sampling 'nearest)
     (draw-rect canvas 20 35 160 50 outline)))
 #:background 'white)

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
 "surface-snapshot-independence.png" 220 100
 (lambda (canvas)
   (with-skia ([surface (make-surface 2 1 #:background 'red)]
               [snapshot (surface-snapshot surface)]
               [font (make-font #:size 14)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (canvas-clear! (surface-canvas surface) 'blue)
     (with-skia ([current (surface-snapshot surface)])
       (draw-simple-text canvas "snapshot" 20 20 font label)
       (draw-simple-text canvas "current surface" 120 20 font label)
       (draw-image-rect canvas snapshot 20 30 80 40 #:sampling 'nearest)
       (draw-image-rect canvas current 120 30 80 40 #:sampling 'nearest)
       (draw-rect canvas 20 30 80 40 outline)
       (draw-rect canvas 120 30 80 40 outline))))
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
 "layer-options-clip.png" 96 96
 (lambda (canvas)
   (with-skia ([surface (make-surface 16 16)]
               [ink (make-paint #:color 'blue)]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")])
     (define layer-canvas (surface-canvas surface))
     (call-with-canvas-layer/options
      layer-canvas
      (lambda () (draw-rect layer-canvas 0 0 16 16 ink))
      #:options (make-layer-options #:bounds '(0 0 16 16))
      #:clip '(2 2 12 12))
     (for* ([row (in-range 16)] [column (in-range 16)])
       (draw-rect canvas (* column 6) (* row 6) 6 6
                  (if (even? (+ row column)) light dark)))
     (with-skia ([image (surface-snapshot surface)])
       (draw-image-rect canvas image 0 0 96 96 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "layer-backdrop-initialization.png" 420 155
 (lambda (canvas)
   (with-skia ([base (make-paint #:color "#DCEAF8")]
               [stripe-a (make-paint #:color "#326DE6")]
               [stripe-b (make-paint #:color "#EFA02B")]
               [dot (make-paint #:color "#7D5BA6")]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [clip-outline (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
               [border (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (define (draw-pattern target)
       (draw-paint target base)
       (for ([x (in-range -10 130 20)])
         (draw-rect target x 0 10 85
                    (if (even? (quotient (+ x 10) 20)) stripe-a stripe-b)))
       (draw-circle target 78 42 21 dot))
     (define zone '(25 20 70 46))
     (define (render-panel kind)
       (with-skia ([page (make-surface 120 85)]
                   [replace (make-paint #:blend-mode 'src)])
         (define layer-canvas (surface-canvas page))
         (draw-pattern layer-canvas)
         (case kind
           [(empty)
            (call-with-canvas-layer/options layer-canvas void #:paint replace
                                        #:options (make-layer-options #:bounds zone)
                                        #:clip zone)]
           [(initialized)
            (call-with-canvas-layer/options layer-canvas void #:paint replace
                                        #:options (make-layer-options #:bounds zone
                                                                      #:initialize-with-previous? #t)
                                        #:clip zone)]
           [(backdrop)
            (with-skia ([blur (make-blur-image-filter 4 4)])
              (call-with-canvas-layer/options layer-canvas void #:paint replace #:backdrop blur
                                          #:options (make-layer-options #:bounds zone)
                                          #:clip zone))])
         (surface-snapshot page)))
     (with-skia ([empty-image (render-panel 'empty)]
                 [initialized-image (render-panel 'initialized)]
                 [backdrop-image (render-panel 'backdrop)])
       (for ([title '("empty src layer" "initialize previous" "backdrop blur")]
             [x '(12 150 290)])
         (draw-simple-text canvas title x 17 font label))
       (for ([image (list empty-image initialized-image backdrop-image)]
             [x '(12 150 290)])
         (draw-image canvas image x 30)
         (draw-rect canvas x 30 120 85 border)
         (draw-rect canvas (+ x 25) 50 70 46 clip-outline))
       (draw-simple-text canvas "same striped-and-circle backdrop; orange is the explicit clip" 12
         135 font label))))
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
 "color-space-interpretation.png" 220 100
 (lambda (canvas)
   (with-skia ([srgb (make-srgb-color-space)]
               [linear (make-linear-srgb-color-space)]
               [encoded (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space srgb)]
               [light (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space linear)]
               [surface (make-surface 2 1 #:color-space srgb)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (define result-canvas (surface-canvas surface))
     (draw-image result-canvas encoded 0 0)
     (draw-image result-canvas light 1 0)
     (with-skia ([result (surface-snapshot surface)])
       (draw-simple-text canvas "sRGB 128" 24 20 font label)
       (draw-simple-text canvas "linear 188" 126 20 font label)
       (draw-image-rect canvas result 20 30 180 50 #:sampling 'nearest)
       (draw-rect canvas 20 30 180 50 outline))))
 #:background 'white)

(render-reference-image
 "image-color-space-conversion.png" 220 100
 (lambda (canvas)
   (with-skia ([linear (make-linear-srgb-color-space)]
               [srgb (make-srgb-color-space)]
               [source (rgba-bytes->image 1 1 (bytes 128 128 128 255))]
               [converted (image-convert-color-space source srgb #:source-color-space linear)]
               [preview-surface (make-surface 2 1 #:color-space srgb)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     ;; The untagged source is shown under this explicitly declared sRGB
     ;; preview interpretation; conversion itself happens only on the right.
     (define preview-canvas (surface-canvas preview-surface))
     (draw-image preview-canvas source 0 0)
     (draw-image preview-canvas converted 1 0)
     (with-skia ([result (surface-snapshot preview-surface)])
       (draw-simple-text canvas "source 128" 20 20 font label)
       (draw-simple-text canvas "converted 188" 128 20 font label)
       (draw-image-rect canvas result 20 30 180 50 #:sampling 'nearest)
       (draw-rect canvas 20 30 180 50 outline))))
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
 "runtime-blender-consumers.png" 420 270
 (lambda (canvas)
   (with-skia ([font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [color-effect (make-runtime-effect
                              "half4 main(half4 c) { return half4(c.b,c.g*0.5,c.r,c.a); }"
                              #:kind 'color-filter)]
               [color-filter (runtime-effect->color-filter color-effect)]
               [orange (make-paint #:color "#E94F37")]
               [filtered-orange (make-paint #:color "#E94F37" #:color-filter color-filter)]
               [child-effect (make-runtime-effect
                               "uniform shader child; half4 main(float2 p) { half4 c=child.eval(p); return half4(c.b,c.g*0.4,c.r,c.a); }")]
               [child-gradient (make-linear-gradient-shader 220 0 400 0 '(red blue))]
               [child-shader (runtime-effect->shader child-effect
                                                     #:children (hash 'child child-gradient))]
               [child-paint (make-paint #:shader child-shader)]
               [blender-effect (make-runtime-effect
                                 "half4 main(half4 src, half4 dst) { return half4(src.r,dst.g,dst.b,1); }"
                                #:kind 'blender)]
               [paint-blender (runtime-effect->blender blender-effect)]
               [shader-blender (runtime-effect->blender blender-effect)]
               [filter-blender (runtime-effect->blender blender-effect)]
               [destination (make-paint #:color "#1769E0")]
               [source (make-paint #:color "#E94F37")]
               [source-with-blender (make-paint #:color "#E94F37")]
               [destination-shader (make-color-shader "#1769E0")]
               [source-shader (make-color-shader "#E94F37")]
               [combined-shader (make-blender-shader shader-blender
                                                      destination-shader source-shader)]
               [shader-paint (make-paint #:shader combined-shader)]
               [destination-filter (make-shader-image-filter destination-shader
                                                              #:crop '(290 130 110 55))]
               [source-filter (make-shader-image-filter source-shader
                                                         #:crop '(290 130 110 55))]
               [combined-filter (make-blender-image-filter filter-blender
                                                            destination-filter source-filter
                                                            #:crop '(290 130 110 55))]
               [filter-paint (make-paint #:image-filter combined-filter)]
               [arithmetic (make-arithmetic-blender 0 0.25 0.75 0)]
               [arithmetic-source (make-paint #:color "#E94F37")])
     (paint-set-blender! source-with-blender paint-blender)
     (paint-set-blender! arithmetic-source arithmetic)
     (draw-simple-text canvas "color filter: source" 18 17 font label)
     (draw-simple-text canvas "bound child shader" 220 17 font label)
     (draw-rounded-rect canvas 18 28 82 45 7 7 orange)
     (draw-rounded-rect canvas 112 28 82 45 7 7 filtered-orange)
     (draw-rect canvas 220 28 180 45 child-paint)
     (draw-simple-text canvas "source" 34 84 font label)
     (draw-simple-text canvas "filtered" 126 84 font label)
     (draw-simple-text canvas "child = red-to-blue gradient" 220 84 font label)
     (draw-simple-text canvas "paint: D then S" 18 118 font label)
     (draw-simple-text canvas "shader: D, S" 155 118 font label)
     (draw-simple-text canvas "filter: bg=D, fg=S" 290 118 font label)
     (draw-rounded-rect canvas 18 130 110 55 8 8 destination)
     (draw-circle canvas 78 158 24 source-with-blender)
     (draw-rect canvas 155 130 110 55 shader-paint)
     (draw-rect canvas 290 130 110 55 filter-paint)
     (for ([x '(18 155 290)]) (draw-rect canvas x 130 110 55 outline))
     (draw-simple-text canvas "D = azure, S = orange" 18 206 font label)
     (draw-simple-text canvas "same runtime blender" 155 206 font label)
     (draw-simple-text canvas "arithmetic: .25 S + .75 D" 18 238 font label)
     (draw-rounded-rect canvas 225 220 110 28 6 6 destination)
     (draw-rounded-rect canvas 250 220 60 28 6 6 arithmetic-source)))
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
     (draw-rounded-rect canvas shape paint)))
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
 "matrix-composition-and-bounds.png" 420 260
 (lambda (canvas)
   (with-skia ([shape (make-path '((move 0 0) (line 35 0) (line 35 12)
                                   (line 12 12) (line 12 35) (line 0 35) (close)))]
               [ghost (make-paint #:color "#D9DEE6")]
               [ink (make-paint #:color "#326DE6")]
               [grid (make-paint #:color "#D9DEE6" #:style 'stroke #:stroke-width 1)]
               [box (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")])
     (define translation (matrix-translate 28 12))
     (define scaling (matrix-scale 1.4))
     (define (composition-panel x transform title)
       (draw-simple-text canvas title x 17 font label)
       (with-canvas-state canvas
         (canvas-translate! canvas x 35)
         (for ([n '(0 20 40 60 80)])
           (draw-line canvas n 0 n 80 grid)
           (draw-line canvas 0 n 80 n grid))
         (draw-path canvas shape ghost)
         (canvas-concat! canvas transform)
         (draw-path canvas shape ink)))
     (composition-panel 18 (matrix-compose translation scaling) "T × S: S acts first")
     (composition-panel 215 (matrix-compose scaling translation) "S × T: T acts first")
     (draw-simple-text canvas "gray = same local L; blue = composed result" 18 130 font label)
     (define bound-transform
       (matrix-compose (matrix-translate 210 195) (matrix-rotate-degrees 28)))
     (define-values (left top width height)
       (vector->values (matrix-map-rect bound-transform -45 -22 90 44)))
     (draw-simple-text canvas "matrix-map-rect returns an axis-aligned box" 90 145 font label)
     (with-canvas-state canvas
       (canvas-concat! canvas bound-transform)
       (draw-rect canvas -45 -22 90 44 ink))
     (draw-rect canvas left top width height box)
     (draw-simple-text canvas "red = mapped bounds, not an oriented rectangle" 85 250 font label)))
 #:background 'white)

(render-reference-image
 "matrix4-projected-grid.png" 300 190
 (lambda (canvas)
   (with-skia ([grid (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1)]
               [axis (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 3)]
               [marker (make-paint #:color "#7D5BA6")]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")])
     (define tilt
       (matrix4-compose (matrix4-translate 150 105 0)
                        (matrix4-perspective 420)
                        (matrix4-rotate-y-degrees 38)
                        (matrix4-rotate-x-degrees -14)
                        (matrix4-translate -70 -45 40)))
     (draw-simple-text canvas "matrix4-projected asymmetric grid" 68 17 font label)
     (with-canvas-matrix canvas tilt
       (for ([x (in-range 0 141 20)]) (draw-line canvas x 0 x 90 grid))
       (for ([y (in-range 0 91 15)]) (draw-line canvas 0 y 140 y grid))
       (draw-line canvas 0 0 140 90 axis)
       (draw-circle canvas 18 18 6 marker))
     (draw-simple-text canvas "purple corner marker prevents mirror ambiguity" 35 175 font label)))
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

(render-reference-image
 "canvas-matrix-scope.png" 160 150
 (lambda (canvas)
   (with-skia ([source (make-surface 20 20)]
               [inside (make-paint #:color 'red)]
               [restored (make-paint #:color 'blue)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")]
               [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (define source-canvas (surface-canvas source))
     (with-canvas-matrix source-canvas (matrix4-translate 5 6)
       (draw-rect source-canvas 0 0 4 3 inside))
     (draw-rect source-canvas 0 0 4 3 restored)
     (unless (equal? (canvas-matrix4 source-canvas) matrix4-identity)
       (error 'canvas-matrix-scope "canvas matrix was not restored"))
     (with-skia ([image (surface-snapshot source)])
       (draw-simple-text canvas "actual 20 x 20 target" 20 18 font label)
       (draw-image-rect canvas image 20 28 120 120 #:sampling 'nearest)
       (draw-rect canvas 20 28 120 120 boundary))))
 #:background 'white)


;;;
;;; Drawing Primitives, Structured Images, Text, and Recordings
;;;

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
 "mesh-triangle.png" 144 144
 (lambda (canvas)
   (with-skia ([source (make-surface 24 24 #:background 'white)]
               [paint (make-paint #:color 'white #:antialias? #f)]
               [mesh (make-vertices 'triangles
                                    '((2 2) (22 2) (2 22))
                                    #:colors '(red green blue))])
     (draw-vertices (surface-canvas source) mesh paint)
     (with-skia ([image (surface-snapshot source)])
       (draw-image-rect canvas image 0 0 144 144 #:sampling 'nearest))))
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


; make-nine-patch-source : -> image?
;   Returns an owned yellow image with blue top and bottom bands that reveal fixed versus stretched
;   regions.
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


; make-atlas-source : -> image?
;   Returns an owned red/blue two-cell atlas for source-rectangle and transform examples.
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
 "portable-atlas.png" 240 120
 (lambda (canvas)
   (with-skia ([source (make-surface 2 2 #:background 'red)]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")])
     ;; This is presentation-only: the documented 12 by 6 target stays
     ;; transparent outside its two drawn atlas copies.
     (for* ([row (in-range 6)] [column (in-range 12)])
       (draw-rect canvas (+ 24 (* column 16)) (+ 12 (* row 16)) 16 16
                  (if (even? (+ row column)) light dark)))
     (with-skia ([image (surface-snapshot source)]
                 [target (make-surface 12 6)])
     (draw-atlas/portable
      (surface-canvas target) image
      (list (make-atlas-transform 1 1) (make-atlas-transform 7 1 #:scale 2))
     '((0 0 2 2) (0 0 2 2)))
     (with-skia ([preview (surface-snapshot target)])
       (draw-image-rect canvas preview 24 12 192 96 #:sampling 'nearest)))))
 #:background 'white)

(render-reference-image
 "image-filter-placement.png" 240 200
 (lambda (canvas)
   (with-skia ([source-surface (make-surface 6 4 #:background 'red)]
               [image (surface-snapshot source-surface)]
               [filter (make-offset-image-filter 2 1)])
     (define-values (result source offset)
       (image-apply-filter image filter #:clip '(0 0 12 10)))
     (call-with-skia-resource result
       (lambda (result)
         (with-skia ([part (apply image-subset result (vector->list source))]
                     [destination (make-surface 12 10)]
                     [dark (make-paint #:color "#D9DEE4")]
                     [light (make-paint #:color "#F1F3F5")])
           (draw-image (surface-canvas destination) part
                       (vector-ref offset 0)
                       (vector-ref offset 1))
           ;; The checkerboard is presentation-only; destination remains
           ;; transparent outside the returned filtered subset.
           (for* ([row (in-range 10)] [column (in-range 12)])
             (draw-rect canvas (+ 24 (* column 16)) (+ 20 (* row 16)) 16 16
                        (if (even? (+ row column)) light dark)))
           (with-skia ([preview (surface-snapshot destination)])
             (draw-image-rect canvas preview 24 20 192 160 #:sampling 'nearest)))))))
 #:background 'white)

(render-reference-image
 "image-pixmap-copy-scaling.png" 420 240
 (lambda (canvas)
   (with-skia ([source (rgba-bytes->image
                        4 3
                        (bytes 255 0 0 255   0 255 0 128   0 0 255 255   255 220 0 64
                               0 220 220 255  150 60 200 128  239 79 55 255  80 80 80 0
                               50 109 230 255  125 91 166 128  34 139 34 255  255 255 255 255))]
               [read-buffer (make-raster-buffer 2 2)]
               [nearest-buffer (make-raster-buffer 8 6)]
               [linear-buffer (make-raster-buffer 8 6)]
               [source-buffer (image->raster-buffer source)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (call-with-raster-buffer-pixmap
      read-buffer
       (lambda (destination) (image-read-pixmap! source destination #:source-x 1 #:source-y 1))
      #:writable? #t)
     (call-with-raster-buffer-pixmap
      nearest-buffer
       (lambda (destination) (image-scale-pixmap! source destination #:sampling 'nearest))
      #:writable? #t)
     (call-with-raster-buffer-pixmap
      source-buffer
      (lambda (source-view)
        (call-with-raster-buffer-pixmap
         linear-buffer
          (lambda (destination) (pixmap-scale! destination source-view #:sampling 'linear))
         #:writable? #t)))
     (with-skia ([read-image (raster-buffer->image read-buffer)]
                 [nearest-image (raster-buffer->image nearest-buffer)]
                 [linear-image (raster-buffer->image linear-buffer)])
       (draw-simple-text canvas "source image: 4 × 3" 20 17 font label)
       (draw-simple-text canvas "read 2 × 2 from (1, 1)" 200 17 font label)
       (draw-image-rect canvas source 20 30 120 90 #:sampling 'nearest)
       (draw-image-rect canvas read-image 200 30 90 90 #:sampling 'nearest)
       (draw-rect canvas 20 30 120 90 outline)
       (draw-rect canvas 200 30 90 90 outline)
       (draw-simple-text canvas "image-scale-pixmap!: nearest" 20 132 font label)
       (draw-simple-text canvas "pixmap-scale!: linear" 220 132 font label)
       (draw-image-rect canvas nearest-image 20 145 120 90 #:sampling 'nearest)
       (draw-image-rect canvas linear-image 220 145 120 90 #:sampling 'nearest)
       (draw-rect canvas 20 145 120 90 outline)
       (draw-rect canvas 220 145 120 90 outline))))
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
 "output-group.png" 220 220
 (lambda (canvas)
   (with-skia ([source (make-surface 20 20)]
               [ink (make-paint #:color 'red)]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas "actual 20 x 20 target" 30 22 font label)
     (draw-output-group (surface-canvas source) 4 5 8 6
       (lambda (group-canvas)
         (draw-rect group-canvas 0 0 8 6 ink))
       #:policy 'raster
       #:scale 2
       #:padding 1)
     ;; The surface is transparent outside the output group; this checkerboard
     ;; belongs only to the enlarged presentation.
     (for* ([row (in-range 20)] [column (in-range 20)])
       (draw-rect canvas (+ 30 (* column 8)) (+ 40 (* row 8)) 8 8
                  (if (even? (+ row column)) light dark)))
     (with-skia ([image (surface-snapshot source)])
       (draw-image-rect canvas image 30 40 160 160 #:sampling 'nearest))))
 #:background 'white)


;;;
;;; Floating Colors, Output Documents, Raster Storage, and Racket Bridges
;;;

(render-reference-image
 "float-gradient.png" 64 16
 (lambda (canvas)
   (with-skia ([shader
                (make-linear-gradient-color4f-shader
                 0 0 64 0
                 (list (make-color4f 1 0 0) (make-color4f 0 0 1))
                 #:color-space 'srgb
                 #:positions '(0 1))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

(render-reference-image
 "nway-canvas.png" 160 160
 (lambda (canvas)
   (with-skia ([a (make-surface 16 16)]
               [b (make-surface 16 16)]
               [ink (make-paint #:color 'blue #:antialias? #f)])
     (call-with-nway-canvas
      (list a b)
      (lambda (nway-canvas) (draw-rect nway-canvas 2 2 8 8 ink)))
     (with-skia ([image (surface-snapshot a)])
       (draw-image-rect canvas image 0 0 160 160 #:sampling 'nearest))))
 #:background 'white)

(render-reference-image
 "pdf-document.png" 120 80
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)])
     (draw-rect canvas 10 10 100 60 paint)))
 #:background 'white)

(render-reference-image
 "pdf-two-pages.png" 260 115
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color 'blue)]
               [page (make-paint #:color 'white)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")]
               [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     ;; These are content previews of the exact page callbacks, not PDF output
     ;; rendered back through a document consumer.
     (for ([x '(10 135)] [size '(20 40)] [name '("page 1" "page 2")])
       (draw-simple-text canvas name x 18 font label)
       (draw-rect canvas x 28 120 80 page)
       (draw-rect canvas (+ x 10) 38 size size paint)
       (draw-rect canvas x 28 120 80 boundary))))
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
   (define page
     (make-output-page 60 40
       (lambda (page-canvas)
         (with-skia ([paint (make-paint #:color 'blue)])
           (draw-circle page-canvas 10 10 8 paint)))
       #:unit 'mm #:margins 5 #:background 'white))
   ;; At 25.4 DPI, a millimeter page unit maps to one pixel.  The following
   ;; draw is only the proportional 2x screen presentation of that real page.
   (with-skia ([image (output-page->image page #:dpi 25.4)])
     (draw-image-rect canvas image 0 0 120 80)))
 #:background 'white)

(render-reference-image
 "raster-buffer-bgra-sample.png" 280 150
 (lambda (canvas)
   (with-skia ([buffer (make-raster-buffer-from-info
                        (make-image-info 2 1 #:color-type 'bgra-8888))]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")]
               [font (make-font #:size 11)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (call-with-raster-buffer-pixmap
      buffer (lambda (view) (pixmap-set-sample! view 0 0 #(20 40 60 255))) #:writable? #t)
     ;; The image is created only after the temporary writable pixmap closes.
     (with-skia ([image (raster-buffer->image buffer)])
       (for* ([row (in-range 3)] [column (in-range 12)])
         (draw-rect canvas (+ 20 (* column 20)) (+ 34 (* row 20)) 20 20
                    (if (even? (+ row column)) light dark)))
       (draw-image-rect canvas image 20 34 240 60 #:sampling 'nearest)
       (draw-rect canvas 20 34 240 60 outline)
       (draw-simple-text canvas "written: (20,40,60,255)" 20 116 font label)
       (draw-simple-text canvas "initial: transparent" 156 134 font label))))
 #:background 'white)

(render-reference-image
 "raster-buffer-extracted-alpha.png" 300 140
 (lambda (canvas)
   (with-skia ([source (make-raster-buffer 4 1)]
               [font (make-font #:size 11)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (call-with-raster-buffer-pixmap
      source
      (lambda (view)
        (for ([x (in-range 4)] [alpha '(0 85 170 255)])
          (pixmap-set-sample! view x 0
                              (vector (quotient (* 50 alpha) 255)
                                      (quotient (* 109 alpha) 255)
                                      (quotient (* 230 alpha) 255)
                                      alpha))))
      #:writable? #t)
     (with-skia ([alpha-buffer (raster-buffer-extract-alpha source)]
                 [source-image (raster-buffer->image source)]
                 [alpha-image (raster-buffer->image alpha-buffer)])
       (draw-simple-text canvas "source blue with alpha 0, 85, 170, 255" 20 18 font label)
       (draw-image-rect canvas source-image 20 30 240 35 #:sampling 'nearest)
       (draw-simple-text canvas "extracted Alpha8 shown as black over white" 20 87 font label)
       (draw-image-rect canvas alpha-image 20 99 240 35 #:sampling 'nearest)
       (draw-rect canvas 20 30 240 35 outline)
       (draw-rect canvas 20 99 240 35 outline))))
 #:background 'white)

(render-reference-image
 "pixmap-subset-write.png" 190 150
 (lambda (canvas)
   (with-skia ([buffer (make-raster-buffer 3 2)]
               [dark (make-paint #:color "#D9DEE4")]
               [light (make-paint #:color "#F1F3F5")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")])
     (call-with-raster-buffer-pixmap
      buffer
      (lambda (view)
        (define corner (pixmap-subset view 2 1 1 1))
        (pixmap-fill! corner 'red))
      #:writable? #t)
     (with-skia ([image (raster-buffer->image buffer)])
       (draw-simple-text canvas "actual 3 x 2 buffer after borrow" 20 20 font label)
       (for* ([row (in-range 4)] [column (in-range 6)])
         (draw-rect canvas (+ 20 (* column 25)) (+ 35 (* row 25)) 25 25
                    (if (even? (+ row column)) light dark)))
       (draw-image-rect canvas image 20 35 150 100 #:sampling 'nearest)
       (draw-rect canvas 20 35 150 100 outline))))
 #:background 'white)

(render-reference-image
 "codec-image.png" 200 130
 (lambda (canvas)
   (with-skia ([surface (make-surface 3 2 #:background 'blue)])
     (define encoded (surface->png-bytes surface))
     (with-skia ([codec (codec-from-bytes encoded)]
                 [image (codec->image codec)]
                 [font (make-font #:size 16)]
                 [label (make-paint #:color "#20344E")]
                 [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
       (draw-simple-text canvas "decoded: 3 x 2 pixels" 20 20 font label)
       (draw-image-rect canvas image 34 30 132 88 #:sampling 'nearest)
       (draw-rect canvas 34 30 132 88 outline))))
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

(render-reference-image
 "bitmap-mask-and-copies.png" 420 180
 (lambda (canvas)
   (define source (draw:make-bitmap 3 2 #t))
   (send source set-argb-pixels 0 0 3 2
         (bytes 255 230 75 50   255 35 155 85   255 45 105 230
                255 240 185 45  255 150 70 190   255 35 180 185)
         #f #t)
   (define coverage (draw:make-bitmap 3 2 #t))
   (send coverage set-argb-pixels 0 0 3 2
         (bytes 102 0 0 0  178 0 0 0  255 0 0 0
                102 0 0 0  178 0 0 0  255 0 0 0)
         #f #t)
   (send source set-loaded-mask coverage)
   (with-skia ([masked (bitmap->image source)]
               [unmasked (bitmap->image source #:mask #f)]
               [surface (make-surface 3 2)]
               [light (make-paint #:color "#F1F3F5")]
               [dark (make-paint #:color "#D5D9DE")]
               [border (make-paint #:color "#9CA8B5" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 10)]
               [label-paint (make-paint #:color "#526070")])
     (draw-image (surface-canvas surface) unmasked 0 0)
     (define returned-bitmap (image->bitmap unmasked))
     (define surface-bitmap (surface->bitmap surface))
     (define (checker x y)
       (for* ([row (in-range 6)] [column (in-range 9)])
         (draw-rect canvas (+ x (* column 12)) (+ y (* row 12)) 12 12
                    (if (even? (+ row column)) light dark))))
     (with-skia ([returned (bitmap->image returned-bitmap #:mask #f)]
                 [surface-copy (bitmap->image surface-bitmap #:mask #f)])
       (for ([image (in-list (list masked returned surface-copy))]
             [x '(17 156 295)])
         (checker x 43)
         (draw-image-rect canvas image x 43 108 72 #:sampling 'nearest)
         (draw-rect canvas x 43 108 72 border))
       (for ([line-1 '("loaded mask" "mask #f, then" "surface->bitmap")]
             [line-2 '("bitmap->image" "image->bitmap" "snapshot")]
             [x '(17 156 295)])
         (draw-simple-text canvas line-1 x 16 label-font label-paint)
         (draw-simple-text canvas line-2 x 29 label-font label-paint))
       (draw-simple-text canvas "3 x 2 source; checkerboard is preview only" 17 148
                         label-font label-paint))))
 #:background 'white)

(render-reference-image
 "bitmap-resolution-density.png" 400 185
 (lambda (canvas)
   (define high-density (draw:make-bitmap 3 2 #t #:backing-scale 2))
   (define bitmap-dc (new draw:bitmap-dc% [bitmap high-density]))
   (send bitmap-dc set-pen "black" 1 'transparent)
   (send bitmap-dc set-brush "orange" 'solid)
   (send bitmap-dc draw-ellipse 1/4 1/4 5/2 3/2)
   (send bitmap-dc set-bitmap #f)
   (with-skia ([physical (bitmap->image high-density #:resolution 'physical #:mask #f)]
               [logical (bitmap->image high-density #:resolution 'logical #:mask #f)]
               [light (make-paint #:color "#F1F3F5")]
               [dark (make-paint #:color "#D5D9DE")]
               [border (make-paint #:color "#9CA8B5" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 11)]
               [label-paint (make-paint #:color "#526070")])
     (define (checker x y)
       (for* ([row (in-range 10)] [column (in-range 15)])
         (draw-rect canvas (+ x (* column 10)) (+ y (* row 10)) 10 10
                    (if (even? (+ row column)) light dark))))
     (for ([image (in-list (list physical logical))]
           [x '(25 225)])
       (checker x 45)
       (draw-image-rect canvas image x 45 150 100 #:sampling 'nearest)
       (draw-rect canvas x 45 150 100 border))
     (draw-simple-text canvas "physical: 6 x 4 samples" 25 22 label-font label-paint)
     (draw-simple-text canvas "logical: 3 x 2 samples" 225 22 label-font label-paint)
     (draw-simple-text canvas "same 3 x 2 logical bitmap; backing scale 2" 25 168
                       label-font label-paint)))
 #:background 'white)

(render-reference-image
 "picture-pict-viewport-density.png" 420 220
 (lambda (canvas)
   (define bounds (vector 36 22 100 70))
   (with-skia ([font (make-font #:size 14)]
               [background (make-paint #:color "#EEF2F7")]
               [ink (make-paint #:color "#20344E")]
               [orange (make-paint #:color "#EFA02B")]
               [grid (make-paint #:color "#C9D2DF" #:style 'stroke #:stroke-width 1)]
               [picture
                (call-with-picture
                 160 110
                 (lambda (picture-canvas)
                   (draw-rect picture-canvas 0 0 160 110 background)
                   (for ([x '(20 40 60 80 100 120 140)])
                     (draw-line picture-canvas x 0 x 110 grid))
                   (for ([y '(20 40 60 80 100)])
                     (draw-line picture-canvas 0 y 160 y grid))
                   (draw-circle picture-canvas 42 29 18 orange)
                   (draw-line picture-canvas 36 92 130 30 ink)
                   (draw-simple-text picture-canvas "viewport" 62 88 font ink)))])
     (define one (picture->pict picture #:bounds bounds #:raster-scale 1))
     (define three (picture->pict picture #:bounds bounds #:raster-scale 3))
     (define one-preview (pict:pict->bitmap (pict:scale one 2)))
     (define three-preview (pict:pict->bitmap (pict:scale three 2)))
     (with-skia ([one-image (bitmap->image one-preview #:mask #f)]
                 [three-image (bitmap->image three-preview #:mask #f)]
                 [label-font (make-font #:size 11)]
                 [label-paint (make-paint #:color "#526070")]
                 [border (make-paint #:color "#9CA8B5" #:style 'stroke #:stroke-width 1)])
       (draw-simple-text canvas "picture->pict: raster scale 1" 10 22 label-font label-paint)
       (draw-simple-text canvas "picture->pict: raster scale 3" 220 22 label-font label-paint)
       (draw-image-rect canvas one-image 10 43 200 140 #:sampling 'nearest)
       (draw-image-rect canvas three-image 210 43 200 140 #:sampling 'nearest)
       (draw-rect canvas 10 43 200 140 border)
       (draw-rect canvas 210 43 200 140 border)
       (draw-simple-text canvas "same nonzero 100 x 70 viewport; previews are 2x" 10 205
                         label-font label-paint))))
 #:background 'white)

(render-reference-image
 "skia-dc-headless-snapshot.png" 220 150
 (lambda (canvas)
   (define white (make-object draw:color% 255 255 255))
   (define navy (make-object draw:color% 32 52 78))
   (define panel (make-object draw:color% 232 238 249))
   (define orange (make-object draw:color% 239 160 43))
   (define blue (make-object draw:color% 50 109 230))
   (define dc
     (new skia-dc% [width 180] [height 105]
                   [background white] [smoothing 'smoothed]))
   (define snapshot
     (dynamic-wind
      void
      (lambda ()
        (send dc clear)
        (send dc set-pen navy 2 'solid)
        (send dc set-brush panel 'solid)
        (send dc draw-rounded-rectangle 8 8 164 88 12)
        (send dc set-brush orange 'solid)
        (send dc draw-ellipse 25 35 48 38)
        (send dc set-pen blue 3 'solid)
        (send dc draw-line 92 75 154 30)
        (send dc set-text-foreground navy)
        (send dc draw-text "headless DC" 24 18)
        (send dc snapshot))
      (lambda () (send dc close))))
   (with-skia ([image snapshot]
               [label-font (make-font #:size 11)]
               [label-paint (make-paint #:color "#526070")]
               [border (make-paint #:color "#9CA8B5" #:style 'stroke #:stroke-width 1)])
     (draw-simple-text canvas "headless DC -> snapshot after close" 20 18
                       label-font label-paint)
     (draw-image-rect canvas image 20 32 180 105 #:sampling 'nearest)
     (draw-rect canvas 20 32 180 105 border)))
 #:background 'white)

(render-reference-image
 "dc-output-capture-and-page-preview.png" 420 170
 (lambda (canvas)
   (define white (make-object draw:color% 255 255 255))
   (define navy (make-object draw:color% 32 52 78))
   (define panel (make-object draw:color% 232 238 249))
   (define orange (make-object draw:color% 239 160 43))
   (define blue (make-object draw:color% 50 109 230))
   (define black (make-object draw:color% 0 0 0))
   (define (draw-scene dc)
     (send dc set-pen navy 2 'solid)
     (send dc set-brush panel 'solid)
     (send dc draw-rectangle 4 4 172 92)
     (send dc set-text-foreground navy)
     (send dc draw-text "vector frame" 12 14)
     (draw-dc-raster-group
      dc 100 30 52 45
      (lambda (group)
        (send group set-pen black 1 'transparent)
        (send group set-brush orange 'solid)
        (send group draw-ellipse 2 2 44 35)
        (send group set-pen blue 3 'solid)
        (send group draw-line 4 39 48 5))
      #:scale 2 #:label "orange-badge")
     (send dc set-pen blue 3 'solid)
     (send dc draw-line 15 80 80 42))
   (define page (make-dc-output-page 180 100 draw-scene #:background "#FFFFFF"))
   (with-skia ([surface (make-surface 180 100 #:background "#FFFFFF")]
               [label-font (make-font #:size 10)]
               [label-paint (make-paint #:color "#526070")]
               [border (make-paint #:color "#9CA8B5" #:style 'stroke #:stroke-width 1)])
     (define report (call-with-output-dc (surface-canvas surface) 180 100 draw-scene))
     (with-skia ([direct (surface-snapshot surface)]
                 [preview (output-page->image page #:dpi 72)])
       (draw-simple-text canvas "call-with-output-dc CPU capture" 15 17
                         label-font label-paint)
       (draw-simple-text canvas "make-dc-output-page content preview" 225 17
                         label-font label-paint)
       (draw-image-rect canvas direct 15 30 180 100 #:sampling 'nearest)
       (draw-image-rect canvas preview 225 30 180 100 #:sampling 'nearest)
       (draw-rect canvas 15 30 180 100 border)
       (draw-rect canvas 225 30 180 100 border)
       (draw-simple-text canvas
                         (format "report: ~a explicit raster group; preview is not document proof"
                                 (hash-ref report 'raster_groups))
                         15 151 label-font label-paint))))
 #:background 'white)

;;;
;;; Extended Effects, Font Geometry, Pictures, and Decoder Placement
;;;

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
 "path-effect-2d-lattices.png" 300 150
 (lambda (canvas)
   (with-skia ([stamp (make-path '((move -5 -4) (line 6 0) (line -5 4) (close)))]
               [line-effect (make-2d-line-path-effect 3 (matrix-scale 14 14))]
               [stamp-effect (make-2d-path-effect (matrix-scale 18 18) stamp)]
               [line-paint (make-paint #:color "#326DE6" #:style 'stroke
                                       #:stroke-width 2 #:path-effect line-effect)]
               [stamp-paint (make-paint #:color "#E94F37" #:style 'stroke
                                        #:stroke-width 2 #:path-effect stamp-effect)]
               [font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")]
               [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (draw-simple-text canvas "parallel-line lattice" 20 20 font label)
     (draw-simple-text canvas "asymmetric stamp lattice" 165 20 font label)
     (draw-rect canvas 20 35 115 95 line-paint)
     (draw-rect canvas 165 35 115 95 stamp-paint)
     (draw-rect canvas 20 35 115 95 boundary)
     (draw-rect canvas 165 35 115 95 boundary)))
 #:background 'white)

(render-native-scale-reference-image
 "mask-filter-coverage.png" 420 125
 (lambda (canvas)
   (with-skia ([table (make-table-mask-filter
                       (apply bytes (for/list ([coverage (in-range 256)])
                                      (if (< coverage 128) 0 255))))]
               [clipped (make-clip-mask-filter 80 180)]
               [alpha-ramp (make-linear-gradient-shader
                            325 0 390 0 (list (rgba 255 255 255 0) 'white))]
               [shader-mask (make-shader-mask-filter alpha-ramp)]
               [plain (make-paint #:color "#326DE6")]
               [table-paint (make-paint #:color "#326DE6" #:mask-filter table)]
               [clip-paint (make-paint #:color "#326DE6" #:mask-filter clipped)]
               [shader-paint (make-paint #:color "#326DE6" #:mask-filter shader-mask)]
               [font (make-font #:size 11)]
               [label (make-paint #:color "#20344E")])
     (for ([text '("original" "table threshold" "clip 80..180" "shader alpha")]
           [x '(20 114 216 326)])
       (draw-simple-text canvas text x 18 font label))
     (for ([paint (list plain table-paint clip-paint shader-paint)]
           [x '(55.5 155.5 255.5 355.5)])
       (draw-circle canvas x 72.5 27.25 paint))))
 #:background 'white)

(render-reference-image
 "color-filter-channel-curves.png" 420 180
 (lambda (canvas)
   (with-skia ([color-source (make-surface 120 50)]
               [gray-source (make-surface 120 50)]
               [spectrum (make-linear-gradient-shader 0 0 120 0 '(red yellow green cyan blue))]
               [gray (make-linear-gradient-shader 0 0 120 0 '(black white))]
               [spectrum-paint (make-paint #:shader spectrum)]
               [gray-paint (make-paint #:shader gray)])
     (draw-rect (surface-canvas color-source) 0 0 120 50 spectrum-paint)
     (draw-rect (surface-canvas gray-source) 0 0 120 50 gray-paint)
     (with-skia ([color-image (surface-snapshot color-source)]
                 [gray-image (surface-snapshot gray-source)]
                 [hsla (make-hsla-matrix-filter
                        '(1 0 0 0 0.18
                          0 0.55 0 0 0
                          0 0 1 0 0
                          0 0 0 1 0))]
                 [to-linear (make-srgb-to-linear-gamma-color-filter)]
                 [to-srgb (make-linear-to-srgb-gamma-color-filter)]
                 [blue-table (make-table-argb-color-filter
                              #:blue (apply bytes (for/list ([v (in-range 256)]) (- 255 v))))]
                 [plain (make-paint)]
                 [hsla-paint (make-paint #:color-filter hsla)]
                 [linear-paint (make-paint #:color-filter to-linear)]
                 [srgb-paint (make-paint #:color-filter to-srgb)]
                 [blue-paint (make-paint #:color-filter blue-table)]
                 [font (make-font #:size 11)]
                 [label (make-paint #:color "#20344E")])
       (for ([text '("source strip" "HSLA hue + desaturate" "blue table inverted")]
             [x '(15 150 285)])
         (draw-simple-text canvas text x 17 font label))
       (for ([paint (list plain hsla-paint blue-paint)] [x '(15 150 285)])
         (draw-image canvas color-image x 28 #:paint paint))
       (for ([text '("sRGB -> linear" "linear -> sRGB")] [x '(80 220)])
         (draw-simple-text canvas text x 103 font label))
       (draw-image canvas gray-image 80 114 #:paint linear-paint)
       (draw-image canvas gray-image 220 114 #:paint srgb-paint))))
 #:background 'white)

(render-reference-image
 "image-filter-displacement-magnifier.png" 420 225
 (lambda (canvas)
   (with-skia ([source-surface (make-surface 120 80 #:background 'white)]
               [grid (make-paint #:color "#B8C0CC" #:style 'stroke #:stroke-width 1)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#E94F37")]
               [purple (make-paint #:color "#7D5BA6")])
     (define source-canvas (surface-canvas source-surface))
     (for ([x '(20 40 60 80 100)]) (draw-line source-canvas x 0 x 80 grid))
     (for ([y '(20 40 60)]) (draw-line source-canvas 0 y 120 y grid))
     (draw-circle source-canvas 24 22 8 blue)
     (draw-polygon source-canvas '((86 12) (110 25) (86 38)) orange)
     (draw-rect source-canvas 14 54 32 14 purple)
     (define map-bytes (make-bytes (* 120 80 4)))
     (for* ([y (in-range 80)] [x (in-range 120)])
       (define index (* 4 (+ x (* y 120))))
       (bytes-set! map-bytes index (quotient (* 255 x) 119))
       (bytes-set! map-bytes (+ index 1) (quotient (* 255 y) 79))
       (bytes-set! map-bytes (+ index 2) 0)
       (bytes-set! map-bytes (+ index 3) 255))
     (with-skia ([source-image (surface-snapshot source-surface)]
                 [map-image (rgba-bytes->image 120 80 map-bytes)]
                 [map-source (make-image-source-filter map-image)]
                 [color-source (make-image-source-filter source-image)]
                 [displacement (make-displacement-map-image-filter
                                'red 'green 60 map-source color-source)]
                 [magnifier (make-magnifier-image-filter '(14 10 52 52) 2 #:inset 6)]
                 [displaced-paint (make-paint #:image-filter displacement)]
                 [magnified-paint (make-paint #:image-filter magnifier)]
                 [displaced-surface (make-surface 120 80 #:background 'white)]
                 [magnified-surface (make-surface 120 80 #:background 'white)]
                 [font (make-font #:size 10)]
                 [label (make-paint #:color "#20344E")]
                 [lens (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)])
       (draw-paint (surface-canvas displaced-surface) displaced-paint)
       (draw-image (surface-canvas magnified-surface) source-image 0 0)
       (draw-image (surface-canvas magnified-surface) source-image 0 0 #:paint magnified-paint)
       (with-skia ([displaced-image (surface-snapshot displaced-surface)]
                   [magnified-image (surface-snapshot magnified-surface)])
         (for ([text '("color source" "map: red=x, green=y" "displaced: red -> x, green -> y")]
               [x '(10 150 285)])
           (draw-simple-text canvas text x 16 font label))
         (draw-image canvas source-image 10 28)
         (draw-image canvas map-image 150 28)
         (draw-image canvas displaced-image 285 28)
         (draw-simple-text canvas "lens on source" 35 127 font label)
         (draw-simple-text canvas "2x magnifier; inset 6" 235 127 font label)
         (draw-image canvas source-image 35 138)
         (draw-rect canvas 49 148 52 52 lens)
         (draw-image canvas magnified-image 235 138)
         (draw-rect canvas 249 148 52 52 lens)))))
 #:background 'white)

(render-reference-image
 "image-filter-lighting-grid.png" 420 280
 (lambda (canvas)
   (with-skia ([height-surface (make-surface 120 70)]
               [height-shader (make-radial-gradient-shader
                               60 35 30 (list 'white (rgba 255 255 255 0)))]
               [height-paint (make-paint #:shader height-shader)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [black (make-paint #:color 'black)])
     (draw-rect (surface-canvas height-surface) 0 0 120 70 height-paint)
     (with-skia ([height-image (surface-snapshot height-surface)]
                 [distant-diffuse (make-distant-lit-diffuse-image-filter '(1 -1 2) 'white
                                                                          #:surface-scale 6
                                    #:coefficient 1.2)]
                 [point-diffuse (make-point-lit-diffuse-image-filter '(60 20 80) 'white
                                                                      #:surface-scale 6
                                  #:coefficient 1.2)]
                 [spot-diffuse (make-spot-lit-diffuse-image-filter '(60 20 80) '(60 35 0) 'white
                                                                    #:exponent 2 #:cutoff-angle 35
                                                                    #:surface-scale 6 #:coefficient
                                 1.2)]
                 [distant-specular (make-distant-lit-specular-image-filter '(1 -1 2) 'white
                                                                            #:surface-scale 6
                                     #:coefficient 1
                                                                            #:shininess 8)]
                 [point-specular (make-point-lit-specular-image-filter '(60 35 100) 'white
                                                                        #:surface-scale 6
                                   #:coefficient 1
                                                                        #:shininess 8)]
                 [spot-specular (make-spot-lit-specular-image-filter '(60 35 100) '(60 35 0) 'white
                                                                      #:exponent 2 #:cutoff-angle 35
                                                                      #:surface-scale 6
                                  #:coefficient 1
                                                                      #:shininess 8)])
       (for ([name '("diffuse distant" "diffuse point" "diffuse spot"
                    "specular distant" "specular point" "specular spot")]
             [x '(20 155 290 20 155 290)] [y '(20 20 20 125 125 125)])
         (draw-simple-text canvas name x y font label))
       (for ([filter (list distant-diffuse point-diffuse spot-diffuse
                           distant-specular point-specular spot-specular)]
             [x '(20 155 290 20 155 290)] [y '(32 32 32 137 137 137)])
         (with-skia ([paint (make-paint #:shader height-shader #:image-filter filter)]
                     [pane (make-surface 120 70 #:background 'black)])
           (draw-rect (surface-canvas pane) 0 0 120 70 paint)
           (with-skia ([image (surface-snapshot pane)])
             (draw-image canvas image x y))))
       (draw-simple-text canvas "source alpha height field" 20 235 font label)
       (draw-rect canvas 20 242 70 30 black)
       (draw-image-rect canvas height-image 20 242 70 30 #:sampling 'linear))))
 #:background 'white)

(render-reference-image
 "picture-image-filter-target-crop.png" 420 175
 (lambda (canvas)
   (with-skia ([picture
                (call-with-picture
                 120 75
                 (lambda (pc)
                   (with-skia ([blue (make-paint #:color "#326DE6")]
                               [orange (make-paint #:color "#E94F37")]
                               [purple (make-paint #:color "#7D5BA6")])
                     (draw-rounded-rect pc 5 5 80 55 9 9 blue)
                     (draw-polygon pc '((20 58) (104 58) (86 17)) orange)
                     (draw-circle pc 98 18 13 purple))))]
               [target-filter (make-picture-image-filter picture #:target '(30 15 55 40))]
               [crop-filter (make-picture-image-filter picture
                                                       #:target '(15 8 85 58)
                                                       #:crop '(55 8 38 58))]
               [target-paint (make-paint #:image-filter target-filter)]
               [crop-paint (make-paint #:image-filter crop-filter)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [bound (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [target-bound (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
               [crop-bound (make-paint #:color "#7D5BA6" #:style 'stroke #:stroke-width 2)])
     ;; Preview it once, then prove that the two filters retain the recording.
     (draw-picture canvas picture #:x 12 #:y 30)
     (skia-close! picture)
     (define (render-filter paint)
       (with-skia ([page (make-surface 120 75 #:background 'white)])
         (draw-paint (surface-canvas page) paint)
         (surface-snapshot page)))
     (with-skia ([target-image (render-filter target-paint)]
                 [crop-image (render-filter crop-paint)])
       (draw-simple-text canvas "recorded picture: native cull" 12 17 font label)
       (draw-simple-text canvas "target: select, don't scale" 150 17 font label)
       (draw-simple-text canvas "target intersect crop" 290 17 font label)
       (draw-image canvas target-image 150 30)
       (draw-image canvas crop-image 290 30)
       (for ([x '(12 150 290)]) (draw-rect canvas x 30 120 75 bound))
       (draw-rect canvas 42 45 55 40 target-bound)
       (draw-rect canvas 180 45 55 40 target-bound)
       (draw-rect canvas 305 38 85 58 target-bound)
       (draw-rect canvas 345 38 38 58 crop-bound)
       (draw-simple-text canvas "orange=target; purple=crop" 12 125 font label)
       (draw-simple-text canvas "recording stays 1:1" 150 125 font label)
       (draw-simple-text canvas "only overlap is output" 290 125 font label))))
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
 "font-metrics-guides.png" 420 205
 (lambda (canvas)
   (with-skia ([font (make-font #:size 58)]
               [text-paint (make-paint #:color "#20344E")]
               [ascent-paint (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 1)]
               [baseline-paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1)]
               [descent-paint (make-paint #:color "#2C9B6F" #:style 'stroke #:stroke-width 1)]
               [advance-paint (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1.5)]
               [ascent-label (make-paint #:color "#D64F45")]
               [baseline-label (make-paint #:color "#326DE6")]
               [descent-label (make-paint #:color "#2C9B6F")]
               [advance-label (make-paint #:color "#8255C7")]
               [label-font (make-font #:size 12)]
               [label-paint (make-paint #:color "#526070")])
     (define text "glyph")
     (define x 35)
     (define baseline 120)
     (define metrics (font-get-metrics font))
     (define ascent (+ baseline (font-metrics-ascent metrics)))
     (define descent (+ baseline (font-metrics-descent metrics)))
     (define advance (measure-simple-text font text))
     (draw-line canvas 22 ascent 235 ascent ascent-paint)
     (draw-line canvas 22 baseline 235 baseline baseline-paint)
     (draw-line canvas 22 descent 235 descent descent-paint)
     (draw-simple-text canvas text x baseline font text-paint)
     (draw-line canvas x 160 (+ x advance) 160 advance-paint)
     (draw-line canvas x 156 (+ x 5) 161 advance-paint)
     (draw-line canvas x 164 (+ x 5) 159 advance-paint)
     (draw-line canvas (+ x advance) 156 (+ x advance -5) 161 advance-paint)
     (draw-line canvas (+ x advance) 164 (+ x advance -5) 159 advance-paint)
     (draw-simple-text canvas "ascent" 250 (+ ascent 4) label-font ascent-label)
     (draw-simple-text canvas "baseline" 250 (+ baseline 4) label-font baseline-label)
     (draw-simple-text canvas "descent" 250 (+ descent 4) label-font descent-label)
     (draw-simple-text canvas (format "advance ~a" (inexact->exact (round advance)))
                       35 183 label-font advance-label)))
 #:background 'white)

(render-reference-image
 "simple-text-path-outlines.png" 360 190
 (lambda (canvas)
   (with-skia ([font (make-font #:size 52)]
               [fill-paint (make-paint #:color "#326DE6")]
               [stroke-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
               [label-font (make-font #:size 12)]
               [label-paint (make-paint #:color "#526070")])
     (with-skia ([filled (simple-text-path font "path" 20 78)]
                 [stroked (simple-text-path font "path" 20 170)])
       (draw-simple-text canvas "filled monochrome outline" 20 20 label-font label-paint)
       (draw-path canvas filled fill-paint)
       (draw-simple-text canvas "stroked monochrome outline" 20 110 label-font label-paint)
       (draw-path canvas stroked stroke-paint))))
 #:background 'white)


; face-label : typeface? -> string?
;   Truncates a font family label to fit compact comparison panels.
(define (face-label face)
  (define family (typeface-family-name face))
  (if (> (string-length family) 16)
      (string-append (substring family 0 13) "...")
      family))

(render-reference-image
 "font-manager-style-selection.png" 420 180
 (lambda (canvas)
   (with-skia ([manager (make-font-manager)]
               [title-font (make-font #:size 12)]
               [label-font (make-font #:size 10)]
               [title-paint (make-paint #:color "#526070")]
               [label-paint (make-paint #:color "#526070")]
               [panel-paint (make-paint #:color "#EEF2F7")]
               [border-paint (make-paint #:color "#C9D2DF" #:style 'stroke #:stroke-width 1)])
     (define initial
       (or (font-manager-match-character manager #\g)
           (error 'font-manager-style-selection "no face covers the displayed character")))
     (define family (typeface-family-name initial))
     (define bold-face
       (or (font-manager-match-family manager family #:weight 'bold)
           (error 'font-manager-style-selection "no bold face was selected")))
     (define italic-face
       (or (font-manager-match-family manager family #:slant 'italic)
           (error 'font-manager-style-selection "no italic face was selected")))
     (with-skia ([regular-face initial]
                 [bold-face* bold-face]
                 [italic-face* italic-face])
       (for ([face (in-list (list regular-face bold-face* italic-face*))]
             [request '("regular request" "bold request" "italic request")]
             [x '(12 148 284)])
         (with-skia ([font (make-font face #:size 37)]
                     [text-paint (make-paint #:color "#20344E")])
           (draw-rect canvas x 26 124 140 panel-paint)
           (draw-rect canvas x 26 124 140 border-paint)
           (draw-simple-text canvas request (+ x 8) 45 title-font title-paint)
           (draw-simple-text canvas "Style" (+ x 8) 90 font text-paint)
           (draw-simple-text canvas (format "actual: ~a" (face-label face))
                             (+ x 8) 125 label-font label-paint)
           (draw-simple-text canvas
                             (format "w~a; ~a"
                                     (typeface-weight face) (typeface-slant face))
                             (+ x 8) 144 label-font label-paint))))))
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
 "text-blob-path-snapshot.png" 330 100
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [shaper (make-shaper font)]
               [path (make-path '((move 10 40) (line 310 40)))]
               [guide-path (make-path '((move 10 40) (line 310 40)))]
               [guide (make-paint #:color "#BBBBBB" #:style 'stroke #:stroke-width 1)]
               [mark (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
               [paint (make-paint #:color "#20344E")]
               [label-font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")])
     (define text "AB")
     (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
     (with-skia ([blob (shaped-run->text-blob/on-path shaper run path
                                                    #:start-offset 20 #:normal-offset 5
                                                    #:text text)])
       (skia-close! path)
       (skia-close! shaper)
       (draw-path canvas guide-path guide)
       (draw-text-blob canvas blob 0 0 paint)
       (draw-line canvas 30 40 30 45 mark)
       (draw-simple-text canvas "start +20; normal +5" 10 88 label-font label))))
 #:background 'white)

(render-reference-image
 "text-blob-multirun-outline.png" 420 175
 (lambda (canvas)
   (with-skia ([font (make-font #:size 30)]
               [builder (make-text-blob-builder)]
               [source-paint (make-paint #:color "#326DE6")]
               [outline-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
               [divider-paint (make-paint #:color "#C9D2DF" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 12)]
               [label-paint (make-paint #:color "#526070")])
     (text-blob-builder-add-run! builder font (font-text->glyphs font "small")
                                #:origin '(18 92))
     (font-set-size! font 52)
     (text-blob-builder-add-run! builder font (font-text->glyphs font "!")
                                #:origin '(130 92))
     (with-skia ([blob (text-blob-builder-finish! builder)]
                 [outline (text-blob->path blob)])
       (draw-line canvas 210 12 210 160 divider-paint)
       (draw-simple-text canvas "completed blob: two retained runs" 18 24
                         label-font label-paint)
       (draw-text-blob canvas blob 0 0 source-paint)
       (draw-simple-text canvas "text-blob->path" 228 24 label-font label-paint)
       (with-canvas-state canvas
         (canvas-translate! canvas 210 0)
         (draw-path canvas outline outline-paint)))))
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
 "scanline-bottom-up-placement.png" 190 190
 (lambda (canvas)
   (with-skia ([session (codec-scanline-from-bytes (make-reference-bottom-up-bmp))]
               [target (make-surface 2 3)]
               [font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")]
               [rule (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
     (define lower-batch (codec-scanline-read! session 2))
     (define upper-batch (codec-scanline-read! session 1))
     (for ([batch (list lower-batch upper-batch)])
       (with-skia ([buffer (scanline-batch->raster-buffer batch)]
                   [part (raster-buffer->image buffer)])
         (draw-image (surface-canvas target) part 0
                     (scanline-batch-first-row batch))))
     (with-skia ([image (surface-snapshot target)])
       (draw-simple-text canvas "first read -> rows 1,2" 20 17 font label)
       (draw-simple-text canvas "second read -> row 0" 20 34 font label)
       (draw-image-rect canvas image 20 50 80 120 #:sampling 'nearest)
       (draw-rect canvas 20 50 80 120 rule)
       (draw-line canvas 20 90 100 90 rule)
       (draw-line canvas 20 130 100 130 rule)
       (for ([row '(0 1 2)] [y '(75 115 155)])
         (draw-simple-text canvas (format "output row ~a" row) 112 y font label)))))
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

;;;
;;; Reusable Comparison Fixtures
;;;


; draw-reference-checkerboard : canvas? real? real? real? real? [real?] -> void?
;   Draws a clipped light/dark grid that makes transparency visible behind examples.
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


; make-reference-quadrant-image : -> image?
;   Returns an owned four-color image whose quadrant placement reveals sampling and coordinate
;   behavior.
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


; make-reference-motif-image : -> image?
;   Returns an owned yellow image with distinct circle and rectangle motifs for cropping and
;   placement examples.
(define (make-reference-motif-image)
  (with-skia ([surface (make-surface 40 30 #:background "#F4D35E")]
              [blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (define canvas (surface-canvas surface))
    (draw-circle canvas 12 15 9 blue)
    (draw-rect canvas 24 6 12 18 orange)
    (surface-snapshot surface)))


; make-reference-overlap-path : symbol? -> path?
;   Returns an owned Boolean path result from two overlapping circles.
(define (make-reference-overlap-path operation)
  (with-skia ([left (make-path)] [right (make-path)])
    (path-add-circle! left 65 50 34)
    (path-add-circle! right 105 50 34)
    (path-op left right operation)))


; make-reference-region-result : symbol? -> region?
;   Returns an owned region-operation result from two overlapping integer rectangles.
(define (make-reference-region-result operation)
  (with-skia ([a (make-region '((20 15 90 55)))]
              [b (make-region '((70 30 80 50)))])
    (region-op a b operation)))

;;;
;;; Paint Styles and Blending
;;;

(render-reference-image
 "paint-fill-path.png" 220 120
 (lambda (canvas)
   (with-skia ([path (make-path '((move 10 20) (line 90 20)))]
               [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 6 #:cap 'round)]
               [fill (make-paint #:color "#326DE6")]
               [boundary (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define-values (outline fillable?) (paint->fill-path paint path))
     (call-with-skia-resource
      outline
      (lambda (outline)
        (unless fillable? (error 'paint-fill-path "round stroke should have a fillable expansion"))
        (draw-simple-text canvas "original stroke" 10 18 font label)
        (with-canvas-state canvas
          (canvas-translate! canvas 10 15)
          (draw-path canvas path paint))
        (draw-simple-text canvas "returned fill path" 10 68 font label)
        (with-canvas-state canvas
          (canvas-translate! canvas 10 65)
          (draw-path canvas outline fill)
          (draw-path canvas outline boundary))))))
 #:background 'white)

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
 "paint-miter-and-translucent-blends.png" 420 250
 (lambda (canvas)
   (with-skia ([high-miter (make-paint #:color "#326DE6" #:style 'stroke
                                       #:stroke-width 16 #:join 'miter)]
               [low-miter (make-paint #:color "#326DE6" #:style 'stroke
                                      #:stroke-width 16 #:join 'miter)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")]
               [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
               [checker-light (make-paint #:color "#F5F6F8")]
               [checker-dark (make-paint #:color "#D9DEE6")])
     (paint-set-miter-limit! high-miter 8)
     (paint-set-miter-limit! low-miter 1.2)
     (for ([paint (list high-miter low-miter)] [x '(20 230)]
           [caption '("miter limit 8" "miter limit 1.2 -> bevel")])
       (draw-simple-text canvas caption x 17 font label)
       (draw-polygon canvas (list (list (+ x 55) 115) (list (+ x 85) 42)
                                  (list (+ x 115) 115)) paint #:closed? #f))
     (draw-simple-text canvas "declared D: 55% azure; incoming S: 65% orange" 18 137 font label)
     (define (draw-checker x)
       (for* ([row (in-range 3)] [column (in-range 6)])
         (draw-rect canvas (+ x (* 20 column)) (+ 150 (* 20 row)) 20 20
                    (if (even? (+ row column)) checker-light checker-dark))))
     (define (blend-pane mode)
       (with-skia ([pane (make-surface 110 58)]
                   [destination (make-paint #:color (rgba 23 105 224 140))]
                   [source (make-paint #:color (rgba 239 79 55 166) #:blend-mode mode)])
         (draw-rounded-rect (surface-canvas pane) 6 6 82 44 8 8 destination)
         (draw-circle (surface-canvas pane) 72 29 22 source)
         (surface-snapshot pane)))
     (for ([mode '(src-over modulate multiply)] [x '(18 155 292)])
       (draw-simple-text canvas (symbol->string mode) x 225 font label)
       (draw-checker x)
       (with-skia ([result (blend-pane mode)])
         (draw-image canvas result x 150))
       (draw-rect canvas x 150 110 58 outline))))
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

;;;
;;; Canvas Transforms and Clipping
;;;

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

;;;
;;; Shader Transforms, Noise, Filtering, and Tiling
;;;

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

;;;
;;; Color-Filter Composition
;;;

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

;;;
;;; Image-Filter Graphs
;;;

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

;;;
;;; Path Geometry, Measurement, and Set Operations
;;;

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
 "path-bounds-and-measure-matrix.png" 420 235
 (lambda (canvas)
   (with-skia ([quadratic (make-path '((move 20 140) (quad 70 30 120 140)))]
               [control-polygon (make-path '((move 20 140) (line 70 30) (line 120 140)))]
               [contours (make-path '((move 235 135) (cubic 260 75 330 175 370 105)
                                     (move 235 190) (line 370 190)))]
               [measure (make-path-measure contours)]
               [arrow (make-path '((move -12 -6) (line 10 0) (line -2 5)
                                   (line -2 2) (line -12 2) (close)))]
               [dash (make-dash-path-effect '(4 3))]
               [curve (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 4)]
               [control (make-paint #:color "#9BA6B5" #:style 'stroke #:stroke-width 2
                                    #:path-effect dash)]
               [stored-bound (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
               [tight-bound (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
               [guide (make-paint #:color "#9BA6B5" #:style 'stroke #:stroke-width 3)]
               [first-arrow (make-paint #:color "#326DE6")]
               [second-arrow (make-paint #:color "#7D5BA6")]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")])
     (define-values (left top width height) (vector->values (path-bounds quadratic)))
     (define-values (tight-left tight-top tight-width tight-height) (vector->values (path-tight-bounds quadratic)))
     (draw-simple-text canvas "quadratic: control points vs. curve" 18 17 font label)
     (draw-path canvas control-polygon control)
     (draw-path canvas quadratic curve)
     (draw-rect canvas left top width height stored-bound)
     (draw-rect canvas tight-left tight-top tight-width tight-height tight-bound)
     (draw-simple-text canvas "red = stored-point bounds" 18 165 font label)
     (draw-simple-text canvas "orange = tight curve bounds" 18 181 font label)
     (draw-simple-text canvas "path-measure-matrix on two contours" 230 17 font label)
     (draw-path canvas contours guide)
     (define first-placement (path-measure-matrix measure (* 0.55 (path-measure-length measure))))
     (with-canvas-state canvas
       (canvas-concat! canvas first-placement)
       (draw-path canvas arrow first-arrow))
     (path-measure-next-contour! measure)
     (define second-placement (path-measure-matrix measure (* 0.55 (path-measure-length measure))))
     (with-canvas-state canvas
       (canvas-concat! canvas second-placement)
       (draw-path canvas arrow second-arrow))
     (draw-simple-text canvas "blue: first contour" 235 210 font label)
     (draw-simple-text canvas "purple: after next-contour!" 235 225 font label)))
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

;;;
;;; Rounded Rectangles and Integer-Region Set Operations
;;;

(render-reference-image
 "rounded-rect-normalized.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")]
               [outline (make-paint #:color "#AAB1B9" #:style 'stroke #:stroke-width 1)])
     (define shape (make-rounded-rect 25 20 130 60 #:radii 80))
     (define normalized (rounded-rect-normalize shape))
     (draw-rect canvas 25 20 130 60 outline)
     (draw-rounded-rect canvas normalized paint)))
 #:background 'white)

(render-reference-image
 "rounded-rect-nine-patch.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (define shape (make-nine-patch-rounded-rect 20 15 140 70 30 10 16 28))
     (draw-rounded-rect canvas shape paint)))
 #:background 'white)

(render-reference-image
 "rounded-rect-inset-outset.png" 260 165
 (lambda (canvas)
   (with-skia ([outset-paint (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 3)]
               [original-paint (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 3)]
               [inset-paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 3)]
               [font (make-font #:size 11)]
               [label (make-paint #:color "#20344E")])
     (define original (make-rounded-rect 65 52 130 65 #:radii 28))
     (define inset (rounded-rect-inset original 12 8))
     (define outset (rounded-rect-outset original 12 8))
     (draw-rounded-rect canvas outset outset-paint)
     (draw-rounded-rect canvas original original-paint)
     (draw-rounded-rect canvas inset inset-paint)
     (draw-simple-text canvas "orange: outset (12, 8)" 54 22 font label)
     (draw-simple-text canvas "dark: original" 88 137 font label)
     (draw-simple-text canvas "blue: inset (12, 8)" 72 153 font label)))
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

(render-reference-image
 "region-quantization-and-difference.png" 420 170
 (lambda (canvas)
   (with-skia ([source (make-path '((move 2 12) (quad 2 1 10 1)
                                   (quad 18 1 18 8) (quad 18 13 10 13)
                                   (quad 3 13 2 12) (close)))]
               [clip (make-region '((0 0 20 14)))]
               [region (path->region source clip)]
               [boundary (region->path region)]
               [cutter (make-region '((9 0 5 14)))]
               [difference (region-difference region cutter)]
               [fill (make-paint #:color "#326DE6" #:antialias? #f)]
               [boundary-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 0.8)]
               [scanline (make-paint #:color (rgba 239 79 55 135))]
               [grid (make-paint #:color "#CAD1DA" #:style 'stroke #:stroke-width 0.5)]
               [font (make-font #:size 10)]
               [label (make-paint #:color "#20344E")])
     (define scale 7)
     (define row 7)
     (define spans (region-spans region row 0 20))
     (define (image-of value)
       (with-skia ([page (make-surface 20 14)])
         (draw-region (surface-canvas page) value fill)
         (surface-snapshot page)))
     (with-skia ([region-image (image-of region)]
                 [difference-image (image-of difference)])
       (draw-simple-text canvas "path -> region: integer pixels" 18 17 font label)
       (draw-simple-text canvas "region-difference: remove center band" 208 17 font label)
       (draw-image-rect canvas region-image 18 30 (* 20 scale) (* 14 scale) #:sampling 'nearest)
       (draw-image-rect canvas difference-image 208 30 (* 20 scale) (* 14 scale) #:sampling 'nearest)
       (for ([x (in-range 21)])
         (draw-line canvas (+ 18 (* x scale)) 30 (+ 18 (* x scale)) (+ 30 (* 14 scale)) grid)
         (draw-line canvas (+ 208 (* x scale)) 30 (+ 208 (* x scale)) (+ 30 (* 14 scale)) grid))
       (for ([y (in-range 15)])
         (draw-line canvas 18 (+ 30 (* y scale)) (+ 18 (* 20 scale)) (+ 30 (* y scale)) grid)
         (draw-line canvas 208 (+ 30 (* y scale)) (+ 208 (* 20 scale)) (+ 30 (* y scale)) grid))
       (for ([span spans])
         (draw-rect canvas (+ 18 (* scale (vector-ref span 0))) (+ 30 (* scale row))
                    (* scale (- (vector-ref span 1) (vector-ref span 0))) scale scanline))
       (with-canvas-state canvas
         (canvas-translate! canvas 18 30)
         (canvas-scale! canvas scale scale)
         (draw-path canvas boundary boundary-paint))
       (draw-simple-text canvas "orange=boundary; red=spans y=7" 18 145 font label)
       (draw-simple-text canvas "binary cells, not coverage" 260 145 font label))))
 #:background 'white)

;;;
;;; Image Sampling, Subsets, Alpha, and Reflections
;;;

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

;;;
;;; Font Controls and Shaping
;;;

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
   (call-with-hebrew-font
    'rtl-shaping 36 "שלום"
    (lambda (font)
      (with-skia ([shaper (make-shaper font)]
                  [paint (make-paint #:color "#20344E")])
        (define run (shape-text shaper "שלום" #:direction 'rtl #:script 'hebr))
        (with-skia ([blob (shaped-run->text-blob shaper run)])
          (define-values (left _top width _height) (text-blob-bounds blob))
          (draw-shaped-run canvas shaper run (- 230 (+ left width)) 58 paint))))))
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

;;;
;;; Text-Blob Positioning and Paragraph Layout
;;;

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

;;;
;;; Picture Playback, Rasterization, Drawables, and Page Margins
;;;

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

;; Alternative parameter choices below complement the preceding API examples.

;;;
;;; Gradient Parameters
;;;

(render-reference-image
 "two-point-conical-offset.png" 180 100
 (lambda (canvas)
   (with-skia ([shader (make-two-point-conical-gradient-shader
                        35 50 5 145 50 55
                        '("#F4D35E" "#326DE6"))]
               [paint (make-paint #:shader shader)])
     (draw-paint canvas paint))))

;;;
;;; Path-Effect Composition and Mask Styles
;;;

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

;;;
;;; Image-Filter Parameters
;;;

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

;;;
;;; Primitive Parameters
;;;

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
 "draw-color-blends-stage8.png" 240 100
 (lambda (canvas)
   (canvas-clear! canvas "#EFA02B")
   (for ([mode '(multiply screen difference)]
         [x '(0 80 160)])
     (with-canvas-state canvas
       (canvas-clip-rect! canvas x 0 80 100)
       (draw-color canvas "#326DE6" #:blend-mode mode)))))

;;;
;;; Path Construction, Conversion, and Measurement
;;;

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

;;;
;;; Text-Blob Placement and Conversion
;;;

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

;;;
;;; Wrapping and Bidirectional Layout
;;;

(render-reference-image
 "layout-rtl-stage8.png" 300 100
 (lambda (canvas)
   (call-with-hebrew-font
    'layout-rtl 22 "אבג דהו זחט"
    (lambda (font)
      (with-skia ([shaper (make-shaper font)]
                  [paint (make-paint #:color "#20344E")])
        (define layout
          (layout-text shaper "אבג דהו זחט" #:width 260
                       #:direction 'rtl #:align 'start))
        (draw-text-layout canvas layout 20 18 paint)))))
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
 "layout-unbreakable-overflow.png" 320 90
 (lambda (canvas)
   (with-skia ([font (make-font #:size 24)]
               [shaper (make-shaper font)]
               [paint (make-paint #:color "#20344E")]
               [guide (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 1)])
     (define text "unbreakable")
     (define natural (abs (shaped-run-advance-x (shape-text shaper text))))
     (define requested (max 1 (/ natural 2)))
     (define layout (layout-text shaper text #:width requested))
     (draw-line canvas (+ 20 requested) 18 (+ 20 requested) 72 guide)
     (draw-text-layout canvas layout 20 25 paint)))
 #:background 'white)

(render-reference-image
 "layout-break-provider-insertion.png" 420 175
 (lambda (canvas)
   (with-skia ([font (make-font #:size 28)]
               [shaper (make-shaper font)]
               [text-paint (make-paint #:color "#20344E")]
               [guide (make-paint #:color "#C9D2DF" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 11)]
               [label-paint (make-paint #:color "#526070")])
     (define text "longword")
     (define opportunity (make-layout-break-opportunity 4 "-"))
     (define (provider paragraph language) (list opportunity))
     (define wide (layout-text shaper text #:width 170 #:break-provider provider))
     (define narrow (layout-text shaper text #:width 90 #:break-provider provider))
     (draw-rect canvas 18 40 170 82 guide)
     (draw-rect canvas 228 40 90 82 guide)
     (draw-simple-text canvas "wide: no break selected" 18 25 label-font label-paint)
     (draw-text-layout canvas wide 18 48 text-paint)
     (draw-simple-text canvas "narrow: selected break inserts -" 228 25
                       label-font label-paint)
     (draw-text-layout canvas narrow 228 48 text-paint)
     (draw-simple-text canvas "logical input stays: longword" 18 148
                       label-font label-paint)))
 #:background 'white)

;; Canvas-state and coverage comparisons use literal coordinates where needed.



;;;
;;; Canvas State and Clip Coverage
;;;

(render-native-scale-reference-image
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

(render-native-scale-reference-image
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

(render-native-scale-reference-image
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
 "clip-within-existing-clip.png" 240 130
 (lambda (canvas)
   (with-skia ([state (make-surface 8 6 #:background 'white)]
               [paint (make-paint #:color 'blue #:antialias? #f)]
               [font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define state-canvas (surface-canvas state))
     (for ([operation '(intersect difference)] [x '(12 132)]
           [name '("intersect" "difference")])
       (canvas-clear! state-canvas 'white)
       (with-canvas-state state-canvas
         (canvas-clip-rect! state-canvas 0 0 6 6)
         (canvas-clip-rect! state-canvas 2 2 2 2 #:operation operation)
         (draw-paint state-canvas paint))
       (with-skia ([preview (surface-snapshot state)])
         (draw-simple-text canvas name x 20 font label)
         (draw-image-rect canvas preview x 30 96 72 #:sampling 'nearest)))
     (draw-simple-text canvas "samples at y=3: x=3, 1, 7" 35 122 font label)))
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



;;;
;;; Paint Coverage
;;;

(render-native-scale-reference-image
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

(render-native-scale-reference-image
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

;;;
;;; Shader Edge and Empty Behavior
;;;

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



;;;
;;; Gamma Mask Coverage
;;;

(render-native-scale-reference-image
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



;;;
;;; Shader-Source Image Filtering
;;;

(render-reference-image
 "shader-source-filter-stage9.png" 200 100
 (lambda (canvas)
   (with-skia ([shader (make-linear-gradient-shader 20 0 180 0 '(red blue))]
               [filter (make-shader-image-filter shader #:crop '(10 10 180 80))]
               [paint (make-paint #:color 'white #:image-filter filter)])
     (draw-paint canvas paint))
)
 #:background 'white)



;;;
;;; Arc Chords and Clipped Colors
;;;

(render-reference-image
 "arc-chord-stage9.png" 180 100
 (lambda (canvas)
   (with-skia ([paint (make-paint #:color "#326DE6")])
     (draw-arc canvas 28 18 124 64 205 250 paint #:use-center? #f))
)
 #:background 'white)

(render-reference-image
 "draw-color-device-clip.png" 160 160
 (lambda (canvas)
   ;; Draw on the literal 8 by 8 surface before enlarging its pixels for display.
   (with-skia ([surface (make-surface 8 8 #:background 'white)])
     (define source-canvas (surface-canvas surface))
     (canvas-clip-rect! source-canvas 0 0 4 8)
     (canvas-translate! source-canvas 100 100)
     (draw-color source-canvas 'red)
     (with-skia ([image (surface-snapshot surface)])
       (draw-image-rect canvas image 16 16 128 128 #:sampling 'nearest))))
 #:background "#E8ECF0")

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



;;;
;;; Polygon and Contour Extension
;;;

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

;;;
;;; Floating Gradients, Image Grids, Shaping, and Picture Composition
;;;

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
                 90 50 55
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
                 90 50
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
                 55 52 5 135 52 58
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

;;;
;;; Conceptual Diagrams
;;;
;; These scenes deliberately combine a small executed fixture with guides that
;; explain the fixture's coordinate contract.  The guides are not presented as
;; pixels produced by the adjacent API call.

(render-reference-image
 "concept-font-metrics.png" 460 230
 (lambda (canvas)
   (with-skia ([font (make-font #:size 64)]
               [text-ink (make-paint #:color "#20344E")]
               [ascent-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 1)]
               [baseline-ink (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1.5)]
               [descent-ink (make-paint #:color "#2C9B6F" #:style 'stroke #:stroke-width 1)]
               [measure-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [axis-ink (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 13)]
               [small-font (make-font #:size 11)]
               [label (make-paint #:color "#20344E")])
     (define baseline 135)
     (define text "Hgx")
     (define metrics (font-get-metrics font))
     (define ascent (+ baseline (font-metrics-ascent metrics)))
     (define descent (+ baseline (font-metrics-descent metrics)))
     (define cap-height (font-metrics-cap-height metrics))
     (define x-height (font-metrics-x-height metrics))
     (draw-simple-text canvas "baseline-relative metrics" 22 22 label-font label)
     (draw-arrow canvas 22 52 22 177 axis-ink)
     (draw-simple-text canvas "y+" 8 190 small-font label)
     (draw-line canvas 42 ascent 280 ascent ascent-ink)
     (draw-line canvas 42 baseline 280 baseline baseline-ink)
     (draw-line canvas 42 descent 280 descent descent-ink)
     (draw-simple-text canvas text 58 baseline font text-ink)
     (draw-simple-text canvas
                       (format "ascent  a = ~a < 0" (one-decimal (font-metrics-ascent metrics)))
                       294 (+ ascent 4) small-font label)
     (draw-simple-text canvas "baseline  b" 294 (+ baseline 4) small-font label)
     (draw-simple-text canvas
                       (format "descent  d = ~a > 0" (one-decimal (font-metrics-descent metrics)))
                       294 (+ descent 4) small-font label)
     (draw-arrow canvas 270 baseline 270 ascent measure-ink)
     (draw-simple-text canvas "-a" 247 (/ (+ baseline ascent) 2) small-font label)
     (draw-arrow canvas 270 baseline 270 descent measure-ink)
     (draw-simple-text canvas "d" 250 (/ (+ baseline descent) 2) small-font label)
     (when (positive? cap-height)
       (define guide (- baseline cap-height))
       (draw-line canvas 42 guide 210 guide measure-ink)
       (draw-simple-text canvas "cap height" 216 (+ guide 4) small-font label))
     (when (positive? x-height)
       (define guide (- baseline x-height))
       (draw-line canvas 42 guide 210 guide measure-ink)
       (draw-simple-text canvas "x-height" 216 (+ guide 4) small-font label))
     (draw-simple-text canvas "guides: b+a, b, b+d" 42 208 label-font label)))
 #:background 'white)

(render-reference-image
 "concept-text-advance.png" 460 190
 (lambda (canvas)
   (with-skia ([font (make-font #:size 54)]
               [ink (make-paint #:color "#20344E")]
               [bounds-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 1.5)]
               [advance-ink (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1)]
               [baseline-ink (make-paint #:color "#AEB7C2" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 12)]
               [label (make-paint #:color "#20344E")])
     (define baseline 99)
     (define (panel x text trailing?)
       (define-values (bx by bw bh) (simple-text-bounds font text))
       (define advance (measure-simple-text font text))
       (draw-simple-text canvas (if trailing? "A followed by a space" "A") x 24 label-font label)
       (draw-line canvas (- x 10) baseline (+ x 178) baseline baseline-ink)
       (draw-line canvas x (- baseline 12) x (+ baseline 12) advance-ink)
       (draw-simple-text canvas text x baseline font ink)
       (draw-rect canvas (+ x bx) (+ baseline by) bw bh bounds-ink)
       (draw-arrow canvas x 137 (+ x advance) 137 advance-ink)
       (draw-simple-text canvas "advance: next origin" x 156 label-font label)
       (when trailing?
         (draw-line canvas (+ x (measure-simple-text font "A")) 118 (+ x advance) 118 advance-ink)
         (draw-simple-text canvas "trailing space (annotation)" (+ x 4) 177 label-font label))
       (draw-simple-text canvas "red = measured ink bounds" x 43 label-font label))
     (panel 35 "A" #f)
     (panel 260 "A " #t)))
 #:background 'white)

(render-reference-image
 "concept-layout-box.png" 480 300
 (lambda (canvas)
   (with-skia ([font (make-font #:size 18)]
               [shaper (make-shaper font)]
               [ink (make-paint #:color "#20344E")]
               [box-ink (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1.3)]
               [guide-ink (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 1)]
               [faint-ink (make-paint #:color "#AEB7C2" #:style 'stroke #:stroke-width 1)]
               [label-font (make-font #:size 11)]
               [title-font (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define layout
       (layout-text shaper "First visible line\nSecond visible line\nThird visible line"
                    #:width 205 #:line-height 34))
     (define x 24)
     (define y 34)
     (define first (car (text-layout-lines layout)))
     (draw-simple-text canvas "layout origin, baselines, and height" 24 18 title-font label)
     (draw-rect canvas x y (text-layout-width layout) (text-layout-height layout) box-ink)
     (draw-text-layout canvas layout x y ink)
     (for ([line (in-list (text-layout-lines layout))])
       (define by (+ y (text-layout-line-baseline line)))
       (draw-line canvas x by (+ x (text-layout-width layout)) by faint-ink))
     (draw-arrow canvas 10 34 x y guide-ink)
     (draw-simple-text canvas "box origin" 24 147 label-font label)
     (define first-y (+ y (text-layout-line-baseline first)))
     (draw-arrow canvas 240 y 240 first-y guide-ink)
     (draw-simple-text canvas "first baseline = max(0, -ascent)" 250 61 label-font label)
     (draw-arrow canvas 220 first-y 220 (+ first-y (text-layout-line-height layout)) guide-ink)
     (draw-simple-text canvas "line-height: baseline step" 250 97 label-font label)
     (draw-arrow canvas 452 y 452 (+ y (text-layout-height layout)) guide-ink)
     (draw-simple-text canvas "reported\nheight" 404 133 label-font label)
     (draw-simple-text canvas "requested wrapping width is not a clip" 24 175 title-font label)
     (define word "unbreakable")
     (define requested 105)
     (define overflow (layout-text shaper word #:width requested))
     (draw-rect canvas 24 194 requested 63 box-ink)
     (draw-line canvas (+ 24 requested) 186 (+ 24 requested) 269 guide-ink)
     (draw-text-layout canvas overflow 24 202 ink)
     (draw-corner-bracket canvas 24 194 (text-layout-width overflow) (text-layout-height overflow)
       faint-ink)
     (draw-simple-text canvas "requested width" 24 278 label-font label)
     (draw-simple-text canvas "reported layout box; whole word remains visible" 155 278 label-font
       label)))
 #:background 'white)

(render-reference-image
 "concept-transform-order.png" 480 240
 (lambda (canvas)
   (with-skia ([grid (make-paint #:color "#D9DEE6" #:style 'stroke #:stroke-width 1)]
               [axis (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [source (make-paint #:color "#AEB7C2")]
               [result (make-paint #:color "#326DE6")]
               [point-ink (make-paint #:color "#E94F37")]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define translation (matrix-translate 10 20))
     (define scaling (matrix-scale 2))
     (define-values (tsx tsy) (vector->values (matrix-map-point (matrix-compose translation scaling) 3 4)))
     (define-values (stx sty) (vector->values (matrix-map-point (matrix-compose scaling translation) 3 4)))
     (unless (and (= tsx 16) (= tsy 28)
                  (= stx 26) (= sty 48))
       (error 'concept-transform-order "matrix fixture endpoints changed"))
     (define (panel x title-text final-x final-y equation calls)
       (draw-simple-text canvas title-text x 18 title label)
       (define ox (+ x 28))
       (define oy 78)
       (for ([n '(0 20 40 60 80 100)])
         (draw-line canvas (+ ox n) 35 (+ ox n) 145 grid)
         (draw-line canvas ox (+ 35 n) (+ ox 110) (+ 35 n) grid))
       (draw-arrow canvas ox oy (+ ox 85) oy axis)
       (draw-arrow canvas ox oy ox (+ oy 56) axis)
       (draw-simple-text canvas "x" (+ ox 89) (+ oy 4) font label)
       (draw-simple-text canvas "y" (- ox 5) (+ oy 69) font label)
       (draw-circle canvas (+ ox 3) (+ oy 4) 4 source)
       (draw-simple-text canvas "p=(3,4)" (+ ox 7) (+ oy -4) font label)
       (draw-circle canvas (+ ox final-x) (+ oy final-y) 5 point-ink)
       (draw-simple-text canvas (format "(~a,~a)" (round final-x) (round final-y))
                         (+ ox final-x 7) (+ oy final-y 4) font label)
       (draw-simple-text canvas equation x 166 font label)
       (draw-simple-text canvas calls x 186 font label))
     (panel 20 "T then S on the canvas" tsx tsy "T(S(p)) = (16,28)"
            "canvas: translate, then scale  =>  T × S")
     (panel 255 "S then T on the canvas" stx sty "S(T(p)) = (26,48)"
            "canvas: scale, then translate  =>  S × T")
     (draw-simple-text canvas
       "Matrix composition names argument order; points receive the rightmost map first." 20 220
       font label)))
 #:background 'white)

;; Resetting the canvas transform needs literal target coordinates.  This
;; scene is captured before the Reference's normal 2x presentation scale is
;; applied, so the reset cannot accidentally erase that presentation scale.
(render-native-scale-reference-image
 "concept-clip-state.png" 480 240
 (lambda (canvas)
   (with-skia ([grid (make-paint #:color "#E5E9ED" #:style 'stroke #:stroke-width 1)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")]
               [green (make-paint #:color "#2C9B6F")]
               [clip-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 2)]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define (grid-panel x)
       (draw-rect canvas x 35 132 130 border)
       (for ([n (in-range 0 141 20)])
         (draw-line canvas (+ x n) 35 (+ x n) 165 grid)
         (draw-line canvas x (+ 35 n) (+ x 132) (+ 35 n) grid)))
     (for ([x '(20 174 328)]) (grid-panel x))
     (draw-simple-text canvas "1. establish clip" 20 19 title label)
     (with-canvas-state canvas
       (canvas-translate! canvas 40 55)
       (canvas-clip-rect! canvas 0 0 75 55)
       (draw-rect canvas 0 0 120 90 blue))
     (draw-rect canvas 40 55 75 55 clip-ink)
     (draw-simple-text canvas "target clip: (40,55,75,55)" 20 181 font label)
     (draw-simple-text canvas "2. reset transform" 174 19 title label)
     (with-canvas-state canvas
       (canvas-translate! canvas 194 55)
       (canvas-clip-rect! canvas 0 0 75 55)
       (canvas-reset-transform! canvas)
       ;; The established clip is in target coordinates.  This orange draw
       ;; starts at the literal target origin, after reset.
       (draw-rect canvas 174 35 132 130 orange))
     (draw-rect canvas 194 55 75 55 clip-ink)
     (draw-simple-text canvas "clip did not move" 174 181 font label)
     (draw-simple-text canvas "3. restore state" 328 19 title label)
     (with-canvas-state canvas
       (canvas-translate! canvas 348 55)
       (canvas-clip-rect! canvas 0 0 75 55)
       (draw-rect canvas 0 0 120 90 blue))
     (draw-circle canvas 430 145 10 green)
     (draw-rect canvas 348 55 75 55 clip-ink)
     (draw-simple-text canvas "pixels remain" 328 181 font label)
     (draw-simple-text canvas "red boundary = established clip; grid and labels are explanatory" 20
       222 font label)))
 #:background 'white)

(render-reference-image
 "concept-layer-compositing.png" 480 240
 (lambda (canvas)
   (with-skia ([checker-a (make-paint #:color "#E8EDF2")]
               [checker-b (make-paint #:color "#FFFFFF")]
               [per-draw (make-paint #:color (rgba 50 109 230 120))]
               [opaque (make-paint #:color "#326DE6")]
               [group-alpha (make-paint #:color (rgba 0 0 0 120))]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [arrow-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define (checker x y)
       (for* ([row (in-range 5)] [column (in-range 7)])
         (draw-rect canvas (+ x (* column 18)) (+ y (* row 18)) 18 18
                    (if (even? (+ row column)) checker-a checker-b))))
     (define (rectangles target left top paint)
       (draw-rounded-rect target left top 68 48 7 7 paint)
       (draw-rounded-rect target (+ left 40) top 68 48 7 7 paint))
     (draw-simple-text canvas "opacity applied to each draw" 24 20 title label)
     (checker 24 36)
     (rectangles canvas 38 55 per-draw)
     (draw-rect canvas 24 36 126 90 border)
     (draw-simple-text canvas "overlap accumulates" 24 145 font label)
     (draw-simple-text canvas "opaque children in transparent layer" 258 20 title label)
     (checker 300 36)
     (with-canvas-layer canvas #:paint group-alpha #:bounds '(300 36 126 90)
       (rectangles canvas 314 55 opaque))
     (draw-rect canvas 300 36 126 90 border)
     (draw-arrow canvas 227 82 286 82 arrow-ink)
     (draw-simple-text canvas "restore: composite group once" 205 105 font label)
     (draw-simple-text canvas "same opacity in overlap" 300 145 font label)
     (draw-simple-text canvas "A state save has no transparent intermediate target; a layer does."
       24 193 title label)
     (draw-simple-text canvas
       "The purple arrow is the layer restore/composite step, not a draw call." 24 215 font label)))
 #:background 'white)

(render-reference-image
 "concept-image-placement.png" 480 230
 (lambda (canvas)
   (with-skia ([source-surface (make-surface 48 32 #:background 'transparent)]
               [red (make-paint #:color "#E94F37")]
               [blue (make-paint #:color "#326DE6")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [source-ink (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
               [offset-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 2)]
               [arrow-ink (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-circle (surface-canvas source-surface) 22 15 11 red)
     (draw-rect (surface-canvas source-surface) 32 5 10 10 blue)
     (with-skia ([input (surface-snapshot source-surface)]
                 [filter (make-offset-image-filter 12 8)])
       (define-values (result returned-source offset)
         (image-apply-filter input filter #:clip '(0 0 72 54)))
       (call-with-skia-resource
        result
        (lambda (result-image)
          (draw-simple-text canvas "filtering coordinates" 18 18 title label)
          (draw-image-rect canvas input 18 35 96 64 #:sampling 'nearest)
          (draw-rect canvas 18 35 96 64 border)
          (draw-simple-text canvas "returned image" 190 18 title label)
          (draw-image-rect canvas result-image 190 35 144 108 #:sampling 'nearest)
          ;; Native metadata drives the labels; the large highlighted box is
          ;; the returned source rectangle at the same 3x presentation scale.
          (define sx (vector-ref returned-source 0))
          (define sy (vector-ref returned-source 1))
          (define sw (vector-ref returned-source 2))
          (define sh (vector-ref returned-source 3))
          (draw-rect canvas (+ 190 (* 3 sx)) (+ 35 (* 3 sy)) (* 3 sw) (* 3 sh) source-ink)
          (draw-simple-text canvas (format "source = (~a,~a,~a,~a)" sx sy sw sh)
                            190 158 font label)
          (draw-arrow canvas 335 90 390 90 arrow-ink)
          (draw-simple-text canvas "place selected source" 348 75 font label)
          (draw-simple-text canvas "at returned offset" 348 90 font label)
          (draw-rect canvas 348 105 112 86 border)
          (define ox (vector-ref offset 0))
          (define oy (vector-ref offset 1))
          ;; A small schematic keeps a nonzero returned-source origin visible
          ;; even if a platform's native result is full-image source.
          (draw-rect canvas 374 124 62 42 source-ink)
          (draw-corner-bracket canvas 360 114 84 60 offset-ink)
          (draw-simple-text canvas (format "offset = (~a,~a)" ox oy) 348 206 font label)
          (draw-simple-text canvas "source upper-left goes here; full result origin need not" 18
            216 font label))))))
 #:background 'white)

(render-reference-image
 "concept-filter-graph.png" 480 300
 (lambda (canvas)
   (with-skia ([fixture (make-surface 105 58 #:background 'transparent)]
               [blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [crop-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 2)]
               [arrow-ink (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-circle (surface-canvas fixture) 30 30 20 blue)
     (draw-rounded-rect (surface-canvas fixture) 55 12 35 35 6 6 orange)
     (with-skia ([image (surface-snapshot fixture)]
                 [crop (make-crop-image-filter '(20 8 50 42))]
                 [blur (make-blur-image-filter 7 7)]
                 [crop-then-blur (make-blur-image-filter 7 7 #:input crop)]
                 [blur-then-crop (make-crop-image-filter '(20 8 50 42) #:input blur)]
                 [left-paint (make-paint #:image-filter crop-then-blur)]
                 [right-paint (make-paint #:image-filter blur-then-crop)])
       (define (filtered-result paint)
         (with-skia ([result-surface (make-surface 105 58 #:background 'white)])
           (draw-circle (surface-canvas result-surface) 30 30 20 paint)
           (draw-rounded-rect (surface-canvas result-surface) 55 12 35 35 6 6 paint)
           (surface-snapshot result-surface)))
       (with-skia ([left-result (filtered-result left-paint)]
                   [right-result (filtered-result right-paint)])
       (draw-simple-text canvas "source -> crop -> blur" 20 19 title label)
       (draw-image canvas left-result 20 38)
       (draw-rect canvas 20 38 105 58 border)
       (draw-rect canvas 40 46 50 42 crop-ink)
       (draw-simple-text canvas "crop limits blur input" 20 111 font label)
       (draw-simple-text canvas "source -> blur -> crop" 260 19 title label)
       (draw-image canvas right-result 260 38)
       (draw-rect canvas 260 38 105 58 border)
       (draw-rect canvas 280 46 50 42 crop-ink)
       (draw-simple-text canvas "crop limits blur output" 260 111 font label)
       (for ([x '(25 135 245 355)])
         (draw-rounded-rect canvas x 151 82 34 5 5 border))
       (for ([name '("dynamic\nsource" "crop" "blur" "output")]
             [x '(38 159 269 374)])
         (draw-simple-text canvas name x 172 font label))
       (draw-arrow canvas 107 168 132 168 arrow-ink)
       (draw-arrow canvas 217 168 242 168 arrow-ink)
       (draw-arrow canvas 327 168 352 168 arrow-ink)
       (draw-simple-text canvas "#f input slot = the dynamic drawing source" 20 220 title label)
       (draw-simple-text canvas
         "make-compose-image-filter feeds the inner graph into the outer graph's #f input slots."
         20 246 font label)
       (draw-simple-text canvas "Node construction connects a graph; it does not process pixels."
         20 270 font label)))))
 #:background 'white)

(render-reference-image
 "concept-pixel-stride.png" 480 210
 (lambda (canvas)
   (with-skia ([pixel-a (make-paint #:color "#326DE6")]
               [pixel-b (make-paint #:color "#2C9B6F")]
               [pixel-c (make-paint #:color "#EFA02B")]
               [padding (make-paint #:color "#D9DEE6")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [measure (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define cell 13)
     (define x0 42)
     (define (row y row-index)
       (draw-simple-text canvas (format "row ~a (starts at ~a)" row-index (* row-index 16)) 42
         (- y 7) font label)
       (for ([byte (in-range 16)])
         (draw-rect canvas (+ x0 (* byte cell)) y cell 28
                    (cond [(< byte 4) pixel-a]
                          [(< byte 8) pixel-b]
                          [(< byte 12) pixel-c]
                          [else padding]))
         (draw-rect canvas (+ x0 (* byte cell)) y cell 28 border))
       (draw-simple-text canvas "pixel 0" (+ x0 3) (+ y 18) font label)
       (draw-simple-text canvas "pixel 1" (+ x0 55) (+ y 18) font label)
       (draw-simple-text canvas "pixel 2" (+ x0 107) (+ y 18) font label)
       (draw-simple-text canvas "padding" (+ x0 160) (+ y 18) font label))
     (draw-simple-text canvas "3 × 2 RGBA8888: four bytes per pixel" 42 20 title label)
     (row 47 0)
     (row 108 1)
     (draw-arrow canvas 42 151 (+ x0 (* 16 cell)) 151 measure)
     (draw-simple-text canvas "row stride = 16 bytes (12 pixel bytes + 4 padding bytes)" 42 169
       font label)
     (draw-simple-text canvas "returned (stride, minimum addressable, allocation) = (16, 28, 32)"
       42 192 title label)))
 #:background 'white)

(render-reference-image
 "concept-page-margins.png" 480 240
 (lambda (canvas)
   (with-skia ([page (make-paint #:color "#EEF1F4")]
               [content (make-paint #:color "#DCEAF8")]
               [ink (make-paint #:color "#326DE6")]
               [clip-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 2)]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [measure (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define px 70) (define py 32) (define pw 300) (define ph 150)
     (define left 42) (define top 24) (define right 62) (define bottom 34)
     (define cx (+ px left)) (define cy (+ py top))
     (define cw (- pw left right)) (define ch (- ph top bottom))
     (draw-simple-text canvas "page origin and unequal margins (left, top, right, bottom)" 70 18
       title label)
     (draw-rect canvas px py pw ph page)
     (draw-rect canvas cx cy cw ch content)
     (draw-rect canvas px py pw ph border)
     (draw-rect canvas cx cy cw ch clip-ink)
     (draw-circle canvas px py 4 ink)
     (draw-simple-text canvas "page origin" (+ px 7) (+ py 15) font label)
     (draw-circle canvas cx cy 4 ink)
     (draw-simple-text canvas "callback origin" (+ cx 6) (+ cy 14) font label)
     (draw-arrow canvas px (+ py ph 10) cx (+ py ph 10) measure)
     (draw-simple-text canvas "left" (+ px 8) (+ py ph 27) font label)
     (draw-arrow canvas (+ cx cw) (+ py ph 10) (+ px pw) (+ py ph 10) measure)
     (draw-simple-text canvas "right" (- (+ cx cw) 4) (+ py ph 27) font label)
     (draw-arrow canvas (- px 16) py (- px 16) cy measure)
     (draw-simple-text canvas "top" 15 (+ py 18) font label)
     (draw-arrow canvas (- px 16) (+ cy ch) (- px 16) (+ py ph) measure)
     (draw-simple-text canvas "bottom" 15 (- (+ py ph) 4) font label)
     (draw-circle canvas (+ cx cw 14) (+ cy ch 8) 18 ink)
     (draw-simple-text canvas "red = content clip when clip? is true" (+ cx 7) (- (+ cy ch) 8) font
       label)
     (draw-simple-text canvas
       "With clip? false, the blue mark may cross it; neither origin changes." 70 224 font label)))
 #:background 'white)

(render-reference-image
 "concept-raster-padding.png" 480 230
 (lambda (canvas)
   (with-skia ([padding (make-paint #:color "#E8EDF2")]
               [content (make-paint #:color "#DCEAF8")]
               [blur (make-paint #:color (rgba 50 109 230 90))]
               [ink (make-paint #:color "#326DE6")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [guide (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define rx 70) (define ry 42) (define rw 280) (define rh 130)
     (define left 32) (define top 20) (define right 48) (define bottom 28)
     (draw-simple-text canvas "raster fallback: padding enlarges, content origin stays fixed" 28 20
       title label)
     (draw-rect canvas rx ry rw rh padding)
     (draw-rect canvas (+ rx left) (+ ry top) (- rw left right) (- rh top bottom) content)
     (draw-rect canvas rx ry rw rh border)
     (draw-rect canvas (+ rx left) (+ ry top) (- rw left right) (- rh top bottom) guide)
     (draw-circle canvas (+ rx left 78) (+ ry top 38) 31 blur)
     (draw-circle canvas (+ rx left 78) (+ ry top 38) 20 ink)
     (draw-simple-text canvas "callback (0,0)" (+ rx left 4) (+ ry top 15) font label)
     (draw-simple-text canvas "logical content" (+ rx left 92) (+ ry top 15) font label)
     (draw-simple-text canvas "transparent padded raster region" rx (+ ry rh 18) font label)
     (draw-arrow canvas (+ rx left) 195 rx 195 guide)
     (draw-simple-text canvas "final image placement: (x-left, y-top)" 70 214 font label)))
 #:background 'white)

(render-reference-image
 "concept-path-bounds.png" 480 250
 (lambda (canvas)
   (with-skia ([path (make-path '((move 40 170) (cubic 100 45 320 45 390 170)))]
               [curve (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 4)]
               [control (make-paint #:color "#AEB7C2" #:style 'stroke #:stroke-width 1)]
               [stored (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 2)]
               [tight (make-paint #:color "#2C9B6F" #:style 'stroke #:stroke-width 2)]
               [point (make-paint #:color "#EFA02B")]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define-values (bx by bw bh) (vector->values (path-bounds path)))
     (define-values (tx ty tw th) (vector->values (path-tight-bounds path)))
     (draw-simple-text canvas
       "cubic controls are stored points, but the curve does not pass through them" 28 19 title label)
     (draw-line canvas 40 170 100 45 control)
     (draw-line canvas 100 45 320 45 control)
     (draw-line canvas 320 45 390 170 control)
     (draw-rect canvas bx by bw bh stored)
     (draw-rect canvas tx ty tw th tight)
     (draw-path canvas path curve)
     (for ([p '((40 170) (100 45) (320 45) (390 170))])
       (draw-circle canvas (first p) (second p) 4 point))
     (draw-simple-text canvas "end" 26 189 font label)
     (draw-simple-text canvas "control 1" 72 62 font label)
     (draw-simple-text canvas "control 2" 292 62 font label)
     (draw-simple-text canvas "end" 385 189 font label)
     (draw-simple-text canvas "red: path-bounds (stored points)" 42 214 font label)
     (draw-simple-text canvas "green: path-tight-bounds (curve geometry)" 230 214 font label)
     (draw-simple-text canvas
       "Neither rectangle includes stroke width, filters, transform, or clip." 42 238 font label)))
 #:background 'white)

(render-reference-image
 "concept-fill-rules.png" 480 255
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [white (make-paint #:color 'white)]
               [arrow-ink (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 1.5)]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define (panel x y title-text center-filled? directions)
       (draw-rect canvas x y 205 92 border)
       (draw-simple-text canvas title-text (+ x 8) (+ y 16) font label)
       (draw-circle canvas (+ x 62) (+ y 55) 28 blue)
       (unless center-filled? (draw-circle canvas (+ x 62) (+ y 55) 13 white))
       (draw-circle canvas (+ x 62) (+ y 55) 13 arrow-ink)
       (draw-arrow canvas (+ x 90) (+ y 46) (+ x 84) (+ y 35) arrow-ink)
       (draw-arrow canvas (+ x 75) (+ y 67) (+ x 64) (+ y 71) arrow-ink)
       (draw-simple-text canvas directions (+ x 110) (+ y 43) font label)
       (draw-simple-text canvas (if center-filled? "center filled" "center hole") (+ x 110)
         (+ y 65) font label))
     (draw-simple-text canvas "nested contours: direction affects winding, not even-odd parity" 28
       19 title label)
     (panel 28 38 "winding: same direction" #t "signed total != 0")
     (panel 247 38 "winding: reversed inner" #f "signed total = 0")
     (panel 28 145 "even-odd: same direction" #f "crossing parity = even")
     (panel 247 145 "even-odd: reversed inner" #f "crossing parity = even")
     (draw-simple-text canvas
       "Arrows label contour traversal; the test ray/crossing count is a conceptual guide." 28 250
       font label)))
 #:background 'white)

(render-reference-image
 "concept-nine-patch.png" 480 245
 (lambda (canvas)
   (with-skia ([fixed (make-paint #:color "#326DE6")]
               [stretch (make-paint #:color "#DCEAF8")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [measure (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define (grid x y widths heights title-text)
       (draw-simple-text canvas title-text x (- y 9) title label)
       (define xx x)
       (for ([i (in-range 3)] [w (in-list widths)])
         (define yy y)
         (for ([j (in-range 3)] [h (in-list heights)])
           (draw-rect canvas xx yy w h (if (or (= i 1) (= j 1)) stretch fixed))
           (draw-rect canvas xx yy w h border)
           (draw-simple-text canvas (format "~a" (+ 1 i (* 3 j))) (+ xx (/ w 2) -3)
             (+ yy (/ h 2) 4) font label)
           (set! yy (+ yy h)))
         (set! xx (+ xx w))))
     (draw-simple-text canvas "matching numbered cells preserve source correspondence" 28 19 title
       label)
     (grid 45 55 '(28 54 28) '(20 38 20) "source; center = (28,20,54,38)")
     (grid 245 55 '(28 130 28) '(20 75 20) "enlarged destination")
     (draw-arrow canvas 168 104 226 104 measure)
     (draw-simple-text canvas "fixed corners" 45 174 font label)
     (draw-simple-text canvas "edges: one axis; center: both" 245 190 font label)
     (draw-simple-text canvas
       "If destination is smaller than fixed spans, fixed spans shrink and stretch spans can collapse." 28 218 font label)))
 #:background 'white)

(render-reference-image
 "concept-text-clusters.png" 480 245
 (lambda (canvas)
   (with-skia ([border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [header (make-paint #:color "#DCEAF8")]
               [glyph (make-paint #:color "#326DE6")]
               [cluster (make-paint #:color "#EFA02B")]
               [font (make-font #:size 12)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define x 30) (define y 40) (define widths '(105 90 100 120))
     (define headers '("characters" "UTF-8 bytes" "glyph records" "cluster start"))
     (define rows '(("e-acute" "0..1" "glyph 0" "byte 0")
                    ("A" "2" "glyph 1" "byte 2")))
     (draw-simple-text canvas
       "characters, UTF-8 offsets, and glyph metadata are different index spaces" 30 19 title label)
     (for ([h headers] [w widths] [i (in-naturals)])
       (define xx (+ x (apply + (take widths i))))
       (draw-rect canvas xx y w 33 header)
       (draw-rect canvas xx y w 33 border)
       (draw-simple-text canvas h (+ xx 6) (+ y 21) font label))
     (for ([row rows] [j (in-naturals)])
       (for ([cell row] [w widths] [i (in-naturals)])
         (define xx (+ x (apply + (take widths i))))
         (define yy (+ y 33 (* j 37)))
         (draw-rect canvas xx yy w 37 border)
         (draw-simple-text canvas cell (+ xx 6) (+ yy 23) font label)))
     (draw-simple-text canvas
       "2 Racket characters; 3 UTF-8 bytes: e-acute starts at 0, A starts at 2." 30 161 font label)
     (draw-rect canvas 30 181 194 36 glyph)
     (draw-simple-text canvas "several characters" 66 204 font label)
     (draw-arrow canvas 232 199 278 199 cluster)
     (draw-rect canvas 285 181 150 36 header)
     (draw-simple-text canvas "one shaped glyph" 304 204 font label)
     (draw-simple-text canvas
       "Ligatures can map several characters to one glyph; verify the selected font." 30 233 font
       label)))
 #:background 'white)

(render-reference-image
 "concept-text-path-frame.png" 480 240
 (lambda (canvas)
   (with-skia ([path-ink (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 3)]
               [frame (make-paint #:color "#D64F45" #:style 'stroke #:stroke-width 1.5)]
               [normal (make-paint #:color "#2C9B6F" #:style 'stroke #:stroke-width 1.5)]
               [glyph (make-paint #:color "#20344E")]
               [font (make-font #:size 18)]
               [small (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas "text-on-path uses an arc-length tangent/normal frame" 28 19 title
       label)
     (draw-line canvas 45 105 425 105 path-ink)
     (draw-arrow canvas 70 105 155 105 path-ink)
     (draw-simple-text canvas "contour direction" 75 87 small label)
     (define sx 230) (define sy 105)
     (draw-circle canvas sx sy 4 frame)
     (draw-arrow canvas sx sy (+ sx 60) sy frame)
     (draw-arrow canvas sx sy sx (+ sy 48) normal)
     (draw-simple-text canvas "tangent (tx,ty)" (+ sx 8) 94 small label)
     (draw-simple-text canvas "normal (-ty,tx)" (+ sx 16) (+ sy 43) small label)
     (draw-arrow canvas 45 130 sx 130 frame)
     (draw-simple-text canvas "s = start + gx" 112 148 small label)
     (draw-circle canvas sx (+ sy 48) 3 glyph)
     (draw-simple-text canvas "A" (+ sx 10) (+ sy 72) font glyph)
     (draw-simple-text canvas "glyph origin = P(s) + (normal + gy) * (-ty,tx)" 28 185 title label)
     (draw-simple-text canvas
       "On a rightward path in downward-positive coordinates, positive normal offset is downward."
       28 213 small label)))
 #:background 'white)

(render-reference-image
 "concept-raster-density.png" 480 225
 (lambda (canvas)
   (with-skia ([blue (make-paint #:color "#326DE6")]
               [orange (make-paint #:color "#EFA02B")]
               [light (make-paint #:color "#DCEAF8")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [arrow-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas "two density routes keep physical pixels and logical units distinct"
       28 19 title label)
     (draw-simple-text canvas "image->pict backing scale 2" 35 49 title label)
     (draw-rect canvas 35 62 120 80 light)
     (for ([n (in-range 0 7)]) (draw-line canvas (+ 35 (* n 20)) 62 (+ 35 (* n 20)) 142 border))
     (draw-rect canvas 35 62 120 80 border)
     (draw-simple-text canvas "120 x 80 pixels" 43 158 font label)
     (draw-arrow canvas 160 101 210 101 arrow-ink)
     (draw-rect canvas 220 82 60 40 blue)
     (draw-simple-text canvas "60 x 40 logical units" 205 158 font label)
     (draw-simple-text canvas "picture->pict raster scale 2" 35 188 title label)
     (draw-rect canvas 275 177 120 34 orange)
     (draw-simple-text canvas "120 x 80 logical units -> 240 x 160 pixels" 155 221 font label)))
 #:background 'white)

(render-reference-image
 "concept-resource-lifetimes.png" 480 245
 (lambda (canvas)
   (with-skia ([owner (make-paint #:color "#326DE6")]
               [borrowed (make-paint #:color "#EFA02B")]
               [independent (make-paint #:color "#2C9B6F")]
               [expired (make-paint #:color "#D9DEE6")]
               [axis (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas
       "ownership and borrowed-view validity are timelines, not one universal tree" 28 19 title label)
     (draw-arrow canvas 75 52 440 52 axis)
     (for ([x '(90 230 350)]) (draw-line canvas x 43 x 213 axis))
     (draw-simple-text canvas "open" 80 40 font label)
     (draw-simple-text canvas "owner closes" 205 40 font label)
     (draw-simple-text canvas "later" 334 40 font label)
     (draw-simple-text canvas "CPU surface" 28 87 font label)
     (draw-rect canvas 90 68 140 28 owner)
     (draw-simple-text canvas "owner open" 130 87 font label)
     (draw-rect canvas 90 100 140 24 borrowed)
     (draw-simple-text canvas "borrowed canvas usable" 103 117 font label)
     (draw-rect canvas 230 100 120 24 expired)
     (draw-simple-text canvas "invalid" 268 117 font label)
     (draw-rect canvas 150 132 230 28 independent)
     (draw-simple-text canvas "independent snapshot remains open" 177 151 font label)
     (draw-simple-text canvas "buffer callback" 28 190 font label)
     (draw-rect canvas 90 174 140 26 borrowed)
     (draw-simple-text canvas "pixmap/subset valid" 110 192 font label)
     (draw-rect canvas 230 174 120 26 expired)
     (draw-simple-text canvas "invalid" 268 192 font label)
     (draw-simple-text canvas
       "Keeping a borrowed wrapper reachable never extends its owner or callback scope." 28 229
       font label)))
 #:background 'white)

(render-reference-image
 "concept-color-interpretation.png" 480 220
 (lambda (canvas)
   (with-skia ([bytes (make-paint #:color "#AEB7C2")]
               [srgb (make-paint #:color (rgba 128 128 128 255))]
               [linear-result (make-paint #:color (rgba 188 188 188 255))]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [arrow-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (draw-simple-text canvas "same bytes: interpretation then destination conversion" 28 19 title
       label)
     (draw-rect canvas 28 50 100 46 bytes)
     (draw-rect canvas 28 50 100 46 border)
     (draw-simple-text canvas "bytes (128,128,128)" 30 118 font label)
     (draw-arrow canvas 137 73 202 73 arrow-ink)
     (draw-arrow canvas 137 73 202 153 arrow-ink)
     (draw-simple-text canvas "declared sRGB" 145 61 font label)
     (draw-simple-text canvas "linear sRGB" 145 143 font label)
     (draw-rect canvas 220 47 95 55 srgb)
     (draw-rect canvas 220 47 95 55 border)
     (draw-rect canvas 220 127 95 55 linear-result)
     (draw-rect canvas 220 127 95 55 border)
     (draw-simple-text canvas "draw into sRGB: 128" 326 78 font label)
     (draw-simple-text canvas "draw into sRGB: approx. 188" 326 158 font label)
     (draw-simple-text canvas
       "A tag declares sample meaning; drawing converts into the destination." 28 208 font label)))
 #:background 'white)

(render-reference-image
 "concept-gpu-boundaries.png" 480 245
 (lambda (canvas)
   (with-skia ([pending (make-paint #:color "#DCEAF8")]
               [submit (make-paint #:color "#326DE6")]
               [cpu (make-paint #:color "#2C9B6F")]
               [route (make-paint #:color "#EFA02B")]
               [border (make-paint #:color "#526070" #:style 'stroke #:stroke-width 1)]
               [arrow-ink (make-paint #:color "#8255C7" #:style 'stroke #:stroke-width 1)]
               [font (make-font #:size 11)]
               [title (make-font #:size 13)]
               [label (make-paint #:color "#20344E")])
     (define (box x y w h paint text)
       (draw-rect canvas x y w h paint)
       (draw-rect canvas x y w h border)
       (draw-simple-text canvas text (+ x 8) (+ y 24) font label))
     (draw-simple-text canvas "GPU boundaries are separate responsibilities" 20 19 title label)
     (box 20 52 92 38 pending "pending draw")
     (box 150 52 80 38 pending "flush")
     (box 268 52 95 38 submit "submit")
     (box 400 52 60 38 cpu "CPU wait")
     (draw-arrow canvas 112 71 142 71 arrow-ink)
     (draw-arrow canvas 230 71 260 71 arrow-ink)
     (draw-arrow canvas 363 71 392 71 arrow-ink)
     (draw-simple-text canvas "gpu-submit! submits work already flushed" 150 110 font label)
     (draw-simple-text canvas
       "gpu-wait! includes flush plus submission and requests CPU completion" 20 135 font label)
     (box 95 162 125 38 route "readback -> CPU image")
     (box 290 162 125 38 route "presentation request")
     (draw-arrow canvas 316 92 170 155 arrow-ink)
     (draw-arrow canvas 316 92 352 155 arrow-ink)
     (draw-simple-text canvas "wait alone neither reads back nor presents" 20 220 title label)))
 #:background 'white)
