#lang racket/base
(require racket/cmdline racket/file racket/path "../main.rkt")
(provide render-svg-probes)

(define ink "#20344E")
(define muted "#50657C")
(define blue "#3168CF")
(define teal "#12988C")
(define orange "#F0A02B")

;; Outlined labels make these parts independent of the SVG viewer's fonts.
(define (label c text x y [size 14] [color muted])
  (with-skia ([f (make-font #:size size)]
              [p (make-paint #:color color)]
              [path (simple-text-path f text x y)])
    (draw-path c path p)))

(define (heading c width height title subtitle index)
  (with-skia ([white (make-paint #:color 'white)] [accent (make-paint #:color teal)])
    (draw-rect c 0 0 width height white)
    (draw-rect c 30 22 38 4 accent))
  (label c title 30 58 26 ink)
  (label c subtitle 30 82 13)
  (label c "RACKET / SKIA   |   SVG OUTPUT PROBE" 30 (- height 20) 11)
  (label c (number->string index) (- width 40) (- height 20) 11 ink))

(define (draw-vectors c)
  (heading c 720 520 "A canvas, now in SVG"
           "Paths, a linear gradient, clipping and independent transforms. All labels are outlines." 1)
  (label c "01  Native vector geometry" 30 112)
  (with-skia ([fill (make-paint #:color blue)]
              [stroke (make-paint #:color ink #:style 'stroke #:stroke-width 3)]
              [curve (make-path '((move 260 180) (cubic 355 80 540 240 675 120)))])
    (draw-circle c 78 160 33 fill)
    (paint-set-color! fill teal)
    (draw-rounded-rect c 135 126 70 68 12 12 fill)
    (draw-path c curve stroke))
  (label c "02  Linear gradient remains a paint server" 30 225)
  (with-skia ([shader (make-linear-gradient-shader 30 0 690 0 (list blue teal orange)
                                                   #:positions '(0 1/2 1))]
              [p (make-paint #:shader shader)])
    (draw-rounded-rect c 30 240 660 66 15 15 p))
  (label c "03  Intersecting clip and rotated drawing" 30 342)
  (with-skia ([clip (make-path '((move 40 370) (line 325 353) (line 300 462) (line 65 450) (close)))]
              [p (make-paint #:color teal)]
              [border (make-paint #:color ink #:style 'stroke #:stroke-width 2)])
    (with-canvas-state c
      (canvas-clip-path! c clip)
      (draw-rect c 30 350 310 125 p)
      (paint-set-color! p blue)
      (for ([x (in-range 20 360 26)])
        (draw-rect c x 348 12 130 p)))
    (draw-path c clip border)
    (with-canvas-state c
      (canvas-translate! c 545 410)
      (canvas-rotate! c 24)
      (paint-set-color! p orange)
      (draw-rounded-rect c -52 -42 104 84 10 10 p)
      (draw-line c -40 0 40 0 border)
      (draw-line c 0 -30 0 30 border))))

(define (draw-sun c)
  (with-skia ([rays (make-paint #:color blue #:style 'stroke #:stroke-width 7 #:cap 'round)]
              [center (make-paint #:color orange)])
    (for ([i (in-range 8)])
      (with-canvas-state c
        (canvas-translate! c 40 40)
        (canvas-rotate! c (* i 45))
        (draw-line c 0 -21 0 -34 rays)))
    (draw-circle c 40 40 14 center)))

(define (draw-text-images c)
  (heading c 800 540 "Text, images and recorded drawing"
           "Native text is editable; outlined shaped text preserves glyph geometry, not text semantics." 2)
  (label c "01  Native SVG text (viewer needs the font)" 30 123)
  (with-skia ([f (make-font #:size 29)] [p (make-paint #:color ink)])
    (draw-simple-text c "Simple text: geometry 123" 30 165 f p))
  (label c "02  HarfBuzz shaping, explicitly outlined" 30 205)
  (with-skia ([f (make-font #:size 29)] [sh (make-shaper f)]
              [p (make-paint #:color ink)])
    (define run (shape-text sh "office affinity AV" #:language "en"))
    (with-skia ([path (shaped-run->path sh run)])
      (with-canvas-state c
        (canvas-translate! c 30 245)
        (draw-path c path p))))
  (label c "03  Existing paragraph API" 30 291)
  (with-skia ([f (make-font #:size 18)] [sh (make-shaper f)]
              [p (make-paint #:color ink)])
    (define layout
      (layout-text sh "The paragraph API draws to an SVG canvas using the existing layout and drawing operations."
                   #:width 365))
    (draw-text-layout c layout 30 310 p))
  (label c "04  Embedded RGBA image" 455 123)
  (with-skia ([s (make-surface 120 90)]
              [shader (make-linear-gradient-shader 0 0 120 90 (list blue teal))]
              [p (make-paint #:shader shader)] [dot (make-paint #:color orange)])
    (draw-rounded-rect (surface-canvas s) 4 4 112 82 14 14 p)
    (draw-circle (surface-canvas s) 60 45 22 dot)
    (with-skia ([im (surface-snapshot s)])
      (draw-image-rect c im 485 142 210 157.5)))
  (label c "05  Record once, replay as vectors" 455 335)
  (with-skia ([pic (call-with-picture 80 80 draw-sun)])
    (draw-picture c pic #:x 460 #:y 391 #:width 44 #:height 44)
    (draw-picture c pic #:x 535 #:y 377 #:width 72 #:height 72)
    (draw-picture c pic #:x 646 #:y 356 #:width 114 #:height 114)))

(define (draw-effects c)
  (heading c 720 480 "Explicit rasterized groups"
           "The two effect panels become embedded PNGs; labels and the dashed path remain vectors." 3)
  (label c "01  Shadow and blur, rendered at 2x" 30 118)
  (draw-rasterized
   c 30 130 305 220
   (lambda (rc)
     (with-skia ([shadow (make-drop-shadow-image-filter 8 8 4 4 (rgba 0 0 0 100))]
                 [blur (make-blur-image-filter 4 4)]
                 [a (make-paint #:color blue #:image-filter shadow)]
                 [b (make-paint #:color teal #:image-filter blur)])
       (draw-rounded-rect rc 16 18 155 95 16 16 a)
       (draw-circle rc 225 150 35 b)))
   #:scale 2)
  (label c "02  Radial shader, explicitly rasterized" 375 118)
  (draw-rasterized
   c 375 130 305 220
   (lambda (rc)
     (with-skia ([shader (make-radial-gradient-shader 150 105 90 (list orange teal blue))]
                 [p (make-paint #:shader shader)])
       (draw-circle rc 150 105 90 p)))
   #:scale 2)
  (label c "03  Dashed path is still vector geometry" 30 382)
  (with-skia ([dash (make-dash-path-effect '(10 6))]
              [p (make-paint #:color ink #:style 'stroke #:stroke-width 3 #:path-effect dash)])
    (draw-line c 40 410 675 410 p)))

(define (html-escape s)
  (regexp-replace* #rx"[&<>\"]" s
                   (lambda (v)
                     (cond [(string=? v "&") "&amp;"] [(string=? v "<") "&lt;"]
                           [(string=? v ">") "&gt;"] [else "&quot;"]))))

(define (render-svg-probes prefix)
  (define full (path->string (path->complete-path prefix)))
  (define entries '())
  (for ([spec (in-list (list (list "vectors" 720 520 draw-vectors)
                             (list "text-images" 800 540 draw-text-images)
                             (list "effects" 720 480 draw-effects)))])
    (define suffix (car spec))
    (define w (cadr spec))
    (define h (caddr spec))
    (define draw (cadddr spec))
    (define svg (string-append full "." suffix ".svg"))
    (define png (string-append full "." suffix ".reference.png"))
    (call-with-svg-file svg w h draw #:exists 'replace
                        #:title (string-append "Skia SVG probe: " suffix)
                        #:description "Compare the SVG rendered in a viewer with the separately drawn raster reference."
                        #:id-prefix (string-append "probe-" suffix))
    (with-skia ([s (make-surface w h #:background 'white)])
      (draw (surface-canvas s))
      (save-png s png #:exists 'replace))
    (set! entries (cons (list suffix svg png) entries))
    (printf "Wrote ~a\nWrote ~a (raster reference, not an SVG rendering)\n" svg png))
  (define html (string-append full ".review.html"))
  (call-with-output-file html
    (lambda (out)
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Skia SVG review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}h1{font-size:24px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}figcaption{margin-bottom:8px}@media(max-width:800px){.pair{grid-template-columns:1fr}}</style><h1>SVG output review</h1><p>Left: actual SVG, rendered by this browser. Right: separately drawn raster reference. Open the SVG files directly to inspect and zoom. The references are not SVG rasterizations.</p>" out)
      (for ([entry (in-list (reverse entries))])
        (define svg-name (html-escape (path->string (file-name-from-path (cadr entry)))))
        (define png-name (html-escape (path->string (file-name-from-path (caddr entry)))))
        (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a\" alt=\"SVG probe\"></figure><figure><figcaption>Raster reference</figcaption><img src=\"~a\" alt=\"Raster reference\"></figure></section>" (car entry) svg-name png-name))
      (display "</html>" out))
    #:exists 'replace)
  (printf "Wrote ~a\n" html))

(module+ main
  (define prefix
    (command-line #:program "svg-documents.rkt"
                  #:args ([output-prefix "svg-documents"]) output-prefix))
  (render-svg-probes prefix))
