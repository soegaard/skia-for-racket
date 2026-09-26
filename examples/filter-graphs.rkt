#lang racket/base
(require racket/cmdline racket/file racket/path racket/string racket/list "../main.rkt")
;; One registry; PDF receives native filter graphs. SVG receives explicit bounded
;; raster groups. Reference PNGs are independent native Skia raster drawings.
(define current-probe-backend (make-parameter 'raster))
(define ink "#20344e")
(define blue "#3269d5")
(define teal "#10988e")
(define orange "#efa02b")
(define PW 208)
(define PH 128)
(define crop '(48 16 96 96))
(define (label c text x y size [color ink])
  (with-skia ([f (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [p (make-paint #:color color)])
    (draw-simple-text c text x y f p)))
(define (stamp c)
  (with-skia ([p (make-paint #:color blue)] [q (make-paint #:color orange)]
              [stroke (make-paint #:color teal #:style 'stroke #:stroke-width 5)])
    (draw-rounded-rect c 30 24 105 62 13 13 p)
    (draw-circle c 139 83 23 q)
    (draw-line c 42 39 112 71 stroke)
    (draw-line c 67 30 86 82 stroke)))
(define (source-filter color bounds)
  (with-skia ([sh (make-color-shader color)]) (make-shader-image-filter sh #:crop bounds)))
(define (paint-filter c f)
  (with-skia ([p (make-paint #:image-filter f)]) (draw-paint c p)))
(define (render-case c key)
  (with-skia ([pic (call-with-picture PW PH stamp)] [src (make-picture-image-filter pic)])
    (case key
      [(merge)
       (with-skia ([shadow (make-drop-shadow-only-image-filter 8 6 4 4 (rgba 0 0 0 130) #:input src)]
                   [f (make-merge-image-filter (list shadow src))]) (paint-filter c f))]
      [(blend arithmetic)
       (with-skia ([b (source-filter blue '(26 18 102 74))]
                   [a (source-filter orange '(84 44 102 72))]
                   [f (if (eq? key 'blend) (make-blend-image-filter 'multiply b a)
                          (make-arithmetic-image-filter 0 1/2 1/2 0 b a))]) (paint-filter c f))]
      [(crop-after)
       (with-skia ([f (make-blur-image-filter 5 5 #:input src #:crop crop)]) (paint-filter c f))]
      [(crop-before)
       (with-skia ([cut (make-crop-image-filter crop #:input src)]
                   [f (make-blur-image-filter 5 5 #:input cut)]) (paint-filter c f))]
      [(compose)
       (with-skia ([outer (make-offset-image-filter 18 -8)]
                   [inner (make-blur-image-filter 2 2 #:input src)]
                   [f (make-compose-image-filter outer inner #:crop '(10 8 190 112))]) (paint-filter c f))]
      [(dilate erode)
       (with-skia ([f ((if (eq? key 'dilate) make-dilate-image-filter make-erode-image-filter)
                       4 3 #:input src)]) (paint-filter c f))]
      [(convolution)
       (with-skia ([f (make-matrix-convolution-image-filter 3 3 '(-1 -1 -1 -1 8 -1 -1 -1 -1)
                       #:bias 64 #:convolve-alpha? #f #:input src)]) (paint-filter c f))]
      [(displacement)
       (with-skia ([sh (make-linear-gradient-shader 0 0 PW 0 (list (rgb 0 128 0) (rgb 255 128 0)))]
                   [map-filter (make-shader-image-filter sh #:crop '(0 0 208 128))]
                   [f (make-displacement-map-image-filter 'red 'green 40 map-filter src)])
         (paint-filter c f))]
      [(matrix)
       (with-skia ([f (make-matrix-transform-image-filter
                      (matrix-compose (matrix-translate 35 -3) (matrix-rotate-degrees 18)
                                      (matrix-scale 0.8)) #:input src)]) (paint-filter c f))]
      [(magnifier)
       (with-skia ([f (make-magnifier-image-filter '(24 12 160 104) 1.9 #:inset 10 #:input src)])
         (paint-filter c f))]
      [(image)
       (with-skia ([s (make-surface 104 64)] [p (make-paint #:color teal)] [q (make-paint #:color orange)])
         (draw-rounded-rect (surface-canvas s) 2 2 100 60 8 8 p)
         (for ([x '(24 52 80)]) (draw-circle (surface-canvas s) x 32 10 q))
         (with-skia ([im (surface-snapshot s)]
                     [f (make-image-source-filter im #:destination '(12 10 184 108))])
           (paint-filter c f)))]
      [(picture) (paint-filter c src)]
      [(shader)
       (with-skia ([sh (make-radial-gradient-shader 104 64 76 (list orange teal blue))]
                   [f (make-shader-image-filter sh #:crop '(20 16 168 96))]) (paint-filter c f))]
      [(tile)
       (with-skia ([small (source-filter blue '(0 0 12 12))]
                   [f (make-tile-image-filter '(0 0 20 20) '(12 12 184 104) #:input small)])
         (paint-filter c f))]
      [(diffuse specular)
       (with-skia ([bump (make-blur-image-filter 2 2 #:input src)]
                   [f (if (eq? key 'diffuse)
                          (make-distant-lit-diffuse-image-filter '(1 -1 1) (rgb 90 200 190)
                           #:surface-scale 12 #:input bump #:crop '(8 8 192 112))
                          (make-spot-lit-specular-image-filter '(30 -30 80) '(100 64 0) 'white
                           #:surface-scale 16 #:coefficient 3 #:shininess 8
                           #:input bump #:crop '(8 8 192 112)))])
         (paint-filter c f))])))
(define (panel c x y title note key)
  (label c title x y 11)
  (define top (+ y 12))
  ;; Background and border stay vector. The group's filter inputs do not include
  ;; this checkerboard: all examples composite their output with source-over.
  (with-skia ([a (make-paint #:color "#f2f4f7")] [b (make-paint #:color "#e4e9ef")])
    (draw-rect c x top PW PH a)
    (for* ([row (in-range 8)] [col (in-range 13)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ top (* row 16)) 16 16 b)))
  (define (draw pc) (render-case pc key))
  (if (eq? (current-probe-backend) 'svg)
      (draw-rasterized c x top PW PH draw)
      (with-canvas-state c
        (canvas-translate! c x top)
        (canvas-clip-rect! c 0 0 PW PH)
        (draw c)))
  (with-skia ([p (make-paint #:color "#bdcad7" #:style 'stroke #:stroke-width 0.5)])
    (draw-rect c x top PW PH p))
  (label c note x (+ top PH 17) 8.4))
(define (make-probe title subtitle cases)
  (make-output-page
   720 560
   (lambda (c)
     (with-skia ([p (make-paint #:color teal)]) (draw-rect c 0 0 34 2 p))
     (label c title 0 31 23)
     (label c subtitle 0 54 10)
     (for ([spec (in-list cases)] [i (in-naturals)])
       (panel c (* (remainder i 3) 232) (+ 90 (* (quotient i 3) 180))
              (car spec) (cadr spec) (caddr spec)))
     (label c "PDF: native filter graphs. SVG: six explicit 416 x 256 PNG groups; labels and grid stay vector." 0 461 9)
     (label c "RACKET / SKIA   |   ADVANCED FILTER GRAPHS" 0 502 9))
   #:margins 24 #:background 'white))
(define registry
  (list
   (cons "graphs"
     (make-probe "Composition and crop placement"
       "Independent inputs, ordered composition, and an explicit distinction between crop-before and crop-after."
       '(("01  Merge: shadow + source" "Input order is back to front." merge)
         ("02  Multiply blend" "Background first; foreground second." blend)
         ("03  Arithmetic average" "0.5 foreground + 0.5 background." arithmetic)
         ("04  Crop after blur" "Blur result ends at the crop boundary." crop-after)
         ("05  Crop before blur" "The cropped input can blur outward." crop-before)
         ("06  Compose: offset after blur" "outer(inner(source)), then output crop." compose))))
   (cons "kernels"
     (make-probe "Kernels and coordinate transforms"
       "The same picture is the source of all six filters. Matrix transforms affect pixels, not the original path."
       '(("01  Dilate" "Expands channels, including alpha." dilate)
         ("02  Erode" "Shrinks channels, including alpha." erode)
         ("03  Edge convolution" "3 x 3 kernel; bias 64; alpha copied." convolution)
         ("04  Displacement map" "Red controls x; green is near-neutral." displacement)
         ("05  Affine image transform" "Scale, rotation, and translation." matrix)
         ("06  Magnifier" "1.9x lens with a 10-unit inset." magnifier))))
   (cons "sources"
     (make-probe "Explicit sources and alpha lighting"
       "Image, picture, and shader nodes replace the dynamic source. Lighting interprets the input alpha as height."
       '(("01  Image source" "A retained image, mapped to a rectangle." image)
         ("02  Picture source" "A retained recorded drawing." picture)
         ("03  Shader source" "Radial shader cropped to a rectangle." shader)
         ("04  Tiled subset" "Repeat a 20 x 20 source region." tile)
         ("05  Distant diffuse lighting" "Soft alpha supplies the height field." diffuse)
         ("06  Spot specular lighting" "Position, target, and shininess." specular))))))
(define (escaped s)
  (for/fold ([s s]) ([pair (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")))])
    (string-replace s (car pair) (cdr pair))))
(define (base-name s) (escaped (path->string (file-name-from-path s))))
(module+ main
  (define prefix (command-line #:program "filter-graphs.rkt" #:args ([prefix "filter-graphs-0.25"]) prefix))
  (define (name suffix) (string-append prefix suffix))
  (make-parent-directory* (name ".pdf"))
  (parameterize ([current-probe-backend 'pdf])
    (save-output (map cdr registry) (name ".pdf") 'pdf #:exists 'replace
                 #:title "Advanced filter graphs" #:raster-dpi 144))
  (for ([entry (in-list registry)])
    (define stem (string-append "." (car entry)))
    (parameterize ([current-probe-backend 'svg])
      (save-output (cdr entry) (name (string-append stem ".svg")) 'svg #:exists 'replace
                   #:title (string-append "Filter graphs: " (car entry))
                   #:id-prefix (car entry) #:raster-dpi 144))
    (parameterize ([current-probe-backend 'raster])
      (with-skia ([im (output-page->image (cdr entry) #:dpi 144)])
        (save-image im (name (string-append stem ".reference.png")) 'png #:exists 'replace))))
  (call-with-output-file (name ".review.html")
    (lambda (out)
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Filter graph review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}figure{margin:0}img{width:100%;background:white}figcaption{margin-bottom:8px}@media(max-width:800px){.pair{grid-template-columns:1fr}}</style><h1>Advanced filter graphs</h1>" out)
      (fprintf out "<p><a href=\"~a\">Actual three-page PDF</a> uses native filter graphs. Left: actual SVG with explicit raster groups. Right: independent native raster reference. PNGs are not vector-file rasterizations.</p>" (base-name (name ".pdf")))
      (for ([entry (in-list registry)])
        (define stem (string-append "." (car entry)))
        (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG (six bounded raster groups)</figcaption><img src=\"~a\" alt=\"SVG\"></figure><figure><figcaption>Separate native raster reference</figcaption><img src=\"~a\" alt=\"Reference\"></figure></section>"
          (car entry) (base-name (name (string-append stem ".svg")))
          (base-name (name (string-append stem ".reference.png")))))
      (display "</html>" out)) #:exists 'replace)
  (printf "Wrote ~a.pdf; 3 SVGs; 3 independent raster references; ~a.review.html\n" prefix prefix))
