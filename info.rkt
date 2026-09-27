#lang info
(define collection "skia")
(define version "0.35.0")
(define pkg-desc "Experimental standalone CPU Skia drawing, portable marker geometry and cropped image-grid/atlas placements, capture-once bounded output groups with backend-aware native/raster choice, trusted native SKP persistence, picture metadata and shaders, optional R-tree recording, homogeneous 3x3 and retained-depth 4x4 matrices with scoped perspective and explicit document fallback, integer regions and triangle meshes, image lattice/nine-patch, atlas and Coons patches, canvas primitives and scoped compositing layers, conservative PDF/SVG output auditing and strict publication policies, SkSL runtime shaders/color filters/blenders, PDF/SVG hyperlinks and named destinations, custom RGB spaces and ICC-aware encoded output, advanced filter graphs and crop semantics, path inspection and affine transforms, and multi-page PDF / single-viewport SVG output with shared physical-page, text-outline, and raster-fallback policies, animated image codecs and encoded-orientation normalization, color-space and ICC color management, script-aware CJK/Arabic justification, pluggable segmentation and hyphenation hooks, full Unicode bidi controls, Unicode conformance tooling, paragraph justification, Unicode line breaking, mixed-script/bidi text layout, paragraph text layout, HarfBuzz shaping, font management/text blobs, expanded paths/SVG geometry, filters, pictures/recording, vector effects, text, shaders, and image codecs through the SkiaSharp C ABI")
(define deps '(("base" #:version "8.7") "draw-lib"))
(define build-deps '("rackunit-lib"))
(define license 'MIT)
(define test-omit-paths '("examples" "tools" "native"))
(define compile-omit-paths '("native"))
