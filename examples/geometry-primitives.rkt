#lang racket/base

;;;
;;; Geometry Primitives Example
;;;

;; Builds pages comparing regions, image lattices, sprite atlases, and meshes.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require racket/file racket/path racket/list json "../main.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; blue : rgba?
;;   Specifies the blue color used by this drawing.
(define blue (rgb 48 103 211))
; teal : rgba?
;;   Specifies the teal color used by this drawing.
(define teal (rgb 14 149 142))
; orange : rgba?
;;   Specifies the orange color used by this drawing.
(define orange (rgb 239 161 37))
; ink : rgba?
;;   Specifies the ink color used by this drawing.
(define ink (rgb 32 52 78))
; trace : box?
;;   Collects rendering observations for the example's generated report.
(define trace (box '()))
; label : canvas? string? real? real? [real?] -> void?
;;   Draws a text label at the supplied baseline in local canvas coordinates.
(define (label c text x y [size 11])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [paint (make-paint #:color ink)])
    (draw-simple-text c text x y font paint)))
; heading : canvas? string? string? -> void?
;;   Draws the page heading and its explanatory subtitle.
(define (heading c title subtitle)
  (with-skia ([paint (make-paint #:color teal)]) (draw-rect c 0 0 34 2 paint))
  (label c title 0 32 23) (label c subtitle 0 56 10))
; footer : canvas? exact-nonnegative-integer? any/c -> void?
;;   Adds the page identification beneath the example drawing.
(define (footer c n note)
  (label c note 0 418 9.5)
  (label c "RACKET / SKIA   |   STRUCTURED GEOMETRY AND ADVANCED IMAGE DRAWING" 0 444 9)
  (label c (number->string n) 652 444 9))
; at : canvas? real? real? procedure? -> any/c
;;   Runs a drawing callback at a translated origin and restores canvas state afterward.
(define (at c x y f)
  (with-canvas-state c (canvas-translate! c x y) (f c)))
; checker : canvas? real? real? -> void?
;;   Draws a checkerboard that makes transparent pixels visible.
(define (checker c x y)
  (with-skia ([a (make-paint #:color (rgb 240 243 247))] [b (make-paint #:color (rgb 224 230 238))])
    (draw-rect c x y 300 112 a)
    (for* ([row (in-range 7)] [col (in-range 19)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ y (* row 16)) (min 16 (- 300 (* col 16))) 16 b))))
; panel : canvas? real? real? procedure? #:raster? [boolean?] #:svg-raster? [boolean?] -> any/c
;;   Runs the panel drawing directly or through the explicitly selected raster fallback.
(define (panel c x y f #:raster? [raster? #f] #:svg-raster? [svg-raster? #f])
  (checker c x y)
  (if (or raster? (and svg-raster? (eq? (canvas-annotation-backend c) 'svg)))
      (draw-rasterized c x y 300 112 f #:scale 2)
      (at c x y f)))
; region-boolean : canvas? -> void?
;;   Draws the region boolean comparison in the current canvas coordinate system.
(define (region-boolean c)
  (with-skia ([outer (make-region '((12 10 125 90) (150 35 135 60)))]
              [cut (make-region '((30 30 82 50) (190 20 32 90)))]
              [r (region-difference outer cut)] [paint (make-paint #:color blue)])
    (draw-region c r paint)))
; region-scan : canvas? -> void?
;;   Draws the region scan comparison in the current canvas coordinate system.
(define (region-scan c)
  (with-skia ([circle (make-path)] [clip (make-region '((0 0 28 28)))]
              [paint (make-paint #:color teal)]
              [outline (make-paint #:color orange #:style 'stroke #:stroke-width 0.3)])
    (path-add-circle! circle 14 14 12)
    (with-skia ([r (path->region circle clip)])
      (set-box! trace (cons (hasheq 'backend (symbol->string (canvas-annotation-backend c))
                                     'region_bounds (vector->list (region-bounds r))
                                     'rectangles (map vector->list (region-rectangles r))) (unbox
                                       trace)))
      (with-canvas-state c
        (canvas-translate! c 90 4) (canvas-scale! c 3.7 3.7)
        (draw-region c r paint) (draw-path c circle outline)))))
; region-snapshot : canvas? -> void?
;;   Draws the region snapshot comparison in the current canvas coordinate system.
(define (region-snapshot c)
  (define snapshot
    (with-skia ([r (make-region '((12 12 120 24) (40 24 105 40) (12 70 250 24)))])
      (region-rectangles r)))
  ;; The native source has already been closed here.
  (for ([r (in-list snapshot)] [i (in-naturals)])
    (with-skia ([p (make-paint #:color (list-ref (list blue teal orange) (modulo i 3)))])
      (apply draw-rect c (append (vector->list r) (list p))))))
; region-local-clip : canvas? -> void?
;;   Draws the region local clip comparison in the current canvas coordinate system.
(define (region-local-clip c)
  (with-skia ([r (make-region '((0 0 42 12) (0 12 70 12) (0 24 95 12)))] [p (region->path r)]
              [paint (make-paint #:color blue)])
    (with-canvas-state c
      (canvas-translate! c 10 4) (canvas-scale! c 2.8 2.8)
      (canvas-clip-path! c p)
      (draw-color c teal)
      (for ([x (in-range 0 110 12)]) (draw-rect c x 0 5 40 paint)))))
; regions-page : canvas? -> void?
;;   Draws the regions page comparison in the current canvas coordinate system.
(define (regions-page c)
  (heading c "Integer regions are geometry, not soft masks"
    "Boolean operations, scan conversion, detached rectangle snapshots, and local path clipping.")
  (label c "01  Region difference, with holes" 0 86)
  (label c "02  A curve scan-converted to integer cells" 352 86)
  (with-output-label "region-difference" (panel c 0 99 region-boolean))
  (with-output-label "scan-conversion" (panel c 352 99 region-scan))
  (label c "Half-open rectangles; neither input is mutated." 0 227 10)
  (label c "Orange: original curve. Teal: integer region." 352 227 10)
  (label c "03  Rectangle values after closing the region" 0 253)
  (label c "04  Region boundary used as a local path clip" 352 253)
  (with-output-label "region-snapshot" (panel c 0 267 region-snapshot))
  (with-output-label "boundary-clip" (panel c 352 267 region-local-clip))
  (label c "Each colored rectangle is a detached snapshot." 0 396 10)
  (label c "Use a path clip when transforms should apply." 352 396 10)
  (footer c 1
    "These region drawings stay vector. Direct canvas-clip-region! instead uses native device coordinates."))
; border-image : -> image?
;;   Builds the bordered source image used to make nine-patch stretching visible.
(define (border-image)
  (with-skia ([s (make-surface 64 40)] [p (make-paint #:color blue)] [q (make-paint #:color teal)]
              [r (make-paint #:color orange)])
    (draw-rounded-rect (surface-canvas s) 0 0 64 40 8 8 p)
    (draw-rect (surface-canvas s) 8 8 48 24 q)
    (draw-rect (surface-canvas s) 0 16 8 8 r)
    (surface-snapshot s)))
; tiles : -> image?
;;   Builds a source image with distinguishable tiles for image-grid comparisons.
(define (tiles)
  (with-skia ([s (make-surface 64 32)] [p (make-paint #:color blue)] [q (make-paint #:color teal)]
              [r (make-paint #:color orange)])
    (draw-rounded-rect (surface-canvas s) 0 0 32 32 6 6 p)
    (draw-circle (surface-canvas s) 16 16 8 r)
    (draw-rounded-rect (surface-canvas s) 32 0 32 32 6 6 q)
    (draw-rect (surface-canvas s) 42 9 12 14 r)
    (surface-snapshot s)))
; nine : canvas? -> void?
;;   Draws the nine comparison in the current canvas coordinate system.
(define (nine c)
  (with-skia ([im (border-image)]) (draw-image-nine c im '(8 8 48 24) 8 12 284 88)))
; small-nine : canvas? -> void?
;;   Draws the small nine comparison in the current canvas coordinate system.
(define (small-nine c)
  (with-skia ([im (border-image)])
    (for ([width '(12 24 60 140)] [x '(16 44 90 156)])
      (draw-image-nine c im '(8 8 48 24) x 28 width (min 56 (+ width 4))))))
; lattice : canvas? -> void?
;;   Defines the image-grid layout reused by the portable drawing pages.
(define (lattice c)
  (with-skia ([im (border-image)])
    (define grid
      (make-image-lattice '(8 56) '(8 32)
        #:cell-types '(default default fixed-color default transparent default fixed-color default
          default)
        #:colors (list 'white 'white orange 'white 'white 'white teal 'white 'white)))
    (draw-image-lattice c im grid 8 12 284 88 #:sampling 'nearest)))
; sprites : canvas? -> void?
;;   Builds the portable atlas drawing for the supplied source image.
(define (sprites c)
  (with-skia ([im (tiles)])
    (define transforms
      (for/list ([x '(25 80 140 205 265)] [rot '(-15 20 -30 35 0)] [scale '(1 1.4 1.7 1.3 1.4)])
        (make-atlas-transform x 56 #:rotation rot #:scale scale #:anchor '(16 16))))
    (draw-atlas c im transforms '((0 0 32 32) (32 0 32 32) (0 0 32 32) (32 0 32 32) (0 0 32 32))
                #:colors (list 'white 'white 'white 'white (rgba 255 255 255 140)))))
; images-page : canvas? -> void?
;;   Draws the images page comparison in the current canvas coordinate system.
(define (images-page c)
  (heading c "One image, several structured ways to draw it"
    "Fixed borders, alternating lattice cells, and transformed sprites from a single atlas.")
  (label c "01  Nine-patch preserves corner sizes" 0 86)
  (label c "02  Small destinations shrink fixed strips" 352 86)
  (with-output-label "nine-patch" (panel c 0 99 nine #:svg-raster? #t))
  (with-output-label "small-nine" (panel c 352 99 small-nine #:svg-raster? #t))
  (label c "Only the center and edge spans stretch." 0 227 10)
  (label c "No negative or inverted destination slices." 352 227 10)
  (label c "03  Default, transparent, and fixed-color cells" 0 253)
  (label c "04  Atlas sprites rotate about a local anchor" 352 253)
  (with-output-label "lattice-cells" (panel c 0 267 lattice #:svg-raster? #t))
  (with-output-label "atlas" (panel c 352 267 sprites #:raster? #t))
  (label c "Grid cell types use native one-byte entries." 0 396 10)
  (label c "Per-sprite alpha; positions are independent." 352 396 10)
  (footer c 2
    "PDF submits image grids natively. SVG uses four explicit 600 x 224 PNG panels; atlas fallback is explicit in both."))
; mesh-colors : canvas? -> void?
;;   Draws the mesh colors comparison in the current canvas coordinate system.
(define (mesh-colors c)
  (with-skia ([v (make-vertices 'triangles '((10 10) (286 10) (150 106)) #:colors (list blue teal
    orange))]
              [p (make-paint #:color 'white)])
    (draw-vertices c v p)))
; mesh-texture : canvas? -> void?
;;   Draws the mesh texture comparison in the current canvas coordinate system.
(define (mesh-texture c)
  (with-skia ([im (tiles)] [s (make-image-shader im #:tile-x 'repeat #:tile-y 'repeat #:sampling
    'linear)]
              [p (make-paint #:shader s)]
              [v (make-vertices 'triangles '((18 16) (284 5) (264 104) (36 96))
                   #:texture-coordinates '((0 0) (128 0) (128 64) (0 64)) #:indices '(0 1 2 0 2 3))])
    (draw-vertices c v p)))
; patch-points : list?
;;   Orders the twelve cubic boundary control points expected by the patch drawing API.
(define patch-points '((18 22) (95 0) (195 0) (280 22) (295 45) (288 85)
                       (258 99) (180 80) (100 112) (22 96) (5 80) (3 40)))
; patch-colors : canvas? -> void?
;;   Draws the patch colors comparison in the current canvas coordinate system.
(define (patch-colors c)
  (with-skia ([p (make-paint #:color 'white)])
    (draw-patch c (make-cubic-patch patch-points #:colors (list blue teal orange 'white)) p)))
; patch-texture : canvas? -> void?
;;   Draws the patch texture comparison in the current canvas coordinate system.
(define (patch-texture c)
  (with-skia ([im (tiles)] [s (make-image-shader im #:tile-x 'repeat #:tile-y 'repeat #:sampling
    'linear)]
              [p (make-paint #:shader s)])
    (draw-patch c (make-cubic-patch patch-points #:texture-coordinates '((0 0) (128 0) (128 64) (0
      64))) p)))
; meshes-page : canvas? -> void?
;;   Draws the meshes page comparison in the current canvas coordinate system.
(define (meshes-page c)
  (heading c "Meshes interpolate; patches are not just outlines"
    "Copied vertex buffers, uint16 indices, shader coordinates, and a Coons patch bounded by four cubics.")
  (label c "01  Per-vertex colors" 0 86)
  (label c "02  Two indexed, textured triangles" 352 86)
  (with-output-label "colored-triangle" (panel c 0 99 mesh-colors #:raster? #t))
  (with-output-label "textured-mesh" (panel c 352 99 mesh-texture #:raster? #t))
  (label c "The paint is white; vertex colors interpolate." 0 227 10)
  (label c "Texture coordinates are in shader space." 352 227 10)
  (label c "03  Four colored corners on a cubic patch" 0 253)
  (label c "04  The same patch with a repeated image" 352 253)
  (with-output-label "colored-patch" (panel c 0 267 patch-colors #:raster? #t))
  (with-output-label "textured-patch" (panel c 352 267 patch-texture #:raster? #t))
  (label c "Twelve points; four shared-corner cubics." 0 396 10)
  (label c "No promise of path-style antialiasing." 352 396 10)
  (footer c 3
    "Both PDF and SVG use four explicit 600 x 224 PNG panels. Labels and checkerboards remain vector."))
; write-json-file : path-string? any/c -> void?
;;   Writes the report data as JSON, replacing an existing report file.
(define (write-json-file f value)
  (call-with-output-file f (lambda (o) (write-json value o) (newline o)) #:exists 'replace))
;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; args : vector?
  ;;   Retains the command-line argument vector used to select output paths.
  (define args (current-command-line-arguments))
  (when (> (vector-length args) 1) (error 'geometry-primitives "expected optional output prefix"))
  ; prefix : path-string?
  ;;   Selects the destination used by this example's output.
  (define prefix (if (zero? (vector-length args)) "output/geometry-primitives-0.31" (vector-ref args
    0)))
  ; file : any/c -> string?
  ;;   Appends an output suffix to the selected filename prefix.
  (define (file suffix) (string-append prefix suffix))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))
  ; registry : list?
  ;;   Keeps the shared scene/page order used by the exported documents and raster references.
  (define registry (list (cons "regions" regions-page) (cons "images" images-page) (cons "meshes"
    meshes-page)))
  ; pages : list?
  ;;   Collects output-page descriptions in document order.
  (define pages (map (lambda (entry) (make-output-page 720 500 (cdr entry) #:margins 24 #:background
    'white)) registry))
  ; report : output-audit-report?
  ;;   Retains the export audit report for the generated metadata file.
  (define report (save-output/audit pages (file ".pdf") 'pdf #:policy 'error #:exists 'replace
    #:title "Structured geometry and image drawing"))
  (write-json-file (file ".pdf.audit.json") (output-audit-report->jsexpr report))
  (for ([entry (in-list registry)] [p (in-list pages)])
    (define stem (string-append "." (car entry)))
    (define r (save-output/audit p (file (string-append stem ".svg")) 'svg #:policy 'error #:exists
      'replace #:id-prefix (car entry)))
    (write-json-file (file (string-append stem ".audit.json")) (output-audit-report->jsexpr r))
    (with-skia ([im (output-page->image p #:dpi 144)])
      (save-image im (file (string-append stem ".reference.png")) 'png #:exists 'replace)))
  (write-json-file (file ".regions.json") (reverse (unbox trace)))
  ; base : string?
  ;;   Escapes the output prefix for links in the generated HTML report.
  (define base (path->string (file-name-from-path prefix)))
  (call-with-output-file (file ".review.html")
    (lambda (o)
      (display
        "<!doctype html><meta charset=\"utf-8\"><title>Structured geometry review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style><h1>Structured geometry and advanced image drawing</h1>" o)
      (fprintf o
        "<p><a href=\"~a.pdf\">Actual PDF</a> | <a href=\"~a.pdf.audit.json\">PDF audit</a> | <a href=\"~a.regions.json\">Region snapshots</a></p>" base base base)
      (display
        "<p>Left: actual SVG. Right: independent raster drawing, not a PDF/SVG rasterization. Inspect cell holes, corner thickness, and texture mapping.</p>" o)
      (for ([entry (in-list registry)])
        (define name (car entry))
        (fprintf o
          "<h2>~a</h2><p><a href=\"~a.~a.audit.json\">Audit report</a></p><div class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a.~a.svg\"></figure><figure><figcaption>Independent raster reference</figcaption><img src=\"~a.~a.reference.png\"></figure></div>" name base name base name base name)))
    #:exists 'replace)
  (printf "Wrote ~a.pdf; 3 SVGs/references; 4 audit reports; region snapshots; review HTML\n" prefix))
