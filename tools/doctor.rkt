#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt" "../private/harfbuzz-types.rkt")
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
    (printf "HarfBuzz shaping passed; glyph extraction, positioning, and drawing verified\n")))
