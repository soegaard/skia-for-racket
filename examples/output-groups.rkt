#lang racket/base
(require racket/file racket/path racket/list racket/string json "../main.rkt")

(define blue (rgb 48 103 211))
(define teal (rgb 14 149 142))
(define orange (rgb 239 161 37))
(define ink (rgb 32 52 78))
(define wash (rgb 237 240 244))
(define pale (rgb 246 248 251))

(define (label c text x y [size 11])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [paint (make-paint #:color ink)])
    (draw-simple-text c text x y font paint)))

(define (heading c title subtitle)
  (with-skia ([p (make-paint #:color teal)])
    (draw-rect c 0 0 34 2 p))
  (label c title 0 32 23)
  (label c subtitle 0 56 10))

(define (footer c n)
  (label c "RACKET / SKIA   |   BACKEND-AWARE BOUNDED OUTPUT GROUPS" 0 444 9)
  (label c (number->string n) 652 444 9))

(define (at c x y draw)
  (with-canvas-state c
    (canvas-translate! c x y)
    (draw c)))

(define (panel-backdrop c x y w h)
  (with-skia ([bg (make-paint #:color wash)]
              [inner (make-paint #:color 'white)]
              [stroke (make-paint #:color (rgb 207 216 228) #:style 'stroke #:stroke-width 1)])
    (draw-rounded-rect c (- x 8) (- y 8) (+ w 16) (+ h 16) 13 13 bg)
    (draw-rounded-rect c x y w h 10 10 inner)
    (draw-rounded-rect c x y w h 10 10 stroke)))

(define (vector-card c)
  (with-skia ([gradient (make-linear-gradient-shader 0 0 300 0 (list blue teal))]
              [fill (make-paint #:shader gradient)]
              [accent (make-paint #:color orange)]
              [stroke (make-paint #:color 'white #:style 'stroke #:stroke-width 3)])
    (draw-rounded-rect c 0 0 300 170 16 16 fill)
    (draw-circle c 76 85 38 accent)
    (draw-line c 142 56 258 56 stroke)
    (draw-line c 142 84 234 84 stroke)
    (draw-line c 142 112 258 112 stroke)))

(define (runtime-card c runtime-paint #:padding [padding 0])
  (define full-w (+ 300 (* 2 padding)))
  (define full-h (+ 170 (* 2 padding)))
  (with-skia ([bg (make-paint #:color pale)]
              [accent (make-paint #:color teal)]
              [line (make-paint #:color 'white #:style 'stroke #:stroke-width 4)])
    ;; Cover the padded snapshot as well, keeping the PDF image opaque.
    (draw-rect c (- padding) (- padding) full-w full-h bg)
    (draw-rounded-rect c 0 0 300 170 16 16 runtime-paint)
    (draw-circle c 77 84 34 accent)
    (draw-line c 141 54 260 54 line)
    (draw-line c 141 85 236 85 line)
    (draw-line c 141 116 260 116 line)))

(define (blend-card c multiply?)
  (with-skia ([bg (make-paint #:color pale)]
              [left (make-paint #:color blue)]
              [circle (make-paint #:color (rgba 239 161 37 224)
                                  #:blend-mode (if multiply? 'multiply 'src-over))]
              [stroke (make-paint #:color ink #:style 'stroke #:stroke-width 2)])
    (draw-rounded-rect c 0 0 300 170 16 16 bg)
    (draw-rounded-rect c 0 0 178 170 16 16 left)
    (draw-circle c 178 85 60 circle)
    (draw-line c 178 15 178 155 stroke)))

(define (inner-runtime-card c runtime-paint)
  (with-skia ([bg (make-paint #:color pale)]
              [dot (make-paint #:color teal)]
              [line (make-paint #:color 'white #:style 'stroke #:stroke-width 3)])
    (draw-rect c 0 0 240 140 bg)
    (draw-rounded-rect c 0 0 240 140 14 14 runtime-paint)
    (draw-circle c 55 70 28 dot)
    (draw-line c 104 48 205 48 line)
    (draw-line c 104 70 188 70 line)
    (draw-line c 104 92 205 92 line)))

(define (outer-art c runtime-paint #:group? [group? #t])
  (with-skia ([gradient (make-linear-gradient-shader 0 0 652 0 (list (rgb 249 250 252) (rgb 232 239 248)))]
              [fill (make-paint #:shader gradient)]
              [stroke (make-paint #:color ink #:style 'stroke #:stroke-width 2)]
              [dot1 (make-paint #:color blue)]
              [dot2 (make-paint #:color orange)])
    (draw-rounded-rect c 0 0 652 170 16 16 fill)
    (draw-rounded-rect c 0 0 652 170 16 16 stroke)
    (for ([i (in-range 5)])
      (draw-circle c (+ 54 (* i 54)) 64 15 (if (even? i) dot1 dot2)))
    (draw-line c 42 112 294 112 stroke))
  (if group?
      (draw-output-group c 388 15 240 140
                         (lambda (g) (inner-runtime-card g runtime-paint))
                         #:scale 2 #:label "inner-runtime")
      (at c 388 15 (lambda (g) (inner-runtime-card g runtime-paint)))))

(define (record! sink report)
  (set-box! sink (cons report (unbox sink)))
  report)

(define (reports->jsexpr sink)
  (map output-group-report->jsexpr (reverse (unbox sink))))

(define (choice-page runtime-paint sink)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "One bounded group can choose its representation"
              "The left callback stays native; the right callback contains SkSL and becomes one bounded image.")
     (label c "01  Native vector group" 0 92)
     (label c "02  Runtime shader fallback" 352 92)
     (panel-backdrop c 0 110 300 170)
     (panel-backdrop c 352 110 300 170)
     (record! sink (draw-output-group c 0 110 300 170 vector-card
                                     #:label "vector-card"))
     (record! sink (draw-output-group c 352 110 300 170
                                     (lambda (g) (runtime-card g runtime-paint #:padding 6))
                                     #:padding 6 #:scale 2 #:label "runtime-card"))
     (label c "Both callbacks execute once. The second report selects backend-fallback." 0 320 10)
     (label c "Its logical box is 300 x 170; 6-point padding at scale 2 produces a 624 x 364 PNG." 0 348 10)
     (label c "Text, framing, and the left gradient stay native document content." 0 380 10)
     (label c "The audit records both the decision event and the actual raster boundary." 0 407 10)
     (footer c 1))
   #:margins 24 #:background 'white))

(define (choice-reference-page runtime-paint)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "One bounded group can choose its representation"
              "The left callback stays native; the right callback contains SkSL and becomes one bounded image.")
     (label c "01  Native vector group" 0 92)
     (label c "02  Runtime shader fallback" 352 92)
     (panel-backdrop c 0 110 300 170)
     (panel-backdrop c 352 110 300 170)
     (at c 0 110 vector-card)
     (at c 352 110 (lambda (g) (runtime-card g runtime-paint #:padding 6)))
     (label c "Both callbacks execute once. The second report selects backend-fallback." 0 320 10)
     (label c "Its logical box is 300 x 170; 6-point padding at scale 2 produces a 624 x 364 PNG." 0 348 10)
     (label c "Text, framing, and the left gradient stay native document content." 0 380 10)
     (label c "The audit records both the decision event and the actual raster boundary." 0 407 10)
     (footer c 1))
   #:margins 24 #:background 'white))

(define (isolation-page sink)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Destination-dependent blending gets an isolated backdrop"
              "The right group multiplies against content recorded inside its own bounds, not against the page behind it.")
     (label c "01  Ordinary source-over: native" 0 92)
     (label c "02  Multiply: isolated raster group" 352 92)
     (panel-backdrop c 0 110 300 170)
     (panel-backdrop c 352 110 300 170)
     (record! sink (draw-output-group c 0 110 300 170
                                     (lambda (g) (blend-card g #f))
                                     #:label "source-over"))
     (record! sink (draw-output-group c 352 110 300 170
                                     (lambda (g) (blend-card g #t))
                                     #:scale 2 #:label "multiply"))
     (label c "The source-over panel can replay natively. Multiply is classified as isolated-compositing." 0 320 10)
     (label c "The fallback is exactly 300 x 170 at scale 2: one 600 x 340 image." 0 348 10)
     (label c "The pale internal background makes the blend independent of pre-existing page pixels." 0 380 10)
     (label c "No automatic backdrop capture or guessed paint bounds are involved." 0 407 10)
     (footer c 2))
   #:margins 24 #:background 'white))

(define (isolation-reference-page)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Destination-dependent blending gets an isolated backdrop"
              "The right group multiplies against content recorded inside its own bounds, not against the page behind it.")
     (label c "01  Ordinary source-over: native" 0 92)
     (label c "02  Multiply: isolated raster group" 352 92)
     (panel-backdrop c 0 110 300 170)
     (panel-backdrop c 352 110 300 170)
     (at c 0 110 (lambda (g) (blend-card g #f)))
     ;; Independent reference for the documented isolation semantics.
     (draw-rasterized c 352 110 300 170 (lambda (g) (blend-card g #t)) #:scale 2)
     (label c "The source-over panel can replay natively. Multiply is classified as isolated-compositing." 0 320 10)
     (label c "The fallback is exactly 300 x 170 at scale 2: one 600 x 340 image." 0 348 10)
     (label c "The pale internal background makes the blend independent of pre-existing page pixels." 0 380 10)
     (label c "No automatic backdrop capture or guessed paint bounds are involved." 0 407 10)
     (footer c 2))
   #:margins 24 #:background 'white))

(define (nested-page runtime-paint sink)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Nested groups can keep the parent native"
              "The outer picture contains ordinary vector drawing plus one child fallback image.")
     (label c "01  Outer group: native replay; inner runtime group: raster fallback" 0 92)
     (panel-backdrop c 0 110 652 170)
     (record! sink
              (draw-output-group c 0 110 652 170
                                 (lambda (g) (outer-art g runtime-paint))
                                 #:label "outer-group"))
     (label c "The outer report contains the child decision rather than inheriting the child's SkSL feature." 0 320 10)
     (label c "Only the 240 x 140 inner group is rasterized at scale 2: one 480 x 280 image." 0 348 10)
     (label c "The border, gradient strip, dots, and surrounding page text remain vector/native." 0 380 10)
     (label c "This is the intended granularity: author-provided bounds, smallest necessary fallback." 0 407 10)
     (footer c 3))
   #:margins 24 #:background 'white))

(define (nested-reference-page runtime-paint)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Nested groups can keep the parent native"
              "The outer picture contains ordinary vector drawing plus one child fallback image.")
     (label c "01  Outer group: native replay; inner runtime group: raster fallback" 0 92)
     (panel-backdrop c 0 110 652 170)
     (at c 0 110 (lambda (g) (outer-art g runtime-paint #:group? #f)))
     (label c "The outer report contains the child decision rather than inheriting the child's SkSL feature." 0 320 10)
     (label c "Only the 240 x 140 inner group is rasterized at scale 2: one 480 x 280 image." 0 348 10)
     (label c "The border, gradient strip, dots, and surrounding page text remain vector/native." 0 380 10)
     (label c "This is the intended granularity: author-provided bounds, smallest necessary fallback." 0 407 10)
     (footer c 3))
   #:margins 24 #:background 'white))

(define (write-json-file path data)
  (call-with-output-file path
    (lambda (out) (write-json data out) (newline out))
    #:exists 'replace))

(define (html-escape s)
  (for/fold ([text s]) ([p (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")))])
    (string-replace text (car p) (cdr p))))

(module+ main
  (define args (current-command-line-arguments))
  (when (> (vector-length args) 1)
    (error 'output-groups "expected optional output prefix"))
  (define prefix
    (if (zero? (vector-length args))
        "output/output-groups-0.34"
        (vector-ref args 0)))
  (define (file suffix) (string-append prefix suffix))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))

  (with-skia ([effect (make-runtime-effect "half4 main(float2 p) { return half4(0.93,0.31,0.18,1); }")]
              [shader (runtime-effect->shader effect)]
              [runtime-paint (make-paint #:shader shader)])
    (define names '("choice" "isolation" "nested"))
    (define (build-page name sink)
      (cond [(string=? name "choice") (choice-page runtime-paint sink)]
            [(string=? name "isolation") (isolation-page sink)]
            [else (nested-page runtime-paint sink)]))
    (define (build-reference name)
      (cond [(string=? name "choice") (choice-reference-page runtime-paint)]
            [(string=? name "isolation") (isolation-reference-page)]
            [else (nested-reference-page runtime-paint)]))

    ;; Generate the three-page PDF and retain its backend-specific decisions.
    (define pdf-sinks (for/list ([name (in-list names)]) (box '())))
    (define pdf-pages
      (for/list ([name (in-list names)] [sink (in-list pdf-sinks)])
        (build-page name sink)))
    (define pdf-audit
      (save-output/audit pdf-pages (file ".pdf") 'pdf
                         #:policy 'error #:exists 'replace
                         #:title "Backend-aware bounded output groups"))
    (write-json-file (file ".pdf.audit.json") (output-audit-report->jsexpr pdf-audit))

    ;; Each SVG gets a fresh callback/report sink. References do not use the
    ;; output-group decision machinery and are not SVG/PDF rasterizations.
    (define svg-decisions '())
    (for ([name (in-list names)])
      (define sink (box '()))
      (define page (build-page name sink))
      (define audit
        (save-output/audit page (file (string-append "." name ".svg")) 'svg
                           #:policy 'error #:exists 'replace #:id-prefix name))
      (write-json-file (file (string-append "." name ".audit.json"))
                       (output-audit-report->jsexpr audit))
      (set! svg-decisions
            (cons (hasheq 'page name 'groups (reports->jsexpr sink)) svg-decisions))
      (with-skia ([im (output-page->image (build-reference name) #:dpi 144)])
        (save-image im (file (string-append "." name ".reference.png"))
                    'png #:exists 'replace)))

    (define decisions
      (hasheq 'pdf
              (for/list ([name (in-list names)] [sink (in-list pdf-sinks)])
                (hasheq 'page name 'groups (reports->jsexpr sink)))
              'svg (reverse svg-decisions)))
    (write-json-file (file ".decisions.json") decisions)

    (define base (html-escape (path->string (file-name-from-path prefix))))
    (call-with-output-file (file ".review.html")
      (lambda (out)
        (display "<!doctype html><meta charset=\"utf-8\"><title>Output groups review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}code{background:#fff;padding:2px 5px}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style><h1>Backend-aware bounded output groups</h1>" out)
        (fprintf out "<p><a href=\"~a.pdf\">Actual PDF</a> | <a href=\"~a.pdf.audit.json\">PDF audit</a> | <a href=\"~a.decisions.json\">Decision tree</a> | <a href=\"~a.inspection.json\">Structural inspection</a></p>" base base base base)
        (display "<p>Left: actual SVG. Right: independent raster reference, not a PDF/SVG rasterization. The structural inspector checks the embedded PNG dimensions in both SVG and PDF.</p>" out)
        (for ([name (in-list names)])
          (fprintf out "<h2>~a</h2><div class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a.~a.svg\"></figure><figure><figcaption>Independent raster reference</figcaption><img src=\"~a.~a.reference.png\"></figure></div>" name base name base name)))
      #:exists 'replace))
  (printf "Wrote ~a.pdf; 3 SVGs/references; 4 audits; decisions; review HTML\n" prefix))
