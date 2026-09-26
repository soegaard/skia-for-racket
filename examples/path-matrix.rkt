#lang racket/base
(require racket/cmdline racket/file racket/path racket/string racket/list "../main.rkt")

;; All three pages are authored once. PNGs are raster REFERENCES, not renderings
;; of the PDF or SVG. Review actual vector files in their viewers as well.
(define ink "#20344e")
(define blue "#3269d5")
(define teal "#10988e")
(define orange "#efa02b")
(define gray "#9aabbc")
(define (label c text x y size [color ink])
  (with-skia ([f (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [p (make-paint #:color color)])
    (draw-simple-text c text x y f p)))
(define (line c x1 y1 x2 y2 width [color ink])
  (with-skia ([p (make-paint #:color color #:style 'stroke #:stroke-width width)])
    (draw-line c x1 y1 x2 y2 p)))
(define (heading c title subtitle)
  (line c 0 0 34 0 3 teal)
  (label c title 0 31 23)
  (label c subtitle 0 53 10.5)
  (label c "RACKET / SKIA   |   PATH INSPECTION AND AFFINE MATRICES" 0 435 9))
(define specimen
  '((move 20 110) (line 70 35) (quad 105 0 140 55)
    (conic 185 120 220 35 0.5) (cubic 255 -10 285 145 320 80) (close)
    (move 385 105) (line 440 30) (quad 490 0 565 105)))

(define inspect-page
  (make-output-page
   720 500
   (lambda (c)
     (heading c "A path can describe its own structure"
              "Blue: original geometry. Teal: rebuilt from raw commands. Orange: stored control points.")
     (with-skia ([src (make-path specimen)]
                 [copy (make-path (path->commands src) #:fill-rule (path-fill-rule src))]
                 [wide (make-paint #:color blue #:style 'stroke #:stroke-width 6)]
                 [thin (make-paint #:color teal #:style 'stroke #:stroke-width 2)]
                 [dots (make-paint #:color orange)])
       (define raw (path-segments src #:mode 'raw))
       (define normal (path-segments src))
       (with-canvas-state c
         (canvas-translate! c 12 123)
         (for ([segment (in-list raw)])
           (define pts (path-segment-points segment))
           (when (>= (length pts) 2)
             (for ([a (in-list pts)] [b (in-list (cdr pts))])
               (line c (car a) (cadr a) (car b) (cadr b) 0.7 gray)))
           (for ([pt (in-list pts)]) (draw-circle c (car pt) (cadr pt) 3 dots)))
         (draw-path c src wide)
         (draw-path c copy thin))
       (label c "01  Closed contour: line / quadratic / rational conic / cubic" 0 89 11)
       (label c "02  Open contour" 395 109 11)
       (label c (format "Raw: ~a verbs    Normal: ~a verbs    Generated closing lines: ~a"
                         (length raw) (length normal)
                         (count path-segment-closing-line? normal)) 0 323 12)
       (label c "Raw commands contain close, but no synthetic closing line." 0 349 11)
       (label c "Normal iteration exposes the line that connects the contour back to its start." 0 372 11)
       (label c "Snapshot lists and sequences remain usable after the source is mutated or closed." 0 399 10.5)))
   #:margins 28 #:background 'white))

(define frame-page
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Local frames along a measured curve"
              "Each arrow is the same small path, placed by path-measure-matrix and canvas-concat!.")
     (with-skia ([curve (make-path '((move 30 270) (cubic 150 0 420 350 620 125)))]
                 [measure (make-path-measure curve)]
                 [arrow (make-path '((move 0 -4) (line 14 -4) (line 14 -9)
                                    (line 27 0) (line 14 9) (line 14 4) (line 0 4) (close)))]
                 [curve-paint (make-paint #:color ink #:style 'stroke #:stroke-width 2)]
                 [arrow-paint (make-paint #:color teal)]
                 [dot (make-paint #:color orange)])
       (draw-path c curve curve-paint)
       (define length (path-measure-length measure))
       (for ([i (in-range 9)])
         (define m (path-measure-matrix measure (* length (/ i 8))))
         (when m
           (with-canvas-state c
             (canvas-concat! c m)
             (draw-path c arrow arrow-paint)
             (draw-circle c 0 0 2.5 dot))))
       (label c "The orange point is the sampled curve position. The arrow's x axis is the tangent." 0 343 11)
       (label c "Composition is current * local: page margins and physical-unit transforms stay in place." 0 367 11)
       (label c "Modes: position only, tangent only, or position+tangent. Empty contours return #f." 0 391 11)))
   #:margins 28 #:background 'white))

(define shader-page
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Transforms, without changing the source"
              "Left pair: canvas transform versus transformed path. Bottom: local shader coordinates.")
     (define m (matrix-compose (matrix-translate 110 143) (matrix-rotate-degrees 25)
                               (matrix-scale 1.4 0.9)))
     (with-skia ([shape (make-path '((move -35 -25) (line 35 -25) (line 35 25) (line -35 25) (close)))]
                 [transformed (path-transform shape m)]
                 [fill (make-paint #:color orange)]
                 [stroke (make-paint #:color ink #:style 'stroke #:stroke-width 2)])
       (label c "canvas-concat!" 58 85 12)
       (label c "path-transform" 288 85 12)
       (with-canvas-state c
         (canvas-concat! c m)
         (draw-path c shape fill))
       (with-canvas-state c
         (canvas-translate! c 230 0)
         (draw-path c transformed fill))
       (label c "Both use the same matrix." 442 135 11)
       (label c "The original path is unchanged." 442 158 11))
     (label c "Identity shader matrix" 14 228 11)
     (label c "Translated shader" 219 228 11)
     (label c "Rotated shader" 424 228 11)
     ;; m119 SVG does not reliably serialize shader-local matrices. Only this
     ;; group is explicitly rasterized; the path comparison and labels stay vector.
     (draw-rasterized
      c 14 245 610 106
      (lambda (rc)
        (with-skia ([base (make-linear-gradient-shader 0 0 180 0 (list blue teal orange))])
          (for ([x (in-list '(0 205 410))]
                [local (in-list (list matrix-identity (matrix-translate 50 0)
                                     (matrix-compose (matrix-translate 90 50)
                                                     (matrix-rotate-degrees 35)
                                                     (matrix-translate -90 -50))))])
            (with-skia ([shader (shader-with-local-matrix base local)]
                        [paint (make-paint #:shader shader)])
              (with-canvas-state rc
                (canvas-translate! rc x 0)
                (draw-rounded-rect rc 0 0 180 100 12 12 paint))))))
      #:scale 2)
     (label c "All three shaded rectangles keep their geometry; only sampling coordinates change." 0 382 11)
     (label c "This shader panel is one embedded 1220 x 212 PNG in SVG (explicit fallback)." 0 407 10.5))
   #:margins 28 #:background 'white))

(define registry (list (cons "inspection" inspect-page) (cons "frames" frame-page) (cons "shaders" shader-page)))
(define (escaped s)
  (string-replace (string-replace (string-replace (string-replace s "&" "&amp;") "<" "&lt;")
                                  ">" "&gt;") "\"" "&quot;"))
(define (base-name path) (escaped (path->string (file-name-from-path path))))
(module+ main
  (define prefix (command-line #:program "path-matrix.rkt" #:args ([prefix "path-matrix-0.24"]) prefix))
  (define (name suffix) (string-append prefix suffix))
  (make-parent-directory* (name ".pdf"))
  (save-output (map cdr registry) (name ".pdf") 'pdf #:exists 'replace
               #:title "Path inspection and affine matrices" #:raster-dpi 144)
  (for ([entry (in-list registry)])
    (define stem (string-append "." (car entry)))
    (save-output (cdr entry) (name (string-append stem ".svg")) 'svg #:exists 'replace
                 #:title (car entry) #:id-prefix (car entry) #:raster-dpi 144)
    (with-skia ([im (output-page->image (cdr entry) #:dpi 144)])
      (save-image im (name (string-append stem ".reference.png")) 'png #:exists 'replace)))
  (call-with-output-file (name ".review.html")
    (lambda (out)
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Path and matrix review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}figure{margin:0}img{width:100%;background:white}figcaption{margin-bottom:8px}@media(max-width:800px){.pair{grid-template-columns:1fr}}</style><h1>Path inspection and matrices</h1>" out)
      (fprintf out "<p><a href=\"~a\">Actual three-page PDF</a>. Left: actual SVG; right: independent raster reference. The PNGs are not vector-file rasterizations.</p>" (base-name (name ".pdf")))
      (for ([entry (in-list registry)])
        (define stem (string-append "." (car entry)))
        (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a\" alt=\"SVG\"></figure><figure><figcaption>Separate raster reference</figcaption><img src=\"~a\" alt=\"Reference\"></figure></section>"
                 (car entry) (base-name (name (string-append stem ".svg")))
                 (base-name (name (string-append stem ".reference.png")))))
      (display "</html>" out)) #:exists 'replace)
  (printf "Wrote ~a.pdf, 3 SVGs, 3 independent raster references, and ~a.review.html\n" prefix prefix))
