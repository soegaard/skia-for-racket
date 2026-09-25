#lang racket/base
(require racket/cmdline racket/path "../main.rkt")

;; The SAME three drawing procedures target PDF pages and raster surfaces.
;; The PNG files are raster references, NOT renderings of the generated PDF.
(define (page-heading c w h title subtitle page)
  (with-skia ([white (make-paint #:color 'white)]
              [ink (make-paint #:color "#192B43")]
              [muted (make-paint #:color "#526276")]
              [accent (make-paint #:color "#197E85")]
              [large (make-font #:size 27)]
              [small (make-font #:size 12)])
    (draw-rect c 0 0 w h white)
    (draw-rect c 32 24 38 4 accent)
    (draw-simple-text c title 32 66 large ink)
    (draw-simple-text c subtitle 32 89 small muted)
    (draw-simple-text c "RACKET / SKIA    |    PDF OUTPUT PROBE" 32 (- h 22) small muted)
    (draw-simple-text c (number->string page) (- w 45) (- h 22) small ink)))

(define (label c text x y)
  (with-skia ([font (make-font #:size 13)] [paint (make-paint #:color "#526276")])
    (draw-simple-text c text x y font paint)))

(define (vectors-page c)
  (page-heading c 612 792 "A canvas, now on paper" "Paths, gradients, clipping, transforms and ordinary text." 1)
  (with-skia ([blue (make-paint #:color "#3168CE")]
              [teal (make-paint #:color "#13988D")]
              [orange (make-paint #:color "#EB9A35")]
              [line (make-paint #:color "#192B43" #:style 'stroke #:stroke-width 3)]
              [curve (make-path '((move 265 240) (cubic 330 115 470 295 548 145)))]
              [gradient (make-linear-gradient-shader 40 320 570 320 '("#3168CE" "#13988D" "#EB9A35"))]
              [gp (make-paint #:shader gradient)]
              [clip (make-path '((move 60 485) (line 330 455) (line 290 650) (line 85 635) (close)))])
    (label c "01   Primitive shapes and a cubic Bezier curve" 32 128)
    (draw-circle c 86 197 42 blue)
    (draw-rounded-rect c 148 156 82 82 14 14 teal)
    (draw-path c curve line)
    (draw-circle c 265 240 4 orange)
    (draw-circle c 548 145 4 orange)
    (label c "02   A native gradient fill" 32 296)
    (draw-rounded-rect c 40 320 530 88 18 18 gp)
    (label c "03   Clipping and independent transform scopes" 32 449)
    (with-canvas-state c
      (canvas-clip-path! c clip)
      (draw-rect c 40 455 300 200 teal)
      (canvas-rotate! c -18)
      (for ([i (in-range 20)])
        (draw-rect c (+ -160 (* 30 i)) 400 14 380 blue)))
    (draw-path c clip line)
    (with-canvas-state c
      (canvas-translate! c 445 558)
      (canvas-rotate! c 24)
      (draw-rounded-rect c -58 -58 116 116 12 12 orange)
      (draw-line c -48 0 48 0 line)
      (draw-line c 0 -48 0 48 line))
    (label c "The page canvas has the same top-left origin and y-down coordinates." 32 718)))

(define (demo-image)
  (with-skia ([s (make-surface 128 128)]
              [gradient (make-linear-gradient-shader
                         0 0 128 128 (list (rgba 49 104 206 230) (rgba 19 152 141 120)))]
              [p (make-paint #:shader gradient)]
              [dot (make-paint #:color "#EB9A35")])
    (draw-rounded-rect (surface-canvas s) 8 8 112 112 20 20 p)
    (draw-circle (surface-canvas s) 64 64 25 dot)
    (surface-snapshot s)))

(define (demo-picture)
  (call-with-picture
   100 100
   (lambda (c)
     (with-skia ([a (make-paint #:color "#3168CE")]
                 [b (make-paint #:color "#EB9A35")])
       (for ([i (in-range 8)])
         (with-canvas-state c
           (canvas-translate! c 50 50)
           (canvas-rotate! c (* 45 i))
           (draw-rounded-rect c 18 -5 24 10 5 5 a)))
       (draw-circle c 50 50 14 b)))))

(define (content-page c)
  (page-heading c 792 612 "Text, images and recorded drawing" "A landscape page with a different media box." 2)
  (with-skia ([f (make-font #:size 27)]
              [body-font (make-font #:size 16)]
              [sh (make-shaper f)]
              [body-sh (make-shaper body-font)]
              [ink (make-paint #:color "#192B43")]
              [im (demo-image)]
              [pic (demo-picture)])
    (label c "01   Simple text" 32 133)
    (draw-simple-text c "office affinity AV" 32 172 f ink)
    (label c "02   HarfBuzz-shaped text" 32 209)
    (void (draw-shaped-text c sh "office affinity AV" 32 248 ink #:language "en"))
    (label c "03   Paragraph layout" 32 288)
    (define layout
      (layout-text body-sh
                   "The paragraph API draws to this PDF page without changing its layout or shaping interface."
                   #:width 320))
    (draw-text-layout c layout 32 310 ink)
    (label c "04   Embedded RGBA image" 415 133)
    (draw-image-rect c im 440 150 190 165 #:sampling 'linear)
    (label c "05   Record once, replay at three sizes" 415 352)
    (draw-picture c pic #:x 420 #:y 402 #:width 65 #:height 65)
    (draw-picture c pic #:x 500 #:y 385 #:width 100 #:height 100)
    (draw-picture c pic #:x 611 #:y 369 #:width 132 #:height 132)
    (label c "Font embedding and text extraction are checked separately from appearance." 32 552)))

(define (effects-page c)
  (page-heading c 480 480 "Effects and fallback" "The backend decides which operations need rasterization." 3)
  (with-skia ([shadow (make-drop-shadow-image-filter 8 10 5 5 (rgba 25 43 67 100))]
              [sp (make-paint #:color "#3168CE" #:image-filter shadow)]
              [blur (make-blur-image-filter 5 5)]
              [bp (make-paint #:color "#13988D" #:image-filter blur)]
              [dash (make-dash-path-effect '(10 6))]
              [line (make-paint #:color "#192B43" #:style 'stroke #:stroke-width 3 #:path-effect dash)])
    (label c "Image-filter shadow" 32 137)
    (draw-rounded-rect c 40 160 160 105 16 16 sp)
    (label c "Image-filter blur" 258 137)
    (draw-circle c 341 212 49 bp)
    (label c "Dashed vector path" 32 316)
    (draw-line c 40 344 437 344 line)
    (label c "Not every Skia effect has an exact native PDF equivalent." 32 395)
    (label c "Compare this page with the separate raster reference." 32 416)))

(define page-specs
  (list (list 612 792 vectors-page)
        (list 792 612 content-page)
        (list 480 480 effects-page)))

(define (render-probe filename)
  (call-with-pdf-file
   filename
   (lambda (d)
     (for ([spec (in-list page-specs)])
       (call-with-document-page d (car spec) (cadr spec) (caddr spec))))
   #:exists 'replace #:title "Racket Skia PDF output probe"
   #:author "skia-for-racket" #:raster-dpi 144 #:encoding-quality 101)
  (printf "Wrote ~a (3 PDF pages)\n" filename)
  (for ([spec (in-list page-specs)] [i (in-naturals 1)])
    (define reference
      (path-replace-extension filename (string->bytes/utf-8 (format ".page-~a.png" i))))
    (with-skia ([s (make-surface (car spec) (cadr spec))])
      ((caddr spec) (surface-canvas s))
      (save-png s reference #:exists 'replace))
    (printf "Wrote raster reference ~a\n" reference)))

(module+ main
  (define output
    (command-line #:program "pdf-documents.rkt"
                  #:args ([output "pdf-documents.pdf"]) output))
  (render-probe output))
