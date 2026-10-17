#lang racket/base

;;;
;;; Projective Matrices Example
;;;

;; Compares affine and projective transforms, clipping, and saved canvas state.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require racket/file racket/path racket/list racket/string json "../main.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; blue : rgba?
;   Specifies the blue color used by this drawing.
(define blue (rgb 48 103 211))

; teal : rgba?
;   Specifies the teal color used by this drawing.
(define teal (rgb 14 149 142))

; orange : rgba?
;   Specifies the orange color used by this drawing.
(define orange (rgb 239 161 37))

; ink : rgba?
;   Specifies the ink color used by this drawing.
(define ink (rgb 32 52 78))

; target : parameter?
;   Selects target for the dynamically scoped rendering operation.
(define target (make-parameter 'raster))

; trace : box?
;   Collects rendering observations for the example's generated report.
(define trace (box '()))

; label : canvas? string? real? real? [real?] -> void?
;   Draws a text label at the supplied baseline in local canvas coordinates.
(define (label c text x y [size 11])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [paint (make-paint #:color ink)])
    (draw-simple-text c text x y font paint)))

; heading : canvas? string? string? -> void?
;   Draws the page heading and its explanatory subtitle.
(define (heading c title subtitle)
  (with-skia ([p (make-paint #:color teal)]) (draw-rect c 0 0 34 2 p))
  (label c title 0 32 23) (label c subtitle 0 56 10))

; footer : canvas? exact-nonnegative-integer? -> void?
;   Adds the page identification beneath the example drawing.
(define (footer c n)
  (label c "RACKET / SKIA   |   PERSPECTIVE AND GENERAL CANVAS MATRICES" 0 444 9)
  (label c (number->string n) 652 444 9))

; at : canvas? real? real? procedure? -> any/c
;   Runs a drawing callback at a translated origin and restores canvas state afterward.
(define (at c x y f) (with-canvas-state c (canvas-translate! c x y) (f c)))

; checker : canvas? real? real? -> void?
;   Draws a checkerboard that makes transparent pixels visible.
(define (checker c x y)
  (with-skia ([a (make-paint #:color (rgb 240 243 247))]
              [b (make-paint #:color (rgb 224 230 238))])
    (draw-rect c x y 300 180 a)
    (for* ([row (in-range 12)] [col (in-range 19)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ y (* row 16))
                 (min 16 (- 300 (* col 16))) (min 16 (- 180 (* row 16))) b))))

; panel : canvas? real? procedure? #:general? [boolean?] -> any/c
;   Uses bounded raster fallback for general projective transforms on vector backends.
(define (panel c x f #:general? [general? #t])
  (checker c x 110)
  (parameterize ([target (canvas-annotation-backend c)])
    ;; The independent reference draws directly on the raster page. Exporters
    ;; put the perspective INSIDE a destination-space bounded group instead.
    (if (and general? (memq (target) '(pdf svg)))
        (draw-rasterized c x 110 300 180 f #:scale 2)
        (at c x 110 f))))

; remember : canvas? any/c any/c any/c -> void?
;   Draws the remember comparison in the current canvas coordinate system.
(define (remember c local name before)
  (set-box! trace
    (cons (hasheq 'backend (symbol->string (target)) 'name name
                   'before (vector->list (matrix4->vector before))
                   'local (vector->list (matrix4->vector local))
                   'after (vector->list (matrix4->vector (canvas-matrix4 c))))
          (unbox trace))))

; under : canvas? any/c any/c procedure? -> any/c
;   Runs drawing under a scoped matrix while recording the matrix state for the report.
(define (under c m name draw)
  (define before (canvas-matrix4 c))
  (with-canvas-matrix c m
    (remember c (if (matrix3? m) (matrix3->matrix4 m) m) name before)
    (draw c)))

; grid : canvas? -> void?
;   Draws the grid comparison in the current canvas coordinate system.
(define (grid c)
  (with-skia ([sh (make-linear-gradient-shader 30 0 270 0 (list blue teal))]
              [p (make-paint #:shader sh)]
              [lines (make-paint #:color (rgba 255 255 255 180) #:style 'stroke #:stroke-width 1)]
              [dot (make-paint #:color orange)])
    (draw-rect c 30 20 240 140 p)
    (for ([x (in-range 30 271 40)]) (draw-line c x 20 x 160 lines))
    (for ([y (in-range 20 161 35)]) (draw-line c 30 y 270 y lines))
    (draw-circle c 150 90 17 dot)))

; affine : matrix4?
;   Combines centered rotation and scale as the affine comparison transform.
(define affine (matrix->matrix4 (matrix-compose (matrix-translate 150 90)
                                               (matrix-rotate-degrees -10) (matrix-scale 0.9)
                                               (matrix-translate -150 -90))))

; homography : matrix3?
;   Combines perspective with center translations as the projective comparison transform.
(define homography
  (matrix3-compose (matrix->matrix3 (matrix-translate 150 90))
                    (matrix3-perspective 0.0012 0.0006)
                    (matrix->matrix3 (matrix-translate -150 -90))))

; tilt : real? -> matrix4?
;   Builds the centered perspective transform for the supplied y-axis rotation.
(define (tilt degrees)
  (matrix4-compose (matrix4-translate 150 90) (matrix4-scale 0.9)
                    (matrix4-perspective 380) (matrix4-rotate-y-degrees degrees)
                    (matrix4-rotate-x-degrees 18) (matrix4-translate -150 -90)))

; homography-page : canvas? -> void?
;   Draws the homography page comparison in the current canvas coordinate system.
(define (homography-page c)
  (heading c "Perspective is a homogeneous divide"
             "Affine values remain available. A 3 x 3 matrix additionally carries the projective denominator W.")
  (label c "01  Affine grid: native vector geometry" 0 92)
  (label c "02  Homography: explicit raster group" 352 92)
  (with-output-label "affine-grid" (panel c 0 (lambda (r) (under r affine "affine" grid)) #:general?
    #f))
  (with-output-label "homography" (panel c 352 (lambda (r) (under r homography "homography" grid))))
  (label c "The same grid, before and after projective mapping." 0 320)
  (label c "(X, Y, W) = H (x, y, 1); the projected point is (X/W, Y/W)." 0 348)
  (label c
    "The affine panel and surrounding text stay vector. Only the right panel is a 600 x 360 PNG." 0
    380 10)
  (label c "Matrix coefficients are copied, immutable, and stored at native single precision." 0 407
    10)
  (footer c 1))

; image-card : canvas? -> void?
;   Draws the image card comparison in the current canvas coordinate system.
(define (image-card c)
  (with-skia ([s (make-surface 120 70)] [p (make-paint #:color blue)] [q (make-paint #:color orange)]
              [r (make-paint #:color teal)])
    (define sc (surface-canvas s))
    (draw-rect sc 0 0 120 70 p) (draw-rect sc 0 0 60 70 r)
    (draw-circle sc 60 35 21 q)
    (with-skia ([im (surface-snapshot s)]) (draw-image-rect c im 30 20 240 140 #:sampling 'linear))))

; depth-page : canvas? -> void?
;   Draws the depth page comparison in the current canvas coordinate system.
(define (depth-page c)
  (heading c "Keep depth until the final projection"
             "A 4 x 4 matrix retains Z contributions that can affect a later perspective transformation.")
  (label c "01  A textured card tilted left" 0 92)
  (label c "02  The same card tilted right" 352 92)
  (with-output-label "left-tilt" (panel c 0 (lambda (r) (under r (tilt -48) "left-tilt" image-card))))
  (with-output-label "right-tilt" (panel c 352 (lambda (r) (under r (tilt 48) "right-tilt"
    image-card))))
  (label c "Composition is current * local: the rightmost matrix acts first." 0 320)
  (label c
    "Projecting each operand to 3 x 3 before multiplying can discard depth needed by the result." 0
    348 10)
  (label c "Camera convention: W = 1 + Z/distance. Positive Z moves away from the viewer." 0 380 10)
  (label c
    "This transforms 2D drawing; it does not add a depth buffer, lighting, or hidden-surface removal." 0 407 10)
  (footer c 2))

; restored : canvas? -> void?
;   Draws the restored comparison in the current canvas coordinate system.
(define (restored c)
  (define local (matrix3->matrix4 homography))
  (define before (canvas-matrix4 c))
  (with-canvas-matrix c local
    (remember c local "restored" before)
    (define saved (canvas-matrix4 c))
    (with-handlers ([exn:fail? (lambda (_) (void))])
      (with-canvas-matrix c (matrix4-translate 900 900 50)
        (canvas-clip-rect! c 0 0 1 1) (error 'probe "intentional scope exit")))
    (unless (equal? saved (canvas-matrix4 c)) (error 'probe "matrix scope did not restore"))
    (grid c)))

; clipped : canvas? -> void?
;   Draws the clipped comparison in the current canvas coordinate system.
(define (clipped c)
  (with-canvas-state c
    ;; Clip before the projective matrix: its device-space footprint stays put.
    (canvas-clip-rect! c 65 35 170 110)
    (under c (tilt 40) "clipped" grid))
  (with-skia ([p (make-paint #:color orange #:style 'stroke #:stroke-width 1)])
    (draw-rect c 65 35 170 110 p)))

; scope-page : canvas? -> void?
;   Draws the scope page comparison in the current canvas coordinate system.
(define (scope-page c)
  (heading c "Matrix state is scoped; horizons are not finite"
             "Queries return detached values. Replacing a matrix leaves the existing device-space clip intact.")
  (label c "01  Exception restores the full matrix" 0 92)
  (label c "02  Clip first, transform afterward" 352 92)
  (with-output-label "restored-state" (panel c 0 restored))
  (with-output-label "fixed-clip" (panel c 352 clipped))
  (define horizon (matrix3-perspective 1 0))
  (label c (format "W = 1 + x: mapping x = -1 returns ~s." (matrix3-map-point horizon -1 2)) 0 320)
  (label c (format
    "Bounds crossing that horizon return ~s, not the box of four misleading corner images."
                   (matrix3-map-rect horizon -2 0 2 2)) 0 348 10)
  (label c "Finite mathematical projection is not a native visibility or paint-bounds test." 0 380 10)
  (label c
    "Put the matrix inside the raster callback. Rasterizing later does not repair outer perspective." 0 407 10)
  (footer c 3))

; write-json-file : path-string? any/c -> void?
;   Writes the report data as JSON, replacing an existing report file.
(define (write-json-file path data)
  (call-with-output-file path (lambda (o) (write-json data o) (newline o)) #:exists 'replace))

; html-escape : string? -> string?
;   Escapes text before inserting it into the generated HTML report.
(define (html-escape s)
  (for/fold ([text s]) ([p (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" .
    "&quot;")))])
    (string-replace text (car p) (cdr p))))
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; args : vector?
  ;   Retains the command-line argument vector used to select output paths.
  (define args (current-command-line-arguments))
  (when (> (vector-length args) 1) (error 'projective-matrices "expected optional output prefix"))

  ; prefix : path-string?
  ;   Selects the destination used by this example's output.
  (define prefix (if (zero? (vector-length args)) "output/projective-matrices-0.32" (vector-ref args
    0)))

  ; file : any/c -> string?
  ;   Appends an output suffix to the selected filename prefix.
  (define (file suffix) (string-append prefix suffix))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))

  ; registry : list?
  ;   Keeps the shared scene/page order used by the exported documents and raster references.
  (define registry (list (cons "homography" homography-page) (cons "depth" depth-page) (cons "scope"
    scope-page)))

  ; pages : list?
  ;   Collects output-page descriptions in document order.
  (define pages (map (lambda (p) (make-output-page 720 500 (cdr p) #:margins 24 #:background
    'white)) registry))

  ; report : output-audit-report?
  ;   Retains the export audit report for the generated metadata file.
  (define report (save-output/audit pages (file ".pdf") 'pdf #:policy 'error #:exists 'replace
                                    #:title "Perspective and general canvas matrices"))
  (write-json-file (file ".pdf.audit.json") (output-audit-report->jsexpr report))
  (for ([entry (in-list registry)] [page (in-list pages)])
    (define stem (string-append "." (car entry)))
    (define r (save-output/audit page (file (string-append stem ".svg")) 'svg #:policy 'error
                                #:exists 'replace #:id-prefix (car entry)))
    (write-json-file (file (string-append stem ".audit.json")) (output-audit-report->jsexpr r))
    (with-skia ([im (output-page->image page #:dpi 144)])
      (save-image im (file (string-append stem ".reference.png")) 'png #:exists 'replace)))
  (write-json-file (file ".matrices.json") (reverse (unbox trace)))

  ; unsafe : output-page?
  ;   Describes the unsafe drawing and its export dimensions.
  (define unsafe
    (make-output-page 30 30 (lambda (c) (canvas-concat-matrix3! c (matrix3-perspective 1/32 0))
                              (with-skia ([p (make-paint)]) (draw-rect c 0 0 20 20 p)))))
  (write-json-file (file ".unsafe.audit.json")
                   (for/list ([backend '(pdf svg)]) (output-audit-report->jsexpr
                     (analyze-output-page unsafe backend))))

  ; base : string?
  ;   Escapes the output prefix for links in the generated HTML report.
  (define base (html-escape (path->string (file-name-from-path prefix))))
  (call-with-output-file (file ".review.html")
    (lambda (o)
      (display
        "<!doctype html><meta charset=\"utf-8\"><title>General matrix review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style><h1>Perspective and general canvas matrices</h1>" o)
      (fprintf o
        "<p><a href=\"~a.pdf\">Actual PDF</a> | <a href=\"~a.matrices.json\">Matrix trace</a> | <a href=\"~a.unsafe.audit.json\">Unsafe preflight reports</a></p>" base base base)
      (display
        "<p>Left: actual SVG. Right: independent raster drawing, not a PDF/SVG rasterization. Inspect projected grids, opposite tilts, restored state, and the fixed clip.</p>" o)
      (for ([entry (in-list registry)])
        (define name (car entry))
        (fprintf o
          "<h2>~a</h2><div class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a.~a.svg\"></figure><figure><figcaption>Independent raster reference</figcaption><img src=\"~a.~a.reference.png\"></figure></div>" name base name base name)))
    #:exists 'replace)
  (printf
    "Wrote ~a.pdf; 3 SVGs/references; 4 export reports; matrix trace; unsafe preflight reports; review HTML\n" prefix))
