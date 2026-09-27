#lang racket/base
(require racket/file racket/path racket/list racket/string json
         "../main.rkt" "../tests/color-filter-fixtures.rkt")
(define ink (rgb 32 52 78))
(define teal (rgb 14 149 142))
(define current-decisions (make-parameter #f))
(define page-names '("matrices" "curves" "composition"))
(define titles '("Color filters transform channels, not geometry"
                 "Transfer curves and lookup tables are different tools"
                 "Luma, contrast, and composed color operations"))
(define subtitles '("HSL operations and RGB lighting use the ordinary color-filter resource API."
                     "Gamma changes samples; tables index unpremultiplied byte channels. Neither retags an image."
                     "Filters stay retained resources. Output groups choose the bounded representation."))
(define names-by-page '((control hue desaturate lighting)
                        (encode decode rgb-table threshold)
                        (luma contrast lerp compose)))
(define labels-by-page
  '(("01  Unfiltered control: native vectors" "02  Hue + one third of a turn"
     "03  HSL saturation set to zero" "04  RGB multiply, then add")
    ("01  Linear-to-sRGB gamma" "02  sRGB-to-linear gamma"
     "03  RGB inversion tables; alpha unchanged" "04  RGB threshold tables")
    ("01  Luma multiplied into alpha" "02  Grayscale, lightness inversion, contrast"
     "03  Parallel results interpolated at 0.35" "04  Gamma conversion and its inverse")))
(define notes-by-page
  '(("The first panel stays vector. The other three are bounded raster groups in PDF and SVG."
     "H, S, L, A and matrix offsets use normalized values. Hue is not measured in degrees.")
    ("A shared table affects alpha too. These RGB-only examples deliberately leave alpha unchanged."
     "At stored gray 128: gamma encoding is about 188; decoding is about 55. Alpha is unchanged.")
    ("Luma produces black with varying alpha, not gray RGB. Composition is outer(inner(source))."
     "The native parents retain their inputs. All four effect panels are explicitly bounded by the author.")))
