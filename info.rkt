#lang info
(define collection "skia")
(define version "0.14.0")
(define pkg-desc "Experimental standalone CPU Skia drawing, paragraph justification, Unicode line breaking, mixed-script/bidi text layout, paragraph text layout, HarfBuzz shaping, font management/text blobs, expanded paths/SVG geometry, filters, pictures/recording, vector effects, text, shaders, and image codecs through the SkiaSharp C ABI")
(define deps '(("base" #:version "8.7") "draw-lib"))
(define build-deps '("rackunit-lib"))
(define license 'MIT)
(define test-omit-paths '("examples" "tools" "native"))
(define compile-omit-paths '("native"))
