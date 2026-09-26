#lang racket/base
(require racket/cmdline racket/file racket/path racket/list racket/string json "../main.rkt")

;; One visual registry, explicit sRGB normalization before document embedding.
;; Encoded P3 files below retain P3 samples and their ICC metadata for browsers.
(define ink "#20344E")
(define teal "#10988E")
(define (label c text x y [size 11] [color ink])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [paint (make-paint #:color color)])
    (draw-simple-text c text x y font paint)))
(define (heading c title subtitle)
  (with-skia ([paint (make-paint #:color teal)]) (draw-rect c 0 0 34 2 paint))
  (label c title 0 32 23)
  (label c subtitle 0 53 10))
(define (footer c)
  (label c "RACKET / SKIA   |   COLOR-MANAGED OUTPUT" 0 445 9))
(define (grey-bytes)
  (apply bytes (append-map (lambda (n) (list n n n 255)) (range 256))))
(define colors '((180 100 65) (70 155 100) (80 120 180) (160 90 160) (128 128 128)))
(define (palette-bytes width height)
  (define out (make-bytes (* 4 width height)))
  (for* ([y (in-range height)] [x (in-range width)])
    (define rgb (list-ref colors (min 4 (quotient (* 5 x) width))))
    (define at (* 4 (+ x (* y width))))
    (for ([value (in-list (append rgb '(255)))] [i (in-naturals at)])
      (bytes-set! out i value)))
  out)
(define (bytes-file path bs)
  (call-with-output-file path (lambda (out) (write-bytes bs out) (void)) #:mode 'binary #:exists 'replace))

(define gamma-page
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Transfer functions change samples"
              "The same stored midpoint has different meanings in linear RGB and sRGB.")
     (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                 [raw (rgba-bytes->image 256 1 (grey-bytes) #:color-space srgb)]
                 [lin (rgba-bytes->image 256 1 (grey-bytes) #:color-space linear)]
                 [converted (image-convert-color-space lin srgb)]
                 [decoded (image-from-bytes
                           (image->png-bytes lin #:color-space srgb
                                            #:icc-profile (color-space->icc-bytes srgb)))])
       (for ([im (in-list (list raw converted decoded))]
             [y '(102 207 312)]
             [text '("01  Stored values displayed as sRGB" "02  Linear values converted to sRGB" "03  Converted, encoded as PNG, decoded")])
         (label c text 0 (- y 13) 12)
         (draw-image-rect c im 0 y 660 46 #:sampling 'nearest))
       (label c "Raw midpoint: 128. Converted midpoint: about 188. Conversion leaves alpha unchanged." 0 385 10)
       (label c "Adding an ICC tag alone is not a conversion. All three embedded images here use sRGB samples." 0 407 10))
     (footer c))
   #:margins 24 #:background 'white))

(define gamut-page
  (make-output-page
   720 500
   (lambda (c)
     (heading c "A gamut matrix is not a geometry matrix"
              "Each row starts with the same RGB numbers, then converts from its declared space to sRGB.")
     (with-skia ([target (make-srgb-color-space)])
       (for ([gamut '(srgb display-p3 adobe-rgb rec2020)]
             [tf '(srgb srgb gamma-2.2 rec2020)]
             [title '("sRGB" "Display P3" "Adobe RGB" "Rec. 2020 (SDR)")]
             [y '(104 178 252 326)])
         (with-skia ([source (make-rgb-color-space tf gamut)]
                     [im (rgba-bytes->image 100 20 (palette-bytes 100 20) #:color-space source)]
                     [converted (image-convert-color-space im target)])
           (label c title 0 (+ y 27) 11)
           (draw-image-rect c converted 140 y 510 44 #:sampling 'nearest))))
     (label c "Wide-gamut values outside sRGB are clipped by this 8-bit conversion; this is not gamut mapping." 0 397 10)
     (label c "Custom primaries are adapted to XYZ D50. The transform changes color values, not page coordinates." 0 415 10)
     (footer c))
   #:margins 24 #:background 'white))

(define (encoded-page records)
  (make-output-page
   720 500
   (lambda (c)
     (heading c "Profiles in files; normalized samples on paper"
              "The external image files carry ICC metadata. These document thumbnails are converted to sRGB.")
     (with-skia ([srgb (make-srgb-color-space)])
       (for ([record (in-list records)] [i (in-naturals)])
         (define x (* (modulo i 3) 225))
         (define y (+ 126 (* (quotient i 3) 117)))
         (label c (car record) x (- y 16) 11)
         (with-skia ([decoded (image-from-bytes (cdr record))]
                     [converted (image-convert-color-space decoded srgb)])
           (draw-image-rect c converted x y 204 60 #:sampling 'nearest))))
     (label c "PDF/A mode adds XMP, a UUID, and an sRGB output intent. It is not a PDF/A conformance validator." 0 362 10)
     (label c "The pinned PDF backend does not reliably preserve source-image ICC profiles: normalize before embedding." 0 386 10)
     (label c "The separate browser images test ICC-aware viewing. Viewer and display color management still matter." 0 410 10)
     (footer c))
   #:margins 24 #:background 'white))

(define (escaped s)
  (string-replace (string-replace (string-replace (string-replace s "&" "&amp;") "<" "&lt;") ">" "&gt;") "\"" "&quot;"))
(define (base-name s) (escaped (path->string (file-name-from-path s))))
(module+ main
  (define prefix (command-line #:program "color-output.rkt" #:args ([prefix "color-output-0.26"]) prefix))
  (define (name suffix) (string-append prefix suffix))
  (make-parent-directory* (name ".pdf"))
  (define records '())
  (define trace '())
  (with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)] [srgb (make-srgb-color-space)]
              [source (rgba-bytes->image 250 60 (palette-bytes 250 60) #:color-space p3)]
              [converted (image-convert-color-space source srgb)])
    (for ([space (in-list (list p3 srgb))] [image (in-list (list source converted))]
          [stem '("p3" "srgb")])
      (define profile (color-space->icc-bytes space))
      (bytes-file (name (string-append "." stem ".icc")) profile)
      (set! trace (append trace (list (hasheq 'space stem
                                             'xyz (vector->list (color-space-xyz-d50 space))
                                             'first-pixel (bytes->list (subbytes (image->rgba-bytes image) 0 4))))))
      (for ([format '(png jpeg webp)])
        (define suffix (string-append "." stem "." (symbol->string format)))
        (define bs (image->encoded-bytes image format #:quality 100 #:jpeg-downsample 'yuv-444
                                        #:webp-lossless? #t #:icc-profile profile
                                        #:icc-description (string-append "Color output " stem)))
        (bytes-file (name suffix) bs)
        (set! records (append records (list (cons (string-append stem " / " (symbol->string format)) bs)))))))
  (bytes-file (name ".trace.json") (jsexpr->bytes (hasheq 'spaces trace 'note "Native probe values, not display measurements")))
  (define registry (list (cons "gamma" gamma-page) (cons "gamuts" gamut-page)
                         (cons "encoded" (encoded-page records))))
  (save-output (map cdr registry) (name ".pdf") 'pdf #:exists 'replace #:title "Color output probe")
  (save-output (map cdr registry) (name ".pdfa.pdf") 'pdf #:exists 'replace
               #:title "Color output probe - Skia PDF-A mode" #:pdfa? #t)
  (for ([entry (in-list registry)])
    (define stem (string-append "." (car entry)))
    (save-output (cdr entry) (name (string-append stem ".svg")) 'svg #:exists 'replace
                 #:title (string-append "Color output: " (car entry)) #:id-prefix (car entry))
    (with-skia ([im (output-page->image (cdr entry) #:dpi 144)])
      (save-image im (name (string-append stem ".reference.png")) 'png #:exists 'replace)))
  (call-with-output-file (name ".review.html")
    (lambda (out)
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Color output review</title><style>body{font:16px system-ui;margin:24px;color:#20344e;background:#edf0f4}.pair,.triple{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin:16px 0 28px}.triple{grid-template-columns:repeat(3,1fr)}figure{margin:0}img{width:100%;background:white}figcaption{margin-bottom:8px}@media(max-width:800px){.pair,.triple{grid-template-columns:1fr}}</style><h1>Color-managed output</h1>" out)
      (fprintf out "<p><a href=\"~a\">Normal PDF</a> | <a href=\"~a\">Skia PDF/A-mode PDF</a> (not independently certified). Left: actual SVG. Right: independently drawn raster reference, not a vector-file rasterization.</p>" (base-name (name ".pdf")) (base-name (name ".pdfa.pdf")))
      (for ([entry (in-list registry)])
        (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a\" alt=\"SVG\"></figure><figure><figcaption>Separate raster reference</figcaption><img src=\"~a\" alt=\"Reference\"></figure></section>"
                 (car entry) (base-name (name (string-append "." (car entry) ".svg")))
                 (base-name (name (string-append "." (car entry) ".reference.png")))))
      (display "<h2>Actual encoded images (browser color management)</h2><p>Each P3 file and its converted sRGB counterpart should look close for these in-gamut patches. JPEG edges can differ. This is not a display calibration test.</p>" out)
      (for ([space '("p3" "srgb")])
        (fprintf out "<h3>~a</h3><section class=\"triple\">" space)
        (for ([format '("png" "jpeg" "webp")])
          (fprintf out "<figure><figcaption>~a</figcaption><img src=\"~a\" alt=\"ICC image\"></figure>"
                   format (base-name (name (string-append "." space "." format)))))
        (display "</section>" out))
      (display "</html>" out)) #:exists 'replace)
  (printf "Wrote ~a.pdf, ~a.pdfa.pdf, 3 SVGs/references, 6 ICC-tagged images, profiles, trace and review HTML\n" prefix prefix))
