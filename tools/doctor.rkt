#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt" "../private/harfbuzz-types.rkt"
         "../private/bidi.rkt" "../private/unicode-conformance.rkt"
         "codec-doctor.rkt" "pdf-doctor.rkt" "svg-doctor.rkt" "output-doctor.rkt"
         "path-matrix-doctor.rkt" "filter-graph-doctor.rkt" "color-output-doctor.rkt" "annotation-doctor.rkt")
(module+ main
  (printf "Racket: ~a; VM: ~a; platform: ~a/~a\n"
          (version) (system-type 'vm) (system-type 'os) (system-type 'arch))
  (printf "Pinned native package: SkiaSharp ~a\n" native-package-version)
  (printf "ABI sizes: pointer=~a image-info=~a rect=~a point=~a textblob-runbuffer=~a irect=~a sampling=~a PNG-options=~a JPEG-options=~a WebP-options=~a font-metrics=~a HB-info=~a HB-pos=~a HB-feature=~a\n"
          (ctype-sizeof _pointer) (ctype-sizeof _sk-image-info)
          (ctype-sizeof _sk-rect) (ctype-sizeof _sk-point)
          (ctype-sizeof _sk-textblob-runbuffer) (ctype-sizeof _sk-irect)
          (ctype-sizeof _sk-sampling) (ctype-sizeof _sk-png-options)
          (ctype-sizeof _sk-jpeg-options) (ctype-sizeof _sk-webp-options)
          (ctype-sizeof _sk-font-metrics)
          (ctype-sizeof _hb-glyph-info) (ctype-sizeof _hb-glyph-position)
          (ctype-sizeof _hb-feature))
  (skia-check!)
  (codec-doctor!)
  (pdf-doctor!)
  (svg-doctor!)
  (output-doctor!)
  (path-matrix-doctor!)
  (filter-graph-doctor!)
  (color-output-doctor!)
  (annotation-doctor!)
  (printf "Native library: ~a\n" (skia-native-library-path))
  (printf "Native ABI version: ~a\n" (skia-native-version))
  (harfbuzz-check!)
  (printf "HarfBuzzSharp native package: ~a\n" harfbuzz-package-version)
  (printf "HarfBuzz library: ~a\n" (harfbuzz-native-library-path))
  (printf "HarfBuzz version: ~a\n" (harfbuzz-native-version))
  (with-skia ([s (make-surface 2 2 #:background 'red)])
    (unless (equal? (surface-pixel s 0 0) (rgb 255 0 0))
      (error 'doctor "pixel readback failed"))
    (printf "Raster readback passed; native PNG: ~a bytes\n"
            (bytes-length (surface->png-bytes s))))
  (with-skia ([tf (make-typeface)]
              [f (make-font tf #:size 24)])
    (define width (measure-simple-text f "Skia"))
    (unless (> width 0)
      (error 'doctor "simple text measurement failed"))
    (printf "Font/text passed; default family: ~s; \"Skia\" advance: ~a\n"
            (typeface-family-name tf) width))
  (with-skia ([s (make-surface 21 1)]
              [sh (make-linear-gradient-shader 0 0 20 0 '(red blue))]
              [p (make-paint #:shader sh)])
    (draw-paint (surface-canvas s) p)
    (define left (surface-pixel s 1 0))
    (define right (surface-pixel s 19 0))
    (unless (and (> (rgba-red left) (rgba-blue left))
                 (> (rgba-blue right) (rgba-red right)))
      (error 'doctor "gradient shader rasterization failed"))
    (printf "Shaders/gradients passed; linear endpoint dominance verified\n"))
  (with-skia ([s (make-surface 8 8 #:background 'red)]
              [im (surface-snapshot s)])
    (define png (image->png-bytes im))
    (define jpg (image->jpeg-bytes im #:quality 95))
    (define webp (image->webp-bytes im #:lossless? #t))
    (for ([data (in-list (list png jpg webp))]
          [format (in-list '(png jpeg webp))])
      (define info (encoded-image-info-from-bytes data))
      (unless (and (eq? (encoded-image-info-format info) format)
                   (= (encoded-image-info-width info) 8)
                   (= (encoded-image-info-height info) 8))
        (error 'doctor "~a codec metadata failed" format))
      (with-skia ([decoded (image-from-bytes data)])
        (unless (and (= (image-width decoded) 8) (= (image-height decoded) 8))
          (error 'doctor "~a decode failed" format))))
    (printf "Codecs passed; PNG/JPEG/WebP encode, probe, and decode verified\n"))
  (with-skia ([path (make-path '((move 0 0) (line 100 0)))]
              [measure (make-path-measure path)]
              [dash (make-dash-path-effect '(6 4))]
              [paint (make-paint #:style 'stroke #:stroke-width 2
                                 #:path-effect dash)]
              [a (make-path)]
              [b (make-path)])
    (unless (< (abs (- (path-measure-length measure) 100.0)) 0.001)
      (error 'doctor "path measurement length failed"))
    (define-values (x y tx ty) (path-measure-position+tangent measure 40))
    (unless (and x y tx ty (< (abs (- x 40.0)) 0.001)
                 (< (abs y) 0.001) (< (abs (- tx 1.0)) 0.001)
                 (< (abs ty) 0.001))
      (error 'doctor "path position/tangent failed"))
    (path-add-rect! a 0 0 20 20)
    (path-add-rect! b 10 0 20 20)
    (with-skia ([u (path-union a b)])
      (unless (and (path-contains? u 5 10)
                   (path-contains? u 25 10))
        (error 'doctor "boolean path union failed")))
    (define held (paint-path-effect paint))
    (unless (path-effect? held)
      (error 'doctor "paint path-effect attachment failed"))
    ;; The getter result owns a native reference.
    (skia-close! held)
    (printf "Path effects/measurement passed; dash, tangent, and boolean ops verified\n"))
  (with-skia ([s (make-surface 40 24)]
              [cf (make-color-matrix-filter
                   '(0 0 1 0 0  0 1 0 0 0  1 0 0 0 0  0 0 0 1 0))]
              [mf (make-blur-mask-filter 2 #:respect-ctm? #f)]
              [imf (make-drop-shadow-image-filter 6 0 1 1 (rgba 0 0 0 180))]
              [color-paint (make-paint #:color 'red #:antialias? #f #:color-filter cf)]
              [effect-paint (make-paint #:color 'red #:mask-filter mf #:image-filter imf)])
    (define c (surface-canvas s))
    (draw-rect c 2 2 8 8 color-paint)
    (unless (equal? (surface-pixel s 5 5) (rgb 0 0 255))
      (error 'doctor "color-filter rasterization failed"))
    (define held-mask (paint-mask-filter effect-paint))
    (define held-image (paint-image-filter effect-paint))
    (unless (and (mask-filter? held-mask) (image-filter? held-image))
      (error 'doctor "filter attachment failed"))
    (skia-close! held-mask)
    (skia-close! held-image)
    (printf "Filters/effects passed; color matrix and mask/image attachments verified\n"))
  (with-skia ([pic (call-with-picture
                    24 24
                    (lambda (c)
                      (with-skia ([p (make-paint #:color 'blue #:antialias? #f)])
                        (draw-rect c 4 4 16 16 p))))]
              [im (picture->image pic 24 24)]
              [s (make-surface 24 24)])
    (draw-picture (surface-canvas s) pic)
    (unless (equal? (surface-pixel s 12 12) (rgb 0 0 255))
      (error 'doctor "picture replay failed"))
    (unless (and (= (image-width im) 24) (= (image-height im) 24))
      (error 'doctor "picture rasterization failed"))
    (printf "Pictures/recording passed; recording, replay, and rasterization verified\n"))
  (with-skia ([p (svg-path->path "M 4 4 L 28 4 L 16 28 Z")])
    (unless (= (path-point-count p) 3)
      (error 'doctor "path point counting failed"))
    (define-values (lx ly) (path-last-point p))
    (unless (and (= lx 16.0) (= ly 28.0))
      (error 'doctor "path last point lookup failed"))
    (with-skia ([q (make-path '((move 0 0) (rline 10 0) (rline 0 10) (close)))]
                [r (make-path)])
      (path-add-rounded-rect! r 2 2 10 8 2 2)
      (path-add-path! r q #:dx 12 #:dy 0)
      (unless (path-convex? q)
        (error 'doctor "relative-path recording failed"))
      (unless (string? (path->svg-path p))
        (error 'doctor "path SVG serialization failed"))
      (printf "Paths/SVG passed; relative commands, SVG conversion, and point queries verified\n")))
  (with-skia ([fm (default-font-manager)])
    (define family-count (font-manager-family-count fm))
    (unless (exact-nonnegative-integer? family-count)
      (error 'doctor "font manager returned an invalid family count"))
    (when (positive? family-count)
      (unless (string? (font-manager-family-name fm 0))
        (error 'doctor "font manager family lookup failed")))
    (define face (font-manager-match-character fm #\A #:languages '("en")))
    (unless face
      (error 'doctor "default font manager could not match U+0041"))
    (call-with-skia-resource
     face
     (lambda (matched-face)
       (with-skia ([font (make-font matched-face #:size 26)]
                   [paint (make-paint #:color 'black)]
                   [surface (make-surface 96 48)])
         (define glyphs (font-text->glyphs font "AB"))
         (unless (= (vector-length glyphs) 2)
           (error 'doctor "font manager matched face did not produce two glyphs"))
         (with-skia ([blob (make-positioned-text-blob font glyphs '((0 0) (28 0)))])
           (define-values (_x _y w h) (text-blob-bounds blob))
           (unless (and (> w 0) (> h 0) (positive? (text-blob-unique-id blob)))
             (error 'doctor "positioned text blob metadata failed"))
           (draw-text-blob (surface-canvas surface) blob 10 34 paint)
           (define pixels (surface->rgba-bytes surface))
           (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
                     (> (bytes-ref pixels i) 0))
             (error 'doctor "positioned text blob rasterization failed"))))))
    (printf "Font manager/text blobs passed; fallback, positioned runs, and replay verified\n"))
  (with-skia ([tf (make-typeface)]
              [font (make-font tf #:size 30)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 140 60)])
    (define run (shape-text sh "office" #:language "en" #:features '("kern=1")))
    (unless (and (positive? (shaped-run-glyph-count run))
                 (= (length (shaped-run-glyphs run))
                    (length (shaped-run-positions run))))
      (error 'doctor "HarfBuzz shaping result failed"))
    (draw-shaped-run (surface-canvas surface) sh run 8 42 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "HarfBuzz shaped text rasterization failed"))
    (printf "HarfBuzz shaping passed; glyph extraction, positioning, and drawing verified\n"))
  (with-skia ([tf (make-typeface)]
              [font (make-font tf #:size 24)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 180 100)])
    (define layout (layout-text sh "alpha beta gamma" #:width 100 #:align 'center))
    (unless (> (text-layout-line-count layout) 1)
      (error 'doctor "text layout did not wrap"))
    (draw-text-layout (surface-canvas surface) layout 10 6 paint)
    (unless (> (text-layout-height layout) 0)
      (error 'doctor "text layout metrics failed"))
    (printf "Paragraph layout passed; wrapping, alignment, metrics, and drawing verified\n"))
  (with-skia ([fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 25)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 260 90)])
    (define mixed (layout-mixed-text sh fm "abc שלום 123" #:width 230))
    (define runs (mixed-text-line-runs (car (mixed-text-layout-lines mixed))))
    (unless (and (for/or ([r (in-list runs)]) (eq? (mixed-text-run-direction r) 'ltr))
                 (for/or ([r (in-list runs)]) (eq? (mixed-text-run-direction r) 'rtl)))
      (error 'doctor "mixed text layout did not create both LTR and RTL runs"))
    (draw-mixed-text-layout (surface-canvas surface) mixed 10 8 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "mixed text layout rasterization failed"))
    (printf "Mixed text layout passed; bidi runs, script segmentation, fallback, and drawing verified\n"))
  (with-skia ([fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 25)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 260 140)])
    (define hyphenated (layout-text sh "alpha-beta-gamma" #:width 95))
    (unless (> (text-layout-line-count hyphenated) 1)
      (error 'doctor "UAX #14 hyphen opportunity did not wrap"))
    (define cjk
      (layout-mixed-text sh fm "世界中文排版測試沒有空格"
                         #:width 100 #:language "zh"))
    (unless (> (mixed-text-layout-line-count cjk) 1)
      (error 'doctor "UAX #14 CJK opportunities did not wrap"))
    (draw-mixed-text-layout (surface-canvas surface) cjk 10 8 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "UAX #14 layout rasterization failed"))
    (printf "Unicode line breaking passed; UAX #14 opportunities and CJK wrapping verified\n"))
  (with-skia ([fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 24)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 300 150)])
    (define justified
      (layout-text sh "alpha beta gamma delta epsilon"
                   #:width 190 #:align 'justify))
    (define j-lines (text-layout-lines justified))
    (unless (and (> (length j-lines) 1)
                 (< (abs (- (text-layout-line-width (car j-lines)) 190.0)) 0.01))
      (error 'doctor "paragraph justification did not fill a wrapped line"))
    (define mixed
      (layout-mixed-text sh fm "Racket שלום world more text"
                         #:width 220 #:align 'justify-all))
    (unless (< (abs (- (mixed-text-line-width
                        (car (mixed-text-layout-lines mixed)))
                       220.0))
               0.01)
      (error 'doctor "mixed-text justification did not fill the measure"))
    (draw-mixed-text-layout (surface-canvas surface) mixed 10 8 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "justified layout rasterization failed"))
    (printf "Paragraph justification passed; justify/justify-all positioning and drawing verified\n"))
  (define line-break-conformance-smoke
    (run-line-break-conformance-port
     (open-input-string "÷ 0041 × 0020 ÷ 0042 ÷\n")))
  (define bidi-conformance-smoke
    (run-bidi-character-conformance-port
     (open-input-string "05D0 0041; 2; 1; 1 2; 1 0\n")))
  (unless (and (= (unicode-conformance-result-passed line-break-conformance-smoke) 1)
               (= (unicode-conformance-result-passed bidi-conformance-smoke) 1)
               (null? (unicode-conformance-result-failures line-break-conformance-smoke))
               (null? (unicode-conformance-result-failures bidi-conformance-smoke)))
    (error 'doctor "Unicode conformance smoke vectors failed"))
  (printf "Unicode conformance harness passed; line-break and bidi smoke vectors verified\n")
  (with-skia ([fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 24)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 300 170)])
    (define overridden
      (layout-mixed-text
       sh fm
       (string-append (string #\u202E)
                      "alpha beta gamma delta epsilon"
                      (string #\u202C))
       #:width 160))
    (unless (and (> (mixed-text-layout-line-count overridden) 1)
                 (for/and ([line (in-list (mixed-text-layout-lines overridden))])
                   (for/and ([run (in-list (mixed-text-line-runs line))]
                             #:when (regexp-match? #rx"[A-Za-z]"
                                                   (mixed-text-run-text run)))
                     (eq? (mixed-text-run-direction run) 'rtl))))
      (error 'doctor "explicit RLO did not survive wrapped mixed layout"))
    (define isolated
      (layout-mixed-text
       sh fm
       (string-append "before " (string #\u2067) "שלום"
                      (string #\u2069) " after")
       #:width 260))
    (unless (and (eq? (mixed-text-line-direction
                       (car (mixed-text-layout-lines isolated)))
                      'ltr)
                 (for/or ([run (in-list
                                (mixed-text-line-runs
                                 (car (mixed-text-layout-lines isolated))))])
                   (eq? (mixed-text-run-direction run) 'rtl)))
      (error 'doctor "explicit isolate did not preserve outer paragraph direction"))
    (draw-mixed-text-layout (surface-canvas surface) overridden 10 8 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "explicit-bidi rasterization failed"))
    (printf "Explicit bidi controls passed; embeddings, overrides, isolates, and wrapped scopes verified\n"))
  (with-skia ([tf (make-typeface)]
              [font (make-font tf #:size 24)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 220 120)])
    (define alpha-width
      (text-layout-line-width
       (car (text-layout-lines (layout-text sh "alpha")))))
    (define segmented
      (layout-text sh "alphabeta" #:width (+ alpha-width 1.0)
                   #:break-provider (lambda (paragraph language) '(5))))
    (unless (equal? (map text-layout-line-text (text-layout-lines segmented))
                    '("alpha" "beta"))
      (error 'doctor "external break provider did not segment text"))
    (define alpha-hyphen-width
      (text-layout-line-width
       (car (text-layout-lines (layout-text sh "alpha-")))))
    (define hyphenated
      (layout-text
       sh "alphabeta" #:width (+ alpha-hyphen-width 1.0)
       #:break-provider
       (lambda (paragraph language)
         (list (make-layout-break-opportunity 5 "-")))))
    (unless (equal? (map text-layout-line-text (text-layout-lines hyphenated))
                    '("alpha-" "beta"))
      (error 'doctor "discretionary break insertion was not rendered"))
    (draw-text-layout (surface-canvas surface) hyphenated 8 8 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "break-provider rasterization failed"))
    (printf "Break providers passed; external segmentation and discretionary hyphen insertion verified\n"))
  (with-skia ([fm (default-font-manager)]
              [tf (make-typeface)]
              [font (make-font tf #:size 27)]
              [sh (make-shaper font)]
              [paint (make-paint #:color 'black)]
              [surface (make-surface 360 150)])
    (define cjk-natural
      (layout-mixed-text sh fm "世界中文" #:language "zh"))
    (define cjk-width
      (mixed-text-line-width (car (mixed-text-layout-lines cjk-natural))))
    (define cjk-target (+ cjk-width 70.0))
    (define cjk
      (layout-mixed-text sh fm "世界中文" #:width cjk-target
                         #:align 'justify-all #:language "zh"))
    (unless (< (abs (- (mixed-text-line-width
                        (car (mixed-text-layout-lines cjk)))
                       cjk-target))
               0.01)
      (error 'doctor "CJK inter-character justification did not fill the measure"))
    (define arabic-natural
      (layout-mixed-text sh fm "مرحبابكم" #:direction 'rtl #:language "ar"))
    (define arabic-line (car (mixed-text-layout-lines arabic-natural)))
    (define arabic-glyphs
      (for/sum ([r (in-list (mixed-text-line-runs arabic-line))])
        (shaped-run-glyph-count (mixed-text-run-shaped-run r))))
    (define arabic-target (+ (mixed-text-line-width arabic-line) 65.0))
    (define arabic
      (layout-mixed-text sh fm "مرحبابكم" #:width arabic-target
                         #:align 'justify-all #:direction 'rtl #:language "ar"))
    (define arabic-justified-line (car (mixed-text-layout-lines arabic)))
    (define arabic-justified-glyphs
      (for/sum ([r (in-list (mixed-text-line-runs arabic-justified-line))])
        (shaped-run-glyph-count (mixed-text-run-shaped-run r))))
    (unless (and (< (abs (- (mixed-text-line-width arabic-justified-line)
                            arabic-target))
                    0.01)
                 (> arabic-justified-glyphs arabic-glyphs))
      (error 'doctor "Arabic kashida justification did not add shaping material"))
    (draw-mixed-text-layout (surface-canvas surface) cjk 10 8 paint)
    (draw-mixed-text-layout (surface-canvas surface) arabic 10 70 paint)
    (define pixels (surface->rgba-bytes surface))
    (unless (for/or ([i (in-range 3 (bytes-length pixels) 4)])
              (> (bytes-ref pixels i) 0))
      (error 'doctor "script-aware justification rasterization failed"))
    (printf "Script-aware justification passed; CJK inter-character and Arabic kashida expansion verified\n"))
  (with-skia ([srgb (make-srgb-color-space)]
              [linear (make-linear-srgb-color-space)]
              [surface (make-surface 6 6 #:background "#808080" #:color-space srgb)]
              [im (rgba-bytes->image 1 1 (bytes 128 64 32 255) #:color-space srgb)])
    (unless (and (color-space-srgb? srgb)
                 (color-space-linear-gamma? linear)
                 (not (color-space=? srgb linear)))
      (error 'doctor "built-in color spaces did not report expected gamma metadata"))
    (define icc (color-space->icc-bytes srgb))
    (unless (> (bytes-length icc) 100)
      (error 'doctor "sRGB color space did not produce an ICC profile"))
    (with-skia ([round (color-space-from-icc-bytes icc)]
                [surface-cs (surface-color-space surface)]
                [image-cs (image-color-space im)])
      (unless (and (color-space-gamma-close-to-srgb? round)
                   (color-space=? surface-cs srgb)
                   (color-space=? image-cs srgb))
        (error 'doctor "ICC or tagged color-space round-trip failed")))
    (define linear-pixels (image->rgba-bytes im #:color-space linear))
    (unless (and (< (bytes-ref linear-pixels 0) 128)
                 (< (bytes-ref linear-pixels 1) 64)
                 (= (bytes-ref linear-pixels 3) 255))
      (error 'doctor "sRGB-to-linear pixel conversion failed"))
    (printf "Color management passed; sRGB/linear tagging, ICC round-trip, and conversion verified\n"))
)
