#lang racket/base
(require racket/cmdline racket/file racket/path racket/string "../main.rkt")

;; This is one registry of drawing callbacks, exported through both backends.
;; The reference PNGs are separate Skia raster renders, NOT SVG/PDF renderings.
(define ink "#20344e")
(define blue "#3269d5")
(define teal "#10988e")
(define orange "#efa02b")

(define (label c text x y size [color ink])
  (with-skia ([f (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)] [p (make-paint #:color color)])
    (draw-simple-text c text x y f p)))
(define (line c x1 y1 x2 y2 width [color ink])
  (with-skia ([p (make-paint #:color color #:style 'stroke #:stroke-width width)])
    (draw-line c x1 y1 x2 y2 p)))

(define units-page
  (make-output-page
   210 140
   (lambda (c)
     (line c 0 0 12 0 1 teal)
     (label c "One drawing, two vector formats" 0 11 6.4)
     (label c "This callback uses millimetres. PDF and SVG share the same nominal physical size." 0 19 3)
     (label c "01  A 100 mm ruler" 0 32 3.5)
     (line c 5 41 105 41 0.6)
     (for ([i (in-range 11)])
       (define x (+ 5 (* i 10)))
       (line c x 38 x 44 0.35)
       (label c (number->string (* i 10)) (- x 1) 49 2.5))
     (label c "100 mm = 283.4646... PDF points" 118 43 3)
     (label c "SVG root sizes carry pt units." 118 50 3)
     (label c "02  A vector gradient, with the same coordinates and clipping" 0 63 3.5)
     (with-skia ([sh (make-linear-gradient-shader 5 0 185 0 (list blue teal orange))]
                 [p (make-paint #:shader sh)])
       (draw-rounded-rect c 5 69 180 23 4 4 p))
     (label c "The page has 10 mm margins; content starts at the inner top-left corner." 0 104 3)
     (label c "Print at actual size to check the ruler. Browser zoom/CSS may resize the preview." 0 111 3)
     (label c "RACKET / SKIA   |   VECTOR OUTPUT REFINEMENT" 0 119 2.6))
   #:unit 'mm #:margins 10 #:background 'white))

(define text-page
  (make-output-page
   600 400
   (lambda (c)
     (line c 0 0 36 0 3 teal)
     (label c "Text policy, without rewriting the drawing" 0 29 23)
     (label c "Auto: native PDF text; SVG glyph outlines. Explicit modes remain available." 0 49 10.5)
     (label c "01  Simple text" 0 79 10)
     (label c "Same drawing API" 0 108 21)
     (with-skia ([f (make-font #:size 22)] [sh (make-shaper f)] [p (make-paint #:color ink)])
       (label c "02  HarfBuzz shaping" 0 140 10)
       (draw-shaped-text c sh "office affinity AV" 0 170 p)
       (label c "03  Paragraph layout" 0 204 10)
       (with-skia ([small (make-font #:size 15)] [ps (make-shaper small)])
         (draw-text-layout c
           (layout-text ps "The paragraph is authored once. The export mode changes text representation, not the layout API."
                        #:width 310)
           0 220 p)))
     (label c "04  A detached text-blob snapshot" 345 79 10)
     (with-skia ([f (make-font #:size 28)]
                 [blob (make-positioned-text-blob f (font-text->glyphs f "SVG") '((0 0) (27 0) (54 0)))]
                 [p (make-paint #:color teal)])
       ;; The private outline snapshot must not inherit this later mutation.
       (font-set-size! f 80)
       (skia-close! f)
       (draw-text-blob c blob 352 126 p))
     (label c "Original font resized and closed." 345 151 10)
     (label c "05  Record during page authoring" 345 196 10)
     (with-skia ([pic
                  (call-with-picture
                   170 65
                   (lambda (pc)
                     (with-skia ([p (make-paint #:color orange)])
                       (draw-rounded-rect pc 0 0 150 56 9 9 p))
                     (label pc "RECORDED" 15 36 20)))])
       (draw-picture c pic #:x 347 #:y 215))
     (label c "Already-recorded native text cannot be rewritten by a later export policy." 0 321 10)
     (label c "RACKET / SKIA   |   VECTOR OUTPUT REFINEMENT" 0 348 9))
   #:margins 24 #:background 'white))

(define effects-page
  (make-output-page
   180 125
   (lambda (c)
     (line c 0 0 12 0 1 teal)
     (label c "Raster density and padding are explicit" 0 11 5.7)
     (label c "The outer page stays vector; only these two bounded groups become images." 0 20 2.9)
     (label c "01  Shadow with 4 mm padding" 2 31 3.1)
     (label c "02  Asymmetric padding" 96 31 3.1)
     (with-skia ([cs (make-srgb-color-space)])
       (draw-rasterized
        c 6 38 60 42
        (lambda (rc)
          (with-skia ([shadow (make-drop-shadow-image-filter 2 2 2 2 (rgba 0 0 0 110))]
                      [p (make-paint #:color blue #:image-filter shadow)])
            (draw-rounded-rect rc 0 0 52 31 4 4 p)))
        #:padding 4 #:color-space cs)
       (draw-rasterized
        c 98 38 50 42
        (lambda (rc)
          (with-skia ([sh (make-radial-gradient-shader 25 21 20 (list orange teal blue))]
                      [p (make-paint #:shader sh)])
            (draw-circle rc 25 21 20 p)))
        #:padding '(2 5 6 3) #:color-space cs))
     (label c "The SVG embeds 386 x 284 and 329 x 284 pixel PNGs at the requested 144 DPI." 0 89 2.8)
     (with-skia ([dash (make-dash-path-effect '(3 2))]
                 [p (make-paint #:color ink #:style 'stroke #:stroke-width 0.6 #:path-effect dash)])
       (draw-line c 2 97 158 97 p))
     (label c "RACKET / SKIA   |   VECTOR OUTPUT REFINEMENT" 0 108 2.7))
   #:unit 'mm #:margins 8 #:background 'white))

(define registry (list (cons "units" units-page) (cons "text" text-page) (cons "effects" effects-page)))
(define (escaped text)
  (string-replace (string-replace (string-replace (string-replace text "&" "&amp;") "<" "&lt;")
                                  ">" "&gt;") "\"" "&quot;"))
(define (base-name path) (escaped (path->string (file-name-from-path path))))

(module+ main
  (define prefix
    (command-line #:program "vector-output.rkt"
                  #:args ([prefix "vector-output-0.23"]) prefix))
  (define (name suffix) (string-append prefix suffix))
  (make-parent-directory* (name ".pdf"))
  (save-output (map cdr registry) (name ".pdf") 'pdf #:exists 'replace
               #:title "Shared PDF/SVG output" #:description "Units, text policy, and explicit raster groups"
               #:raster-dpi 144)
  (for ([entry (in-list registry)])
    (define stem (string-append "." (car entry)))
    (define page (cdr entry))
    (save-output page (name (string-append stem ".svg")) 'svg #:exists 'replace
                 #:title (string-append "Vector output: " (car entry))
                 #:description "Same page callback as the multi-page PDF."
                 #:id-prefix (car entry) #:raster-dpi 144)
    (with-skia ([image (output-page->image page #:dpi 144)])
      (save-image image (name (string-append stem ".reference.png")) 'png #:exists 'replace)))
  (call-with-output-file (name ".review.html")
    (lambda (out)
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Vector output review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}figure{margin:0}img{width:100%;background:white}figcaption{margin-bottom:8px}@media(max-width:800px){.pair{grid-template-columns:1fr}}</style><h1>Shared PDF/SVG output</h1>" out)
      (fprintf out "<p><a href=\"~a\">Open the actual three-page PDF</a>. Left: actual SVG. Right: separate 144-DPI raster reference. The PNGs are not PDF/SVG rasterizations.</p>" (base-name (name ".pdf")))
      (for ([entry (in-list registry)])
        (define stem (string-append "." (car entry)))
        (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG (auto-outline policy)</figcaption><img src=\"~a\" alt=\"SVG output\"></figure><figure><figcaption>Separate raster reference</figcaption><img src=\"~a\" alt=\"Raster reference\"></figure></section>"
                 (car entry) (base-name (name (string-append stem ".svg")))
                 (base-name (name (string-append stem ".reference.png")))))
      (display "</html>" out))
    #:exists 'replace)
  (printf "Wrote ~a.pdf; 3 SVGs; 3 raster references; ~a.review.html\n" prefix prefix))
