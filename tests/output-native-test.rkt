#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/path "../main.rkt")
(provide output-native-tests)

(define (text-page)
  (make-output-page
   216 144
   (lambda (c)
     (with-skia ([font (make-font #:size 18)] [paint (make-paint #:color 'black)])
       (draw-simple-text c "Vector output" 10 35 font paint)))))
(define (has-text? bs) (regexp-match? #rx#"<text[ >]" bs))
(define (has-path? bs) (regexp-match? #rx#"<path[ >]" bs))
(define (pdf-pages bs) (length (regexp-match* #rx#"/Type /Page([^s]|$)" bs)))
(define (in-temp-dir proc)
  (define dir (make-temporary-file "skia-output-~a" 'directory))
  (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))
(define (foreign-error thunk)
  (define ch (make-channel))
  (define worker
    (thread (lambda ()
              (with-handlers ([exn? (lambda (e) (channel-put ch e))])
                (thunk) (channel-put ch #f)))))
  (define result (channel-get ch))
  (thread-wait worker)
  result)

(define output-native-tests
  (test-suite
   "Shared vector output: live rendering and lifetime"
   (test-case "the same page exports as PDF and physically sized SVG"
     (define page (text-page))
     (define pdf (output->bytes page 'pdf))
     (define svg (output->bytes page 'svg))
     (check-true (regexp-match? #rx#"^%PDF-" pdf))
     (check-equal? (pdf-pages pdf) 1)
     (check-true (regexp-match? #rx#"width=\"216.0pt\" height=\"144.0pt\"" svg))
     (check-true (regexp-match? #rx#"viewBox=\"0 0 216.0 144.0\"" svg)))
   (test-case "auto outlines SVG while explicit native remains text"
     (check-false (has-text? (output->bytes (text-page) 'svg)))
     (check-true (has-path? (output->bytes (text-page) 'svg)))
     (check-true (has-text? (output->bytes (text-page) 'svg #:text-mode 'native))))
   (test-case "lower-level exporters retain their legacy native-text default"
     (define svg
       (call-with-svg-bytes 100 70
         (lambda (c)
           (with-skia ([f (make-font #:size 16)] [p (make-paint)])
             (draw-simple-text c "ABC" 10 30 f p)))))
     (check-true (has-text? svg))
     (check-eq? (current-text-output-mode) 'native))
   (test-case "multi-page PDF invokes each callback exactly once"
     (define calls '())
     (define (page n) (make-output-page (+ 100 n) 90 (lambda (_) (set! calls (cons n calls)))))
     (define bs (output->bytes (list (page 1) (page 2) (page 3)) 'pdf))
     (check-equal? calls '(3 2 1))
     (check-equal? (pdf-pages bs) 3))
   (test-case "SVG callback can return multiple values without changing output"
     (define n 0)
     (define bs (output->bytes (make-output-page 40 30 (lambda (_) (set! n (add1 n)) (values 1 2))) 'svg))
     (check-equal? n 1)
     (check-true (regexp-match? #rx#"</svg>" bs)))
   (test-case "metadata and prefixed resource references survive the shared wrapper"
     (define page
       (make-output-page 90 60
         (lambda (c)
           (with-skia ([sh (make-linear-gradient-shader 0 0 90 0 '(red blue))]
                       [p (make-paint #:shader sh)])
             (draw-rect c 0 0 90 60 p)))))
     (define bs (output->bytes page 'svg #:title "A & B" #:description "<detail>" #:id-prefix "unit"))
     (check-true (regexp-match? #rx#"<title>A &amp; B</title>" bs))
     (check-true (regexp-match? #rx#"<desc>&lt;detail&gt;</desc>" bs))
     (check-true (regexp-match? #rx#"id=\"unit-0\"" bs)))
   (test-case "millimetres are mapped to the same physical dimensions"
     (define bs (output->bytes (make-output-page 127/5 127/10 void #:unit 'mm) 'svg))
     (check-true (regexp-match? #rx#"width=\"72.0pt\" height=\"36.0pt\"" bs))
     (with-skia ([im (output-page->image (make-output-page 1 1 void #:unit 'in) #:dpi 96)])
       (check-equal? (list (image-width im) (image-height im)) '(96 96))))
   (test-case "margin translation and content clipping are visible in pixel readback"
     (define page
       (make-output-page 40 30
         (lambda (c)
           (with-skia ([p (make-paint #:color 'red)]) (draw-rect c -5 -5 100 100 p)))
         #:margins '(5 7 6 8) #:background 'white))
     (with-skia ([s (make-surface 50 40)])
       (draw-output-page (surface-canvas s) page)
       (check-equal? (surface-pixel s 4 10) (rgb 255 255 255))
       (check-equal? (surface-pixel s 6 8) (rgb 255 0 0))
       (check-equal? (surface-pixel s 34 10) (rgb 255 255 255))
       (check-equal? (surface-pixel s 10 22) (rgb 255 255 255))))
   (test-case "unclipped content can deliberately draw into the margins"
     (with-skia ([s (make-surface 40 30)])
       (draw-output-page (surface-canvas s)
         (make-output-page 40 30
           (lambda (c) (with-skia ([p (make-paint #:color 'blue)]) (draw-rect c -5 -5 10 10 p)))
           #:margins 5 #:clip? #f))
       (check-equal? (surface-pixel s 2 2) (rgb 0 0 255))))
   (test-case "drawing a page restores canvas state and policy parameters"
     (with-skia ([s (make-surface 40 40)])
       (define c (surface-canvas s))
       (define before (canvas-save-count c))
       (check-exn #rx"stop"
                  (lambda ()
                    (draw-output-page c
                      (make-output-page 30 30 (lambda (_) (error 'page "stop")) #:margins 2)
                      #:text-mode 'outline #:raster-dpi 288)))
       (check-equal? (canvas-save-count c) before)
       (check-eq? (current-text-output-mode) 'native)
       (check-equal? (current-raster-output-scale) 1)))
   (test-case "scoped page canvases never escape as live resources"
     (for ([format '(pdf svg)])
       (define escaped #f)
       (output->bytes (make-output-page 20 20 (lambda (c) (set! escaped c))) format)
       (check-true (skia-closed? escaped))
       (check-exn #rx"closed" (lambda () (canvas-save! escaped)))))
   (test-case "shaped and paragraph text honor outline mode"
     (define bs
       (output->bytes
        (make-output-page 300 150
          (lambda (c)
            (with-skia ([f (make-font #:size 18)] [sh (make-shaper f)] [p (make-paint)])
              (draw-shaped-text c sh "office affinity AV" 10 30 p)
              (draw-text-layout c (layout-text sh "Paragraph output wraps here." #:width 140) 10 60 p))))
        'svg))
     (check-false (has-text? bs))
     (check-true (has-path? bs)))
   (test-case "mixed-run paragraph drawing also honors outline mode"
     (define bs
       (output->bytes
        (make-output-page 260 90
          (lambda (c)
            (with-skia ([f (make-font #:size 16)] [sh (make-shaper f)]
                        [fm (default-font-manager)] [p (make-paint)])
              (draw-mixed-text-layout c (layout-mixed-text sh fm "Racket 123 text" #:width 220) 8 8 p))))
        'svg))
     (check-false (has-text? bs))
     (check-true (has-path? bs)))
   (test-case "blob outlines survive original font mutation and closure"
     (define f (make-font #:size 20))
     (define gs (font-text->glyphs f "AB"))
     (define blob (make-positioned-text-blob f gs '((0 0) (30 0))))
     (define before
       (with-skia ([path (text-blob->path blob)]) (path->svg-path path)))
     (font-set-size! f 70)
     (font-set-skew-x! f 1/2)
     (skia-close! f)
     (with-skia ([path (text-blob->path blob)])
       (check-equal? (path->svg-path path) before)
       (skia-close! blob)
       (check-true (> (path-point-count path) 0)))
     (check-exn #rx"closed" (lambda () (text-blob->path blob))))
   (test-case "blob construction snapshots mutable glyph and position vectors"
     (with-skia ([f (make-font #:size 18)])
       (define gs (vector (font-char->glyph f #\A)))
       (define xy (vector 7 11))
       (define ps (vector xy))
       (with-skia ([blob (make-positioned-text-blob f gs ps)] [path (text-blob->path blob)])
         (define before (path->svg-path path))
         (vector-set! gs 0 0)
         (vector-set! xy 0 999)
         (with-skia ([after (text-blob->path blob)]) (check-equal? (path->svg-path after) before)))))
   (test-case "prebuilt text blobs honor the draw-time outline policy"
     (with-skia ([f (make-font #:size 18)]
                 [blob (make-positioned-text-blob f (list (font-char->glyph f #\A)) '((0 0)))]
                 [p (make-paint)])
       (define page (make-output-page 80 60 (lambda (c) (draw-text-blob c blob 10 30 p))))
       (check-false (has-text? (output->bytes page 'svg)))
       (check-true (has-path? (output->bytes page 'svg)))
       (check-true (has-text? (output->bytes page 'svg #:text-mode 'native)))))
   (test-case "outline conversion is thread confined and repeated close is safe"
     (with-skia ([f (make-font #:size 18)]
                 [blob (make-positioned-text-blob f (list (font-char->glyph f #\A)) '((0 0)))])
       (define e (foreign-error (lambda () (text-blob->path blob))))
       (check-true (exn:fail? e))
       (check-true (regexp-match? #rx"another Racket thread" (exn-message e)))
       (skia-close! blob)
       (skia-close! blob)))
   (test-case "a native-text picture is not retroactively rewritten by export policy"
     (with-skia ([pic
                  (call-with-picture 100 60
                    (lambda (c)
                      (with-skia ([f (make-font #:size 16)] [p (make-paint)])
                        (draw-simple-text c "ABC" 10 30 f p))))])
       (check-true
        (has-text? (output->bytes (make-output-page 100 60 (lambda (c) (draw-picture c pic))) 'svg)))))
   (test-case "raster padding preserves outside effects without moving the content origin"
     (with-skia ([s (make-surface 50 40)] [p (make-paint #:color 'red)])
       (draw-rasterized (surface-canvas s) 10 10 20 10
         (lambda (c) (draw-rect c -4 -3 28 16 p)) #:padding 5)
       (check-equal? (surface-pixel s 7 8) (rgb 255 0 0))
       (check-equal? (surface-pixel s 15 15) (rgb 255 0 0))
       (check-equal? (surface-pixel s 4 8) (rgba 0 0 0 0))))
   (test-case "export DPI sets the default pixels per callback drawing unit"
     (define observed #f)
     (output->bytes
      (make-output-page 100 70
        (lambda (_) (set! observed (current-raster-output-scale))) #:unit 'mm)
      'svg #:raster-dpi 144)
     (check-= observed (/ 144 25.4) 0.000001)
     (check-equal? (current-raster-output-scale) 1))
   (test-case "explicit raster groups restore native glyph rendering locally"
     (define in-mode #f)
     (with-skia ([s (make-surface 30 30)])
       (parameterize ([current-text-output-mode 'outline])
         (draw-rasterized (surface-canvas s) 0 0 20 20
           (lambda (_) (set! in-mode (current-text-output-mode))))
         (check-eq? (current-text-output-mode) 'outline)))
     (check-eq? in-mode 'native))
   (test-case "tagged fallback surfaces use owned color spaces safely"
     (with-skia ([s (make-surface 30 30)] [cs (make-srgb-color-space)]
                 [p (make-paint #:color 'red)])
       (draw-rasterized (surface-canvas s) 0 0 20 20
         (lambda (c) (draw-rect c 0 0 20 20 p)) #:color-space cs)
       (check-equal? (surface-pixel s 10 10) (rgb 255 0 0))
       (skia-close! cs)
       (check-exn #rx"closed"
                  (lambda () (draw-rasterized (surface-canvas s) 0 0 20 20 void #:color-space cs)))))
   (test-case "snapshot images outlive their temporary page surface"
     (with-skia ([cs (make-srgb-color-space)]
                 [im (output-page->image (make-output-page 24 12 void #:background 'blue)
                                         #:dpi 72 #:color-space cs)])
       (check-equal? (list (image-width im) (image-height im)) '(24 12))
       (check-equal? (subbytes (image->rgba-bytes im) 0 4) (bytes 0 0 255 255))
       (with-skia ([tag (image-color-space im)]) (check-true (color-space=? tag cs)))))
   (test-case "failed drawing never replaces an existing output file"
     (in-temp-dir
      (lambda (dir)
        (define target (build-path dir "keep.svg"))
        (call-with-output-file target (lambda (out) (write-bytes #"original" out)))
        (check-exn #rx"stop"
                   (lambda () (save-output (make-output-page 20 20 (lambda (_) (error 'draw "stop")))
                                            target 'svg #:exists 'replace)))
        (check-equal? (file->bytes target) #"original")
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "successful publication is complete for both formats"
     (in-temp-dir
      (lambda (dir)
        (for ([fmt '(pdf svg)])
          (define target (build-path dir (format "result.~a" fmt)))
          (save-output (text-page) target fmt)
          (define bs (file->bytes target))
          (check-true (regexp-match? (if (eq? fmt 'pdf) #rx#"%%EOF" #rx#"</svg>") bs))))))
   (test-case "a callback-created destination is not overwritten in error mode"
     (in-temp-dir
      (lambda (dir)
        (define target (build-path dir "race.svg"))
        (check-exn exn:fail?
                   (lambda ()
                     (save-output (make-output-page 20 20
                                    (lambda (_)
                                      (call-with-output-file target (lambda (out) (write-bytes #"other" out)))))
                                  target 'svg)))
        (check-equal? (file->bytes target) #"other")
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "continuation escape restores policy and publishes no file"
     (in-temp-dir
      (lambda (dir)
        (define target (build-path dir "escape.svg"))
        (define escaped #f)
        (define result
          (let/ec escape
            (save-output (make-output-page 20 20 (lambda (c) (set! escaped c) (escape 'left)))
                         target 'svg)
            'failed))
        (check-eq? result 'left)
        (check-false (file-exists? target))
        (check-true (skia-closed? escaped))
        (check-eq? (current-text-output-mode) 'native))))
   (test-case "tiny output byte limits fail without publishing partial SVG"
     (in-temp-dir
      (lambda (dir)
        (define target (build-path dir "limit.svg"))
        (parameterize ([current-skia-byte-limit 16])
          (check-exn exn:fail? (lambda () (save-output (make-output-page 10 10 void) target 'svg))))
        (check-false (file-exists? target))
        (check-equal? (directory-list dir) '()))))
   (test-case "repeated native and outlined exports remain independent"
     (for ([i (in-range 10)])
       (with-skia ([f (make-font #:size 12)]
                   [blob (make-positioned-text-blob f (list (font-char->glyph f #\A)) '((0 0)))]
                   [p (make-paint)])
         (define page (make-output-page 40 30 (lambda (c) (draw-text-blob c blob 5 20 p))))
         (check-false (has-text? (output->bytes page 'svg)))
         (check-true (has-text? (output->bytes page 'svg #:text-mode 'native))))))))

(module+ test
  (skia-check!)
  (unless (zero? (run-tests output-native-tests)) (error 'output-native-tests "test failures")))
