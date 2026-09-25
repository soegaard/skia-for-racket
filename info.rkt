#lang info
(define collection "skia")
(define version "0.22.0")
(define pkg-desc "Experimental standalone CPU Skia drawing and multi-page PDF / single-viewport SVG output, animated image codecs and encoded-orientation normalization, color-space and ICC color management, script-aware CJK/Arabic justification, pluggable segmentation and hyphenation hooks, full Unicode bidi controls, Unicode conformance tooling, paragraph justification, Unicode line breaking, mixed-script/bidi text layout, paragraph text layout, HarfBuzz shaping, font management/text blobs, expanded paths/SVG geometry, filters, pictures/recording, vector effects, text, shaders, and image codecs through the SkiaSharp C ABI")
(define deps '(("base" #:version "8.7") "draw-lib"))
(define build-deps '("rackunit-lib"))
(define license 'MIT)
(define test-omit-paths '("examples" "tools" "native"))
(define compile-omit-paths '("native"))