(define (label c text x y [size 10])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [paint (make-paint #:color ink)])
    (draw-simple-text c text x y font paint)))
(define (checker c x y)
  (with-skia ([a (make-paint #:color (rgb 242 245 248) #:antialias? #f)]
              [b (make-paint #:color (rgb 225 232 240) #:antialias? #f)])
    (draw-rect c x y 300 96 a)
    (for* ([row (in-range 6)] [col (in-range 19)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ y (* row 16)) (min 16 (- 300 (* col 16))) 16 b))))
(define palette (list (rgb 255 0 0) (rgb 0 255 0) (rgb 0 0 255)
                      (rgb 239 161 37) teal (rgb 128 128 128)))
(define (swatches c filter)
  (for ([color (in-list palette)] [i (in-naturals)])
    (with-skia ([p (make-paint #:color color #:color-filter filter #:antialias? #f)])
      (draw-rect c (* i 50) 0 50 36 p)))
  ;; One continuous gradient avoids independently antialiased touching SVG
  ;; rectangles in the native control panel.
  (with-skia ([ramp (make-linear-gradient-shader 0 44 300 44 '(black white))]
              [p (make-paint #:shader ramp #:color-filter filter)])
    (draw-rect c 0 44 300 24 p))
  (for ([color (in-list palette)] [i (in-naturals)])
    (define v (color->rgba color))
    (with-skia ([p (make-paint #:color (rgba (rgba-red v) (rgba-green v) (rgba-blue v) 128)
                               #:color-filter filter)])
      (draw-circle c (+ 25 (* i 50)) 84 9 p))))
(define (panel c page name x y document?)
  (define (draw cf)
    (define (content local) (swatches local cf))
    (cond
      [document?
       (define result (draw-output-group c x y 300 96 content #:scale 2 #:label (symbol->string name)))
       (when (current-decisions)
         (set-box! (current-decisions)
                   (cons (cons page (output-group-report->jsexpr result)) (unbox (current-decisions)))))]
      [else
       ;; Independent raster reference: same primitives directly on the raster
       ;; canvas, not replay of any PDF/SVG and not an output-group fallback.
       (with-canvas-state c (canvas-translate! c x y) (content c))]))
  (if (eq? name 'control) (draw #f)
      (with-skia ([cf (make-probe-color-filter name)]) (draw cf))))
(define (draw-page c index document?)
  (define page (list-ref page-names index))
  (with-skia ([p (make-paint #:color teal)]) (draw-rect c 0 0 34 2 p))
  (label c (list-ref titles index) 0 32 21)
  (label c (list-ref subtitles index) 0 55 9.5)
  (for ([name (in-list (list-ref names-by-page index))]
        [text (in-list (list-ref labels-by-page index))]
        [xy '((0 110) (352 110) (0 274) (352 274))])
    (define x (car xy)) (define y (cadr xy))
    (label c text x (- y 15) 10)
    (checker c x y)
    (panel c page name x y document?)
    (label c "Opaque palette / gray ramp / half-alpha swatches" x (+ y 14 96) 8.5))
  (label c (car (list-ref notes-by-page index)) 0 406 9)
  (label c (cadr (list-ref notes-by-page index)) 0 424 9)
  (label c "RACKET / SKIA   |   CPU COLOR FILTERS" 0 444 9)
  (label c (number->string (add1 index)) 652 444 9))
(define (write-json-file path data)
  (call-with-output-file path (lambda (out) (write-json data out) (newline out)) #:exists 'replace))
(define (html-escape s)
  (for/fold ([t s]) ([p '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;"))])
    (string-replace t (car p) (cdr p))))
(define (decision-rows rows)
  (for/list ([page (in-list page-names)])
    (hasheq 'page page 'groups (for/list ([row (in-list rows)] #:when (equal? (car row) page)) (cdr row)))))
(define (samples)
  (define (probe make color)
    (with-skia ([cf (make)]) (rgba-list (filter-pixel cf color))))
  (hasheq 'input_gray 128
          'encode (probe make-linear-to-srgb-gamma-color-filter (rgb 128 128 128))
          'decode (probe make-srgb-to-linear-gamma-color-filter (rgb 128 128 128))
          'hue_red (probe (lambda () (make-probe-color-filter 'hue)) 'red)
          'desaturated_red (probe (lambda () (make-probe-color-filter 'desaturate)) 'red)
          'luma_white_alpha128 (probe make-luma-color-filter (rgba 255 255 255 128))
          'rgb_invert (probe (lambda () (make-probe-color-filter 'rgb-table)) (rgb 32 64 96))
          'all_channel_invert_white (probe (lambda () (make-table-color-filter inverse-table)) 'white)
          'roundtrip (probe (lambda () (make-probe-color-filter 'compose)) filter-swatch-color)))
(module+ main
  (define args (current-command-line-arguments))
  (when (> (vector-length args) 1) (error 'color-filters "expected optional output prefix"))
  (define prefix (if (zero? (vector-length args)) "output/color-filters-0.36" (vector-ref args 0)))
  (define (file suffix) (string-append prefix suffix))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))
  (define pages
    (for/list ([i (in-range 3)])
      (make-output-page 720 500 (lambda (c) (draw-page c i #t)) #:margins 24 #:background 'white)))
  (define pdf-decisions (box '())) (define svg-decisions (box '()))
  (define pdf-report
    (parameterize ([current-decisions pdf-decisions])
      (save-output/audit pages (file ".pdf") 'pdf #:policy 'error #:exists 'replace #:title "CPU color filters")))
  (write-json-file (file ".pdf.audit.json") (output-audit-report->jsexpr pdf-report))
  (for ([name (in-list page-names)] [page (in-list pages)] [i (in-naturals)])
    (define report
      (parameterize ([current-decisions svg-decisions])
        (save-output/audit page (file (string-append "." name ".svg")) 'svg #:policy 'error
                           #:id-prefix name #:exists 'replace)))
    (write-json-file (file (string-append "." name ".audit.json")) (output-audit-report->jsexpr report))
    (define raster-page
      (make-output-page 720 500 (lambda (c) (draw-page c i #f)) #:margins 24 #:background 'white))
    (with-skia ([im (output-page->image raster-page #:dpi 144)])
      (save-image im (file (string-append "." name ".reference.png")) 'png #:exists 'replace)))
  (write-json-file (file ".decisions.json")
    (hasheq 'pdf (decision-rows (reverse (unbox pdf-decisions)))
            'svg (decision-rows (reverse (unbox svg-decisions)))))
  (write-json-file (file ".samples.json") (samples))
  (define base (html-escape (path->string (file-name-from-path prefix))))
  (call-with-output-file (file ".review.html")
    (lambda (out)
      (display "<!doctype html><meta charset=\"utf-8\"><title>CPU color filters review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style><h1>CPU color filters</h1>" out)
      (fprintf out "<p><a href=\"~a.pdf\">Actual PDF</a> | <a href=\"~a.decisions.json\">Group decisions</a> | <a href=\"~a.samples.json\">Native sample values</a> | <a href=\"~a.inspection.json\">Structural inspection</a></p>" base base base base)
      (display "<p>Left: actual SVG. Right: independent raster reference, not a PDF/SVG rasterization. Reference filters draw directly on a raster canvas, without output-group fallback.</p>" out)
      (for ([name (in-list page-names)])
        (fprintf out "<h2>~a</h2><div class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a.~a.svg\"></figure><figure><figcaption>Independent raster reference</figcaption><img src=\"~a.~a.reference.png\"></figure></div>" name base name base name)))
    #:exists 'replace)
  (printf "Wrote ~a.pdf; 3 SVGs/references; 4 audits; decisions, native samples, and review HTML\n" prefix))
