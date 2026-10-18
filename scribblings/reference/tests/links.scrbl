#lang scribble/manual

@(require (for-label racket/base skia
                     (prefix-in pictures: skia/pictures)
                     (prefix-in output: skia/output)
                     (prefix-in annotations: skia/annotations)
                     (prefix-in color: skia/color)
                     (prefix-in color-space: skia/color-space)
                     (prefix-in color4f: skia/color4f)
                     (prefix-in float-colors: skia/float-colors)
                     (prefix-in image-info: skia/image-info)
                     (prefix-in geometry: skia/geometry)
                     (prefix-in effects: skia/effects)
                     (prefix-in color-filters: skia/color-filters)
                     (prefix-in runtime-effects: skia/runtime-effects)
                     (prefix-in matrix: skia/matrix)
                     (prefix-in typefaces: skia/typefaces)
                     (prefix-in fonts: skia/fonts)
                     (prefix-in text-blobs: skia/text-blobs)
                     (prefix-in geometry-primitives: skia/geometry-primitives)))

@(require (for-label
           (prefix-in streams: skia/streams)
           (prefix-in file-streams: skia/file-streams)
           (prefix-in stream-inputs: skia/stream-inputs)
           (prefix-in live-streams: skia/live-streams)
           (prefix-in codec-queries: skia/codec-queries)
           (prefix-in codec-scanlines: skia/codec-scanlines)
           (prefix-in codec-incremental: skia/codec-incremental)
           (prefix-in raster-buffers: skia/raster-buffers)
))

@(require (for-label
           (prefix-in advanced-layers: skia/advanced-layers)
           (prefix-in canvas-matrix: skia/canvas-matrix)
           (prefix-in canvas-primitives: skia/canvas-primitives)
           (prefix-in drawables: skia/drawables)
           (prefix-in layer-options: skia/layer-options)
           (prefix-in portable-drawing: skia/portable-drawing)
           (prefix-in projective-matrix: skia/projective-matrix)
           (prefix-in specialized-canvases: skia/specialized-canvases)
))

@(require (for-label
           (prefix-in bitmap: skia/bitmap)
           (prefix-in graphics: skia/graphics)
           (prefix-in image-operations: skia/image-operations)
           (prefix-in native-capabilities: skia/native-capabilities)
           (prefix-in output-audit: skia/output-audit)
           (prefix-in output-groups: skia/output-groups)
           (prefix-in output-policy: skia/output-policy)
           (prefix-in surface-properties: skia/surface-properties)
))

@(require (for-label
           (prefix-in gpu: skia/gpu)
           (prefix-in gpu-context-options: skia/gpu-context-options)))

@(require (for-label (prefix-in gpu-diagnostics: skia/gpu-diagnostics)))

@(require (for-label (prefix-in canvas: skia/canvas)
                     (prefix-in gpu-gui: skia/gpu-gui)
                     (prefix-in gpu-canvas: skia/gpu-canvas)
                     (prefix-in render-canvas: skia/render-canvas)))

@(require (for-label (prefix-in dc: skia/dc)
                     (prefix-in dc-output: skia/dc-output)
                     (prefix-in gpu-dc: skia/gpu-dc)))

@(require (for-label (prefix-in pict: skia/pict)))
@(require (for-label (prefix-in racket-draw: skia/racket-draw)))


@(require (for-label
           (prefix-in gpu-egl: skia/gpu-egl)
           (prefix-in gpu-racket-gl: skia/gpu-racket-gl)
           (prefix-in gpu-gl-interop: skia/gpu-gl-interop)
           (prefix-in gpu-interop: skia/gpu-interop)
           (prefix-in gpu-output: skia/gpu-output)
           (prefix-in unsafe-gpu-metal: skia/unsafe/gpu-metal)
           (prefix-in unsafe-gpu-d3d12: skia/unsafe/gpu-d3d12)))

@title{Reference Binding Links}

The following links exercise the public bindings documented by the Reference.

@racket[skia-resource?]

@racket[skia-closed?]

@racket[skia-close!]

@racket[call-with-skia-resource]

@racket[with-skia]

@racket[current-skia-byte-limit]

@racket[surface?]

@racket[canvas?]

@racket[make-surface]

@racket[surface-canvas]

@racket[surface-width]

@racket[surface-height]

@racket[surface-backend]

@racket[surface-color-space]

@racket[surface-snapshot]

@racket[surface->rgba-bytes]

@racket[surface-pixel]

@racket[canvas-clear!]

@racket[canvas-execution-backend]

@racket[canvas-save!]

@racket[canvas-save-count]

@racket[canvas-restore!]

@racket[canvas-restore-to-count!]

@racket[call-with-canvas-state]

@racket[with-canvas-state]

@racket[canvas-translate!]

@racket[canvas-scale!]

@racket[canvas-rotate!]

@racket[canvas-rotate-radians!]

@racket[canvas-skew!]

@racket[canvas-reset-transform!]

@racket[canvas-transform]

@racket[canvas-set-transform!]

@racket[canvas-concat!]

@racket[canvas-clip-rect!]

@racket[canvas-clip-path!]

@racket[color?]

@racket[rgba]

@racket[struct:rgba]

@racket[rgba?]

@racket[rgba-red]

@racket[rgba-green]

@racket[rgba-blue]

@racket[rgba-alpha]

@racket[rgb]

@racket[color->rgba]

@racket[color->argb]

@racket[color-space?]

@racket[make-srgb-color-space]

@racket[make-linear-srgb-color-space]

@racket[color-space=?]

@racket[color-space-srgb?]

@racket[color-space-linear-gamma?]

@racket[paint?]

@racket[shader?]

@racket[path-effect?]

@racket[color-filter?]

@racket[mask-filter?]

@racket[image-filter?]

@racket[make-paint]

@racket[paint-copy]

@racket[paint-color]

@racket[paint-shader]

@racket[paint-path-effect]

@racket[paint-color-filter]

@racket[paint-mask-filter]

@racket[paint-image-filter]

@racket[paint-set-color!]

@racket[paint-set-style!]

@racket[paint-set-stroke-width!]

@racket[paint-set-antialias!]

@racket[paint-set-cap!]

@racket[paint-set-join!]

@racket[paint-set-miter-limit!]

@racket[paint-set-blend-mode!]

@racket[paint-set-shader!]

@racket[paint-set-path-effect!]

@racket[paint-set-color-filter!]

@racket[paint-set-mask-filter!]

@racket[paint-set-image-filter!]

@racket[paint-style]

@racket[paint-stroke-width]

@racket[paint-cap]

@racket[paint-join]

@racket[paint-miter-limit]

@racket[paint-antialias?]

@racket[paint-dither?]

@racket[paint-set-dither!]

@racket[paint-blend-mode-or-src-over]

@racket[paint-reset!]

@racket[paint->fill-path]

@racket[make-color-shader]

@racket[make-linear-gradient-shader]

@racket[make-radial-gradient-shader]

@racket[make-sweep-gradient-shader]

@racket[make-two-point-conical-gradient-shader]

@racket[make-image-shader]

@racket[make-blend-shader]

@racket[shader-with-local-matrix]

@racket[draw-rect]

@racket[draw-paint]

@racket[draw-line]

@racket[draw-rounded-rect]

@racket[draw-circle]

@racket[draw-oval]

@racket[draw-path]

@racket[draw-polygon]

@racket[skia-path?]

@racket[make-path]

@racket[path-copy]

@racket[path-fill-rule]

@racket[path-set-fill-rule!]

@racket[path-reset!]

@racket[path-move-to!]

@racket[path-rmove-to!]

@racket[path-line-to!]

@racket[path-rline-to!]

@racket[path-quad-to!]

@racket[path-rquad-to!]

@racket[path-conic-to!]

@racket[path-rconic-to!]

@racket[path-cubic-to!]

@racket[path-rcubic-to!]

@racket[path-close!]

@racket[path-add-rect!]

@racket[path-add-rounded-rect!]

@racket[path-add-oval!]

@racket[path-add-circle!]

@racket[path-add-path!]

@racket[path-add-reversed-path!]

@racket[path-point-count]

@racket[path-point-ref]

@racket[path-points]

@racket[path-last-point]

@racket[path-bounds]

@racket[path-tight-bounds]

@racket[path-contains?]

@racket[path-convex?]

@racket[path-transform]

@racket[path-transform!]

@racket[svg-path->path]

@racket[path->svg-path]

@racket[path->commands]

@racket[path-segments]

@racket[in-path-segments]

@racket[path-segment?]

@racket[path-segment-verb]

@racket[path-segment-points]

@racket[path-segment-conic-weight]

@racket[path-segment-closing-line?]

@racket[path-contours]

@racket[path-contour?]

@racket[path-contour-segments]

@racket[path-contour-closed?]

@racket[path-op]

@racket[path-union]

@racket[path-intersect]

@racket[path-difference]

@racket[path-xor]

@racket[path-reverse-difference]

@racket[path-simplify]

@racket[path-as-winding]

@racket[path-measure?]

@racket[make-path-measure]

@racket[path-measure-set-path!]

@racket[path-measure-length]

@racket[path-measure-closed?]

@racket[path-measure-next-contour!]

@racket[path-measure-position+tangent]

@racket[path-measure-segment]

@racket[path-measure-matrix]

@racket[matrix?]

@racket[make-matrix]

@racket[matrix-identity]

@racket[matrix-xx]

@racket[matrix-yx]

@racket[matrix-xy]

@racket[matrix-yy]

@racket[matrix-x0]

@racket[matrix-y0]

@racket[matrix->vector]

@racket[vector->matrix]

@racket[matrix-translate]

@racket[matrix-scale]

@racket[matrix-rotate]

@racket[matrix-rotate-degrees]

@racket[matrix-skew]

@racket[matrix-compose]

@racket[matrix-invert]

@racket[matrix-map-point]

@racket[matrix-map-vector]

@racket[matrix-map-rect]

@racket[image?]

@racket[rgba-bytes->image]

@racket[image-from-bytes]

@racket[image-from-file]

@racket[image-width]

@racket[image-height]

@racket[image-color-type]

@racket[image-alpha-type]

@racket[image-color-space]

@racket[image-original-encoded-bytes]

@racket[image->rgba-bytes]

@racket[image-subset]

@racket[draw-image]

@racket[draw-image-rect]

@racket[draw-image-subrect]

@racket[save-png]

@racket[surface->png-bytes]

@racket[image->png-bytes]

@racket[image->jpeg-bytes]

@racket[image->webp-bytes]

@racket[image->encoded-bytes]

@racket[save-image]

@section{skia/color re-exports}

@racket[color:color?]

@racket[color:rgba]

@racket[color:struct:rgba]

@racket[color:rgba?]

@racket[color:rgba-red]

@racket[color:rgba-green]

@racket[color:rgba-blue]

@racket[color:rgba-alpha]

@racket[color:rgb]

@racket[color:color->rgba]

@racket[color:color->argb]

@section{skia/geometry re-exports}

@racket[geometry:paint-style]

@racket[geometry:paint-stroke-width]

@racket[geometry:paint-cap]

@racket[geometry:paint-join]

@racket[geometry:paint-miter-limit]

@racket[geometry:paint-antialias?]

@racket[geometry:paint-dither?]

@racket[geometry:paint-set-dither!]

@racket[geometry:paint-blend-mode-or-src-over]

@racket[geometry:paint-reset!]

@racket[geometry:paint->fill-path]

@section{skia/matrix re-exports}

@racket[matrix:matrix?]

@racket[matrix:make-matrix]

@racket[matrix:matrix-identity]

@racket[matrix:matrix-xx]

@racket[matrix:matrix-yx]

@racket[matrix:matrix-xy]

@racket[matrix:matrix-yy]

@racket[matrix:matrix-x0]

@racket[matrix:matrix-y0]

@racket[matrix:matrix->vector]

@racket[matrix:vector->matrix]

@racket[matrix:matrix-translate]

@racket[matrix:matrix-scale]

@racket[matrix:matrix-rotate]

@racket[matrix:matrix-rotate-degrees]

@racket[matrix:matrix-skew]

@racket[matrix:matrix-compose]

@racket[matrix:matrix-invert]

@racket[matrix:matrix-map-point]

@racket[matrix:matrix-map-vector]

@racket[matrix:matrix-map-rect]

The following links check the current and retained encoding chapter tags.

@seclink["skia-png" #:doc '(lib "skia/scribblings/reference/reference.scrbl")]{
Image Encoding (legacy tag)}

@seclink["skia-encoding" #:doc '(lib "skia/scribblings/reference/reference.scrbl")]{
Image Encoding (current tag)}

The following links cover the font and text interfaces.

@racket[font-manager?]

@racket[make-font-manager]

@racket[default-font-manager]

@racket[font-manager-family-count]

@racket[font-manager-family-name]

@racket[font-manager-families]

@racket[font-manager-match-family]

@racket[font-manager-match-character]

@racket[typeface?]

@racket[make-typeface]

@racket[typeface-from-family]

@racket[typeface-from-file]

@racket[typeface-family-name]

@racket[typeface-weight]

@racket[typeface-width]

@racket[typeface-slant]

@racket[font-style?]

@racket[typefaces:font-style?]

@racket[make-font-style]

@racket[typefaces:make-font-style]

@racket[font-style-weight]

@racket[typefaces:font-style-weight]

@racket[font-style-width]

@racket[typefaces:font-style-width]

@racket[font-style-slant]

@racket[typefaces:font-style-slant]

@racket[font-style-set?]

@racket[typefaces:font-style-set?]

@racket[make-empty-font-style-set]

@racket[typefaces:make-empty-font-style-set]

@racket[font-manager-style-set]

@racket[typefaces:font-manager-style-set]

@racket[font-manager-style-set-ref]

@racket[typefaces:font-manager-style-set-ref]

@racket[font-style-set-count]

@racket[typefaces:font-style-set-count]

@racket[font-style-set-ref]

@racket[typefaces:font-style-set-ref]

@racket[font-style-set-styles]

@racket[typefaces:font-style-set-styles]

@racket[font-style-entry?]

@racket[typefaces:font-style-entry?]

@racket[font-style-entry-index]

@racket[typefaces:font-style-entry-index]

@racket[font-style-entry-name]

@racket[typefaces:font-style-entry-name]

@racket[font-style-entry-style]

@racket[typefaces:font-style-entry-style]

@racket[font-style-set-typeface]

@racket[typefaces:font-style-set-typeface]

@racket[font-style-set-match]

@racket[typefaces:font-style-set-match]

@racket[typeface-style]

@racket[typefaces:typeface-style]

@racket[typeface-from-bytes]

@racket[typefaces:typeface-from-bytes]

@racket[font-manager-typeface-from-bytes]

@racket[typefaces:font-manager-typeface-from-bytes]

@racket[typeface-postscript-name]

@racket[typefaces:typeface-postscript-name]

@racket[typeface-fixed-pitch?]

@racket[typefaces:typeface-fixed-pitch?]

@racket[typeface-glyph-count]

@racket[typefaces:typeface-glyph-count]

@racket[typeface-units-per-em]

@racket[typefaces:typeface-units-per-em]

@racket[font-table-tag]

@racket[typefaces:font-table-tag]

@racket[font-table-tag->bytes]

@racket[typefaces:font-table-tag->bytes]

@racket[typeface-table-tags]

@racket[typefaces:typeface-table-tags]

@racket[typeface-table-size]

@racket[typefaces:typeface-table-size]

@racket[typeface-table-bytes]

@racket[typefaces:typeface-table-bytes]

@racket[typeface-kerning-pair-adjustments]

@racket[typefaces:typeface-kerning-pair-adjustments]

@racket[typeface->font-bytes]

@racket[typefaces:typeface->font-bytes]

@racket[font?]

@racket[make-font]

@racket[font-size]

@racket[font-set-size!]

@racket[font-scale-x]

@racket[font-set-scale-x!]

@racket[font-skew-x]

@racket[font-set-skew-x!]

@racket[font-edging]

@racket[font-set-edging!]

@racket[font-hinting]

@racket[font-set-hinting!]

@racket[font-subpixel?]

@racket[font-set-subpixel!]

@racket[font-linear-metrics?]

@racket[font-set-linear-metrics!]

@racket[font-embolden?]

@racket[font-set-embolden!]

@racket[font-get-metrics]

@racket[font-metrics?]

@racket[font-metrics-top]

@racket[font-metrics-ascent]

@racket[font-metrics-descent]

@racket[font-metrics-bottom]

@racket[font-metrics-leading]

@racket[font-metrics-average-character-width]

@racket[font-metrics-max-character-width]

@racket[font-metrics-x-min]

@racket[font-metrics-x-max]

@racket[font-metrics-x-height]

@racket[font-metrics-cap-height]

@racket[font-metrics-underline-thickness]

@racket[font-metrics-underline-position]

@racket[font-metrics-strikeout-thickness]

@racket[font-metrics-strikeout-position]

@racket[font-metrics-spacing]

@racket[draw-simple-text]

@racket[measure-simple-text]

@racket[simple-text-bounds]

@racket[font-char->glyph]

@racket[font-text->glyphs]

@racket[font-glyph-path]

@racket[simple-text-path]

@racket[font-embedded-bitmaps?]

@racket[fonts:font-embedded-bitmaps?]

@racket[font-set-embedded-bitmaps!]

@racket[fonts:font-set-embedded-bitmaps!]

@racket[font-force-auto-hinting?]

@racket[fonts:font-force-auto-hinting?]

@racket[font-set-force-auto-hinting!]

@racket[fonts:font-set-force-auto-hinting!]

@racket[font-baseline-snap?]

@racket[fonts:font-baseline-snap?]

@racket[font-set-baseline-snap!]

@racket[fonts:font-set-baseline-snap!]

@racket[font-typeface]

@racket[fonts:font-typeface]

@racket[font-set-typeface!]

@racket[fonts:font-set-typeface!]

@racket[font-glyph-widths]

@racket[fonts:font-glyph-widths]

@racket[font-glyph-bounds]

@racket[fonts:font-glyph-bounds]

@racket[font-glyph-widths+bounds]

@racket[fonts:font-glyph-widths+bounds]

@racket[font-glyph-positions]

@racket[fonts:font-glyph-positions]

@racket[font-glyph-x-positions]

@racket[fonts:font-glyph-x-positions]

@racket[font-glyph-paths]

@racket[fonts:font-glyph-paths]

@racket[font-break-text]

@racket[fonts:font-break-text]

@racket[shaper?]

@racket[make-shaper]

@racket[shape-text]

@racket[shaped-run?]

@racket[shaped-run-glyphs]

@racket[shaped-run-clusters]

@racket[shaped-run-positions]

@racket[shaped-run-advance-x]

@racket[shaped-run-advance-y]

@racket[shaped-run-glyph-count]

@racket[shaped-run->text-blob]

@racket[draw-shaped-run]

@racket[draw-shaped-text]

@racket[shaped-run->path]

@racket[text-blob?]

@racket[make-positioned-text-blob]

@racket[text-blob-bounds]

@racket[text-blob-unique-id]

@racket[draw-text-blob]

@racket[text-blob->path]

@racket[layout-text]

@racket[draw-text-layout]

@racket[text-layout?]

@racket[text-layout-lines]

@racket[text-layout-width]

@racket[text-layout-height]

@racket[text-layout-line-height]

@racket[text-layout-line-count]

@racket[text-layout-line?]

@racket[text-layout-line-text]

@racket[text-layout-line-run]

@racket[text-layout-line-origin-x]

@racket[text-layout-line-baseline]

@racket[text-layout-line-width]

@racket[text-layout-line-direction]

@racket[layout-break-opportunity?]

@racket[make-layout-break-opportunity]

@racket[layout-break-opportunity-index]

@racket[layout-break-opportunity-insert]

@racket[layout-mixed-text]

@racket[draw-mixed-text-layout]

@racket[mixed-text-layout?]

@racket[mixed-text-layout-lines]

@racket[mixed-text-layout-width]

@racket[mixed-text-layout-height]

@racket[mixed-text-layout-line-height]

@racket[mixed-text-layout-line-count]

@racket[mixed-text-line?]

@racket[mixed-text-line-text]

@racket[mixed-text-line-runs]

@racket[mixed-text-line-origin-x]

@racket[mixed-text-line-baseline]

@racket[mixed-text-line-width]

@racket[mixed-text-line-direction]

@racket[mixed-text-run?]

@racket[mixed-text-run-text]

@racket[mixed-text-run-shaped-run]

@racket[mixed-text-run-origin-x]

@racket[mixed-text-run-width]

@racket[mixed-text-run-direction]

@racket[mixed-text-run-level]

@racket[mixed-text-run-script]

@racket[mixed-text-run-family]

@racket[text-blob-builder?]

@racket[text-blobs:text-blob-builder?]

@racket[make-text-blob-builder]

@racket[text-blobs:make-text-blob-builder]

@racket[text-blob-builder-run-count]

@racket[text-blobs:text-blob-builder-run-count]

@racket[text-blob-builder-add-run!]

@racket[text-blobs:text-blob-builder-add-run!]

@racket[text-blob-builder-add-horizontal-run!]

@racket[text-blobs:text-blob-builder-add-horizontal-run!]

@racket[text-blob-builder-add-positioned-run!]

@racket[text-blobs:text-blob-builder-add-positioned-run!]

@racket[text-blob-builder-add-transformed-run!]

@racket[text-blobs:text-blob-builder-add-transformed-run!]

@racket[text-blob-builder-add-shaped-run!]

@racket[text-blobs:text-blob-builder-add-shaped-run!]

@racket[text-blob-builder-finish!]

@racket[text-blobs:text-blob-builder-finish!]

@racket[text-blob-run-count]

@racket[text-blobs:text-blob-run-count]

@racket[text-blob-runs]

@racket[text-blobs:text-blob-runs]

@racket[text-blob-run-font]

@racket[text-blobs:text-blob-run-font]

@racket[text-blob-intercepts]

@racket[text-blobs:text-blob-intercepts]

@racket[text-run-info?]

@racket[text-blobs:text-run-info?]

@racket[text-run-info-positioning]

@racket[text-blobs:text-run-info-positioning]

@racket[text-run-info-glyphs]

@racket[text-blobs:text-run-info-glyphs]

@racket[text-run-info-positions]

@racket[text-blobs:text-run-info-positions]

@racket[text-run-info-transforms]

@racket[text-blobs:text-run-info-transforms]

@racket[text-run-info-utf8]

@racket[text-blobs:text-run-info-utf8]

@racket[text-run-info-clusters]

@racket[text-blobs:text-run-info-clusters]

@racket[positioned-glyphs->path]

@racket[text-blobs:positioned-glyphs->path]

@racket[shaped-run->text-blob/on-path]

@racket[text-blobs:shaped-run->text-blob/on-path]

@racket[draw-shaped-run/on-path]

@racket[text-blobs:draw-shaped-run/on-path]

@racket[atlas-transform?]

@racket[geometry-primitives:atlas-transform?]

@racket[make-atlas-transform]

@racket[geometry-primitives:make-atlas-transform]

@racket[atlas-transform-coefficients]

@racket[geometry-primitives:atlas-transform-coefficients]

@section{Effects and Filters}

@racket[make-dash-path-effect]
@racket[make-corner-path-effect]
@racket[make-discrete-path-effect]
@racket[make-trim-path-effect]
@racket[make-compose-path-effect]
@racket[make-sum-path-effect]
@racket[make-1d-path-effect]
@racket[effects:make-1d-path-effect]
@racket[make-2d-line-path-effect]
@racket[effects:make-2d-line-path-effect]
@racket[make-2d-path-effect]
@racket[effects:make-2d-path-effect]
@racket[make-blur-mask-filter]
@racket[make-table-mask-filter]
@racket[effects:make-table-mask-filter]
@racket[make-gamma-mask-filter]
@racket[effects:make-gamma-mask-filter]
@racket[make-clip-mask-filter]
@racket[effects:make-clip-mask-filter]
@racket[make-shader-mask-filter]
@racket[effects:make-shader-mask-filter]
@racket[make-color-matrix-filter]
@racket[make-blend-color-filter]
@racket[make-compose-color-filter]
@racket[make-hsla-matrix-filter]
@racket[color-filters:make-hsla-matrix-filter]
@racket[make-linear-to-srgb-gamma-color-filter]
@racket[color-filters:make-linear-to-srgb-gamma-color-filter]
@racket[make-srgb-to-linear-gamma-color-filter]
@racket[color-filters:make-srgb-to-linear-gamma-color-filter]
@racket[make-lerp-color-filter]
@racket[color-filters:make-lerp-color-filter]
@racket[make-luma-color-filter]
@racket[color-filters:make-luma-color-filter]
@racket[make-high-contrast-color-filter]
@racket[color-filters:make-high-contrast-color-filter]
@racket[make-table-color-filter]
@racket[color-filters:make-table-color-filter]
@racket[make-table-argb-color-filter]
@racket[color-filters:make-table-argb-color-filter]
@racket[make-lighting-color-filter]
@racket[color-filters:make-lighting-color-filter]
@racket[make-blur-image-filter]
@racket[make-drop-shadow-image-filter]
@racket[make-drop-shadow-only-image-filter]
@racket[make-color-filter-image-filter]
@racket[make-compose-image-filter]
@racket[make-crop-image-filter]
@racket[make-offset-image-filter]
@racket[make-merge-image-filter]
@racket[make-blend-image-filter]
@racket[make-arithmetic-image-filter]
@racket[make-dilate-image-filter]
@racket[make-erode-image-filter]
@racket[make-displacement-map-image-filter]
@racket[make-matrix-convolution-image-filter]
@racket[make-matrix-transform-image-filter]
@racket[make-image-source-filter]
@racket[make-shader-image-filter]
@racket[make-tile-image-filter]
@racket[make-magnifier-image-filter]
@racket[make-distant-lit-diffuse-image-filter]
@racket[make-point-lit-diffuse-image-filter]
@racket[make-spot-lit-diffuse-image-filter]
@racket[make-distant-lit-specular-image-filter]
@racket[make-point-lit-specular-image-filter]
@racket[make-spot-lit-specular-image-filter]
@racket[make-blender-image-filter]
@racket[effects:make-blender-image-filter]
@racket[runtime-effect?]
@racket[runtime-effects:runtime-effect?]
@racket[make-runtime-effect]
@racket[runtime-effects:make-runtime-effect]
@racket[runtime-effect-kind]
@racket[runtime-effects:runtime-effect-kind]
@racket[runtime-effect-source]
@racket[runtime-effects:runtime-effect-source]
@racket[runtime-effect-uniform-byte-size]
@racket[runtime-effects:runtime-effect-uniform-byte-size]
@racket[runtime-effect-uniforms]
@racket[runtime-effects:runtime-effect-uniforms]
@racket[runtime-effect-children]
@racket[runtime-effects:runtime-effect-children]
@racket[runtime-effect-uniform-bytes]
@racket[runtime-effects:runtime-effect-uniform-bytes]
@racket[runtime-effect->shader]
@racket[runtime-effects:runtime-effect->shader]
@racket[runtime-effect->color-filter]
@racket[runtime-effects:runtime-effect->color-filter]
@racket[runtime-effect->blender]
@racket[runtime-effects:runtime-effect->blender]
@racket[runtime-uniform?]
@racket[runtime-effects:runtime-uniform?]
@racket[runtime-uniform-name]
@racket[runtime-effects:runtime-uniform-name]
@racket[runtime-uniform-offset]
@racket[runtime-effects:runtime-uniform-offset]
@racket[runtime-uniform-type]
@racket[runtime-effects:runtime-uniform-type]
@racket[runtime-uniform-count]
@racket[runtime-effects:runtime-uniform-count]
@racket[runtime-uniform-byte-size]
@racket[runtime-effects:runtime-uniform-byte-size]
@racket[runtime-uniform-array?]
@racket[runtime-effects:runtime-uniform-array?]
@racket[runtime-uniform-color?]
@racket[runtime-effects:runtime-uniform-color?]
@racket[runtime-uniform-half-precision?]
@racket[runtime-effects:runtime-uniform-half-precision?]
@racket[runtime-child?]
@racket[runtime-effects:runtime-child?]
@racket[runtime-child-name]
@racket[runtime-effects:runtime-child-name]
@racket[runtime-child-kind]
@racket[runtime-effects:runtime-child-kind]
@racket[runtime-child-index]
@racket[runtime-effects:runtime-child-index]
@racket[exn:fail:skia-sksl?]
@racket[runtime-effects:exn:fail:skia-sksl?]
@racket[exn:fail:skia-sksl-kind]
@racket[runtime-effects:exn:fail:skia-sksl-kind]
@racket[exn:fail:skia-sksl-source]
@racket[runtime-effects:exn:fail:skia-sksl-source]
@racket[exn:fail:skia-sksl-diagnostics]
@racket[runtime-effects:exn:fail:skia-sksl-diagnostics]
@racket[blender?]
@racket[runtime-effects:blender?]
@racket[make-blend-mode-blender]
@racket[runtime-effects:make-blend-mode-blender]
@racket[paint-blender]
@racket[runtime-effects:paint-blender]
@racket[paint-set-blender!]
@racket[runtime-effects:paint-set-blender!]
@racket[make-arithmetic-blender]
@racket[effects:make-arithmetic-blender]
@racket[make-fractal-noise-shader]
@racket[effects:make-fractal-noise-shader]
@racket[make-turbulence-shader]
@racket[effects:make-turbulence-shader]
@racket[make-empty-shader]
@racket[effects:make-empty-shader]
@racket[shader-with-color-filter]
@racket[effects:shader-with-color-filter]
@racket[make-blender-shader]
@racket[effects:make-blender-shader]

@section{Color Management and Floating-Point Colors}

@racket[transfer-function?]

@racket[color-space:transfer-function?]

@racket[transfer-function-coefficients]

@racket[color-space:transfer-function-coefficients]

@racket[named-transfer-function]

@racket[color-space:named-transfer-function]

@racket[transfer-function-invert]

@racket[color-space:transfer-function-invert]

@racket[named-xyz-d50]

@racket[color-space:named-xyz-d50]

@racket[color-space-transfer-function]

@racket[color-space:color-space-transfer-function]

@racket[color-space-xyz-d50]

@racket[color-space:color-space-xyz-d50]

@racket[xyz-d50-invert]

@racket[color-space:xyz-d50-invert]

@racket[color-space-gamma-close-to-srgb?]

@racket[color-space->linear-gamma]

@racket[color-space->srgb-gamma]

@racket[color-space-from-icc-bytes]

@racket[color-space->icc-bytes]

@racket[color-space-descriptor?]

@racket[image-info:color-space-descriptor?]

@racket[color4f?]

@racket[color4f:color4f?]

@racket[color4f-red]

@racket[color4f:color4f-red]

@racket[color4f-green]

@racket[color4f:color4f-green]

@racket[color4f-blue]

@racket[color4f:color4f-blue]

@racket[color4f-alpha]

@racket[color4f:color4f-alpha]

@racket[color4f->vector]

@racket[color4f:color4f->vector]

@racket[color->color4f]

@racket[color4f:color->color4f]

@racket[paint-color4f]

@racket[float-colors:paint-color4f]

@racket[transfer-function-evaluate]

@racket[color-space:transfer-function-evaluate]

@racket[make-rgb-color-space]

@racket[color-space:make-rgb-color-space]

@racket[xyz-d50-concat]

@racket[color-space:xyz-d50-concat]

@racket[canvas-clear-color4f!]

@racket[float-colors:canvas-clear-color4f!]

@racket[primaries->xyz-d50]

@racket[color-space:primaries->xyz-d50]

@racket[make-transfer-function]

@racket[color-space:make-transfer-function]

@racket[make-color4f]

@racket[color4f:make-color4f]

@racket[color4f->rgba]

@racket[color4f:color4f->rgba]

@racket[image-convert-color-space]

@racket[make-paint/color4f]

@racket[float-colors:make-paint/color4f]

@racket[paint-set-color4f!]

@racket[float-colors:paint-set-color4f!]

@racket[draw-color4f]

@racket[float-colors:draw-color4f]

@racket[make-color4f-shader]

@racket[float-colors:make-color4f-shader]

@racket[make-linear-gradient-color4f-shader]

@racket[float-colors:make-linear-gradient-color4f-shader]

@racket[make-radial-gradient-color4f-shader]

@racket[float-colors:make-radial-gradient-color4f-shader]

@racket[make-sweep-gradient-color4f-shader]

@racket[float-colors:make-sweep-gradient-color4f-shader]

@racket[make-two-point-conical-gradient-color4f-shader]

@racket[float-colors:make-two-point-conical-gradient-color4f-shader]

@secref["skia-color-spaces" #:doc '(lib "skia/scribblings/reference/reference.scrbl")]

@racket[make-picture-image-filter]

@racket[picture?]

@racket[picture-recorder?]

@racket[make-picture-recorder]

@racket[picture-recorder-recording?]

@racket[picture-recorder-begin-recording!]

@racket[picture-recorder-finish-recording!]

@racket[call-with-picture]

@racket[picture-width]

@racket[picture-height]

@racket[draw-picture]

@racket[picture->image]

@racket[picture-cull-bounds]

@racket[pictures:picture-cull-bounds]

@racket[picture-unique-id]

@racket[pictures:picture-unique-id]

@racket[picture-approximate-op-count]

@racket[pictures:picture-approximate-op-count]

@racket[picture-approximate-bytes-used]

@racket[pictures:picture-approximate-bytes-used]

@racket[picture->bytes]

@racket[pictures:picture->bytes]

@racket[picture-from-bytes]

@racket[pictures:picture-from-bytes]

@racket[picture-from-file]

@racket[pictures:picture-from-file]

@racket[save-picture]

@racket[pictures:save-picture]

@racket[make-picture-shader]

@racket[pictures:make-picture-shader]

@racket[document?]

@racket[make-pdf-document]

@racket[document-state]

@racket[document-page-count]

@racket[document-begin-page!]

@racket[document-end-page!]

@racket[call-with-document-page]

@racket[with-document-page]

@racket[document-finish!]

@racket[document-abort!]

@racket[document->pdf-bytes]

@racket[save-pdf]

@racket[call-with-pdf-bytes]

@racket[call-with-pdf-file]

@racket[svg-document?]

@racket[make-svg-document]

@racket[svg-document-width]

@racket[svg-document-height]

@racket[svg-document-state]

@racket[svg-document-canvas]

@racket[svg-document-finish!]

@racket[svg-document-abort!]

@racket[svg-document->bytes]

@racket[svg-document->string]

@racket[save-svg]

@racket[call-with-svg-bytes]

@racket[call-with-svg-string]

@racket[call-with-svg-file]

@racket[unit->points]

@racket[output:unit->points]

@racket[output-page?]

@racket[output:output-page?]

@racket[make-output-page]

@racket[output:make-output-page]

@racket[output-page-width]

@racket[output:output-page-width]

@racket[output-page-height]

@racket[output:output-page-height]

@racket[output-page-unit]

@racket[output:output-page-unit]

@racket[output-page-margins]

@racket[output:output-page-margins]

@racket[output-page-background]

@racket[output:output-page-background]

@racket[output-page-clip?]

@racket[output:output-page-clip?]

@racket[output-page-size-in-points]

@racket[output:output-page-size-in-points]

@racket[output-page-content-size]

@racket[output:output-page-content-size]

@racket[draw-output-page]

@racket[output:draw-output-page]

@racket[output-page->image]

@racket[output:output-page->image]

@racket[output->bytes]

@racket[output:output->bytes]

@racket[save-output]

@racket[output:save-output]

@racket[current-text-output-mode]

@racket[current-raster-output-scale]

@racket[draw-rasterized]

@racket[canvas-annotation-backend]

@racket[annotations:canvas-annotation-backend]

@racket[canvas-annotate-url!]

@racket[annotations:canvas-annotate-url!]

@racket[canvas-define-destination!]

@racket[annotations:canvas-define-destination!]

@racket[canvas-link-destination!]

@racket[annotations:canvas-link-destination!]

@racket[destination-id]

@racket[annotations:destination-id]

@racket[svg-destination-id]

@racket[annotations:svg-destination-id]

@para{Stream, codec, and decoded-storage definitions:}

@racket[skia-input-stream?]
@racket[streams:skia-input-stream?]
@racket[make-memory-input-stream]
@racket[streams:make-memory-input-stream]
@racket[make-file-input-stream]
@racket[streams:make-file-input-stream]
@racket[input-stream-length]
@racket[streams:input-stream-length]
@racket[input-stream-position]
@racket[streams:input-stream-position]
@racket[input-stream-at-end?]
@racket[streams:input-stream-at-end?]
@racket[input-stream-read-bytes]
@racket[streams:input-stream-read-bytes]
@racket[input-stream-peek-bytes]
@racket[streams:input-stream-peek-bytes]
@racket[input-stream-skip!]
@racket[streams:input-stream-skip!]
@racket[input-stream-seek!]
@racket[streams:input-stream-seek!]
@racket[input-stream-rewind!]
@racket[streams:input-stream-rewind!]
@racket[input-stream-move!]
@racket[streams:input-stream-move!]
@racket[input-stream-duplicate]
@racket[streams:input-stream-duplicate]
@racket[input-stream-fork]
@racket[streams:input-stream-fork]
@racket[input-stream->bytes]
@racket[streams:input-stream->bytes]
@racket[skia-output-stream?]
@racket[streams:skia-output-stream?]
@racket[make-memory-output-stream]
@racket[streams:make-memory-output-stream]
@racket[output-stream-write-bytes!]
@racket[streams:output-stream-write-bytes!]
@racket[output-stream-bytes-written]
@racket[streams:output-stream-bytes-written]
@racket[output-stream->bytes]
@racket[streams:output-stream->bytes]
@racket[output-stream-detach-input!]
@racket[streams:output-stream-detach-input!]
@racket[make-file-output-stream]
@racket[file-streams:make-file-output-stream]
@racket[output-stream-flush!]
@racket[file-streams:output-stream-flush!]
@racket[buffered-port->input-stream]
@racket[streams:buffered-port->input-stream]
@racket[output-stream-write-port/buffered]
@racket[streams:output-stream-write-port/buffered]
@racket[codec-from-stream]
@racket[stream-inputs:codec-from-stream]
@racket[typeface-from-stream]
@racket[stream-inputs:typeface-from-stream]
@racket[picture-from-stream]
@racket[stream-inputs:picture-from-stream]
@racket[codec-from-port/buffered]
@racket[stream-inputs:codec-from-port/buffered]
@racket[typeface-from-port/buffered]
@racket[stream-inputs:typeface-from-port/buffered]
@racket[image-from-port/buffered]
@racket[stream-inputs:image-from-port/buffered]
@racket[picture-from-port/buffered]
@racket[stream-inputs:picture-from-port/buffered]
@racket[live-streams-check!]
@racket[live-streams:live-streams-check!]
@racket[live-streams-available?]
@racket[live-streams:live-streams-available?]
@racket[image-from-port]
@racket[live-streams:image-from-port]
@racket[picture-from-port]
@racket[live-streams:picture-from-port]
@racket[copy-port/streaming]
@racket[live-streams:copy-port/streaming]
@racket[image->port]
@racket[live-streams:image->port]
@racket[picture->port]
@racket[live-streams:picture->port]
@racket[output->port]
@racket[live-streams:output->port]
@racket[image-write-stream!]
@racket[live-streams:image-write-stream!]
@racket[picture-write-stream!]
@racket[live-streams:picture-write-stream!]
@racket[output-write-stream!]
@racket[live-streams:output-write-stream!]
@racket[image-info?]
@racket[image-info:image-info?]
@racket[make-image-info]
@racket[image-info:make-image-info]
@racket[image-info-width]
@racket[image-info:image-info-width]
@racket[image-info-height]
@racket[image-info:image-info-height]
@racket[image-info-color-type]
@racket[image-info:image-info-color-type]
@racket[image-info-alpha-type]
@racket[image-info:image-info-alpha-type]
@racket[image-info-color-space]
@racket[image-info:image-info-color-space]
@racket[image-info-bytes-per-pixel]
@racket[image-info:image-info-bytes-per-pixel]
@racket[image-info-channel-bits]
@racket[image-info:image-info-channel-bits]
@racket[image-info-sample-type]
@racket[image-info:image-info-sample-type]
@racket[image-info-byte-order]
@racket[image-info:image-info-byte-order]
@racket[image-info-min-row-bytes]
@racket[image-info:image-info-min-row-bytes]
@racket[image-info-with-dimensions]
@racket[image-info:image-info-with-dimensions]
@racket[image-info-storage-layout]
@racket[image-info:image-info-storage-layout]
@racket[image-info-supports?]
@racket[image-info:image-info-supports?]
@racket[raster-buffer?]
@racket[raster-buffers:raster-buffer?]
@racket[raster-buffer-image-info]
@racket[raster-buffers:raster-buffer-image-info]
@racket[raster-buffer->image]
@racket[raster-buffers:raster-buffer->image]
@racket[codec?]
@racket[codec-from-bytes]
@racket[codec-from-file]
@racket[codec-info]
@racket[codec-frame-count]
@racket[codec-repetition-count]
@racket[codec-color-space]
@racket[codec->image]
@racket[image-frame-from-bytes]
@racket[image-frame-from-file]
@racket[encoded-image-info?]
@racket[encoded-image-info-from-bytes]
@racket[encoded-image-info-from-file]
@racket[encoded-image-info-width]
@racket[encoded-image-info-display-width]
@racket[encoded-image-info-height]
@racket[encoded-image-info-display-height]
@racket[encoded-image-info-format]
@racket[encoded-image-info-color-type]
@racket[encoded-image-info-alpha-type]
@racket[encoded-image-info-origin]
@racket[encoded-image-info-frame-count]
@racket[codec-frame-info]
@racket[codec-frame-info?]
@racket[codec-frame-info-index]
@racket[codec-frame-info-required-frame]
@racket[codec-frame-info-duration]
@racket[codec-frame-info-fully-received?]
@racket[codec-frame-info-alpha-type]
@racket[codec-frame-info-has-alpha-within-bounds?]
@racket[codec-frame-info-disposal-method]
@racket[codec-frame-info-blend]
@racket[codec-frame-info-rect]
@racket[codec-scaled-dimensions]
@racket[codec-queries:codec-scaled-dimensions]
@racket[codec-supported-subset]
@racket[codec-queries:codec-supported-subset]
@racket[codec-scanline-session?]
@racket[codec-scanlines:codec-scanline-session?]
@racket[codec-scanline-from-bytes]
@racket[codec-scanlines:codec-scanline-from-bytes]
@racket[codec-scanline-from-stream]
@racket[codec-scanlines:codec-scanline-from-stream]
@racket[codec-scanline-from-port/buffered]
@racket[codec-scanlines:codec-scanline-from-port/buffered]
@racket[codec-scanline-state]
@racket[codec-scanlines:codec-scanline-state]
@racket[codec-scanline-info]
@racket[codec-scanlines:codec-scanline-info]
@racket[codec-scanline-source-info]
@racket[codec-scanlines:codec-scanline-source-info]
@racket[codec-scanline-order]
@racket[codec-scanlines:codec-scanline-order]
@racket[codec-scanline-position]
@racket[codec-scanlines:codec-scanline-position]
@racket[codec-scanline-next-row]
@racket[codec-scanlines:codec-scanline-next-row]
@racket[codec-scanline-output-row]
@racket[codec-scanlines:codec-scanline-output-row]
@racket[codec-scanline-read!]
@racket[codec-scanlines:codec-scanline-read!]
@racket[codec-scanline-skip!]
@racket[codec-scanlines:codec-scanline-skip!]
@racket[scanline-batch?]
@racket[codec-scanlines:scanline-batch?]
@racket[scanline-batch-info]
@racket[codec-scanlines:scanline-batch-info]
@racket[scanline-batch-row-bytes]
@racket[codec-scanlines:scanline-batch-row-bytes]
@racket[scanline-batch-first-row]
@racket[codec-scanlines:scanline-batch-first-row]
@racket[scanline-batch-requested-count]
@racket[codec-scanlines:scanline-batch-requested-count]
@racket[scanline-batch-decoded-count]
@racket[codec-scanlines:scanline-batch-decoded-count]
@racket[scanline-batch-bytes]
@racket[codec-scanlines:scanline-batch-bytes]
@racket[scanline-batch-complete?]
@racket[codec-scanlines:scanline-batch-complete?]
@racket[scanline-batch->raster-buffer]
@racket[codec-scanlines:scanline-batch->raster-buffer]
@racket[exn:fail:codec-scanline?]
@racket[codec-scanlines:exn:fail:codec-scanline?]
@racket[exn:fail:codec-scanline-result]
@racket[codec-scanlines:exn:fail:codec-scanline-result]
@racket[exn:fail:codec-scanline-native-code]
@racket[codec-scanlines:exn:fail:codec-scanline-native-code]
@racket[codec-incremental-session?]
@racket[codec-incremental:codec-incremental-session?]
@racket[make-codec-incremental]
@racket[codec-incremental:make-codec-incremental]
@racket[codec-incremental-feed!]
@racket[codec-incremental:codec-incremental-feed!]
@racket[codec-incremental-step!]
@racket[codec-incremental:codec-incremental-step!]
@racket[codec-incremental-cancel!]
@racket[codec-incremental:codec-incremental-cancel!]
@racket[codec-incremental-state]
@racket[codec-incremental:codec-incremental-state]
@racket[codec-incremental-info]
@racket[codec-incremental:codec-incremental-info]
@racket[codec-incremental-origin]
@racket[codec-incremental:codec-incremental-origin]
@racket[codec-incremental-statistics]
@racket[codec-incremental:codec-incremental-statistics]
@racket[incremental-progress?]
@racket[codec-incremental:incremental-progress?]
@racket[incremental-progress-state]
@racket[codec-incremental:incremental-progress-state]
@racket[incremental-progress-result]
@racket[codec-incremental:incremental-progress-result]
@racket[incremental-progress-initialized-rows]
@racket[codec-incremental:incremental-progress-initialized-rows]
@racket[codec-incremental-snapshot]
@racket[codec-incremental:codec-incremental-snapshot]
@racket[incremental-snapshot?]
@racket[codec-incremental:incremental-snapshot?]
@racket[incremental-snapshot-info]
@racket[codec-incremental:incremental-snapshot-info]
@racket[incremental-snapshot-row-bytes]
@racket[codec-incremental:incremental-snapshot-row-bytes]
@racket[incremental-snapshot-bytes]
@racket[codec-incremental:incremental-snapshot-bytes]
@racket[incremental-snapshot-progress]
@racket[codec-incremental:incremental-snapshot-progress]
@racket[incremental-snapshot->raster-buffer]
@racket[codec-incremental:incremental-snapshot->raster-buffer]

@section{Geometry and Advanced Drawing}

@racket[canvas-clip-rounded-rect!]

@racket[canvas-primitives:canvas-clip-rounded-rect!]

@racket[canvas-local-clip-bounds]

@racket[canvas-primitives:canvas-local-clip-bounds]

@racket[canvas-device-clip-bounds]

@racket[canvas-primitives:canvas-device-clip-bounds]

@racket[canvas-clip-empty?]

@racket[canvas-primitives:canvas-clip-empty?]

@racket[canvas-clip-rect?]

@racket[canvas-primitives:canvas-clip-rect?]

@racket[canvas-quick-reject?]

@racket[canvas-primitives:canvas-quick-reject?]

@racket[canvas-save-layer!]

@racket[canvas-primitives:canvas-save-layer!]

@racket[call-with-canvas-layer]

@racket[canvas-primitives:call-with-canvas-layer]

@racket[with-canvas-layer]

@racket[canvas-primitives:with-canvas-layer]

@racket[layer-options?]

@racket[layer-options:layer-options?]

@racket[make-layer-options]

@racket[layer-options:make-layer-options]

@racket[layer-options-bounds]

@racket[layer-options:layer-options-bounds]

@racket[layer-options-flags]

@racket[layer-options:layer-options-flags]

@racket[layer-options-preserve-lcd-text?]

@racket[layer-options:layer-options-preserve-lcd-text?]

@racket[layer-options-initialize-with-previous?]

@racket[layer-options:layer-options-initialize-with-previous?]

@racket[layer-options-f16?]

@racket[layer-options:layer-options-f16?]

@racket[canvas-save-layer/options!]

@racket[advanced-layers:canvas-save-layer/options!]

@racket[call-with-canvas-layer/options]

@racket[advanced-layers:call-with-canvas-layer/options]

@racket[canvas-discard!]

@racket[advanced-layers:canvas-discard!]

@racket[call-with-nodraw-canvas]

@racket[specialized-canvases:call-with-nodraw-canvas]

@racket[call-with-nway-canvas]

@racket[specialized-canvases:call-with-nway-canvas]

@racket[call-with-overdraw-canvas]

@racket[specialized-canvases:call-with-overdraw-canvas]

@racket[draw-point]

@racket[canvas-primitives:draw-point]

@racket[draw-points]

@racket[canvas-primitives:draw-points]

@racket[draw-arc]

@racket[canvas-primitives:draw-arc]

@racket[draw-rrect]

@racket[canvas-primitives:draw-rrect]

@racket[draw-double-rounded-rect]

@racket[canvas-primitives:draw-double-rounded-rect]

@racket[draw-color]

@racket[canvas-primitives:draw-color]

@racket[path-arc-to!]

@racket[geometry:path-arc-to!]

@racket[path-rarc-to!]

@racket[geometry:path-rarc-to!]

@racket[path-arc-to-oval!]

@racket[geometry:path-arc-to-oval!]

@racket[path-tangent-arc-to!]

@racket[geometry:path-tangent-arc-to!]

@racket[path-add-arc!]

@racket[geometry:path-add-arc!]

@racket[path-add-rect-start!]

@racket[geometry:path-add-rect-start!]

@racket[path-add-rrect!]

@racket[geometry:path-add-rrect!]

@racket[path-add-polygon!]

@racket[geometry:path-add-polygon!]

@racket[path-add-transformed!]

@racket[geometry:path-add-transformed!]

@racket[path-rewind!]

@racket[geometry:path-rewind!]

@racket[path-verbs]

@racket[geometry:path-verbs]

@racket[path-segment-kinds]

@racket[geometry:path-segment-kinds]

@racket[path-fill-bounds]

@racket[geometry:path-fill-bounds]

@racket[path-as-line]

@racket[geometry:path-as-line]

@racket[path-as-oval]

@racket[geometry:path-as-oval]

@racket[path-as-rectangle]

@racket[geometry:path-as-rectangle]

@racket[path-as-rounded-rect]

@racket[geometry:path-as-rounded-rect]

@racket[path-rectangle?]

@racket[geometry:path-rectangle?]

@racket[path-rectangle-bounds]

@racket[geometry:path-rectangle-bounds]

@racket[path-rectangle-closed?]

@racket[geometry:path-rectangle-closed?]

@racket[path-rectangle-direction]

@racket[geometry:path-rectangle-direction]

@racket[conic->quadratics]

@racket[geometry:conic->quadratics]

@racket[path-combine]

@racket[geometry:path-combine]

@racket[current-path-operation-limit]

@racket[geometry:current-path-operation-limit]

@racket[rounded-rect?]

@racket[canvas-primitives:rounded-rect?]

@racket[make-rounded-rect]

@racket[canvas-primitives:make-rounded-rect]

@racket[rounded-rect-bounds]

@racket[canvas-primitives:rounded-rect-bounds]

@racket[rounded-rect-radii]

@racket[canvas-primitives:rounded-rect-radii]

@racket[make-empty-rounded-rect]

@racket[geometry:make-empty-rounded-rect]

@racket[rounded-rect-normalize]

@racket[geometry:rounded-rect-normalize]

@racket[rounded-rect-type]

@racket[geometry:rounded-rect-type]

@racket[make-nine-patch-rounded-rect]

@racket[geometry:make-nine-patch-rounded-rect]

@racket[rounded-rect-offset]

@racket[geometry:rounded-rect-offset]

@racket[rounded-rect-inset]

@racket[geometry:rounded-rect-inset]

@racket[rounded-rect-outset]

@racket[geometry:rounded-rect-outset]

@racket[rounded-rect-transform]

@racket[geometry:rounded-rect-transform]

@racket[region?]

@racket[geometry-primitives:region?]

@racket[make-region]

@racket[geometry-primitives:make-region]

@racket[region-copy]

@racket[geometry-primitives:region-copy]

@racket[region-empty?]

@racket[geometry-primitives:region-empty?]

@racket[region-rect?]

@racket[geometry-primitives:region-rect?]

@racket[region-complex?]

@racket[geometry-primitives:region-complex?]

@racket[region-bounds]

@racket[geometry-primitives:region-bounds]

@racket[region-contains-point?]

@racket[geometry-primitives:region-contains-point?]

@racket[region-contains-rect?]

@racket[geometry-primitives:region-contains-rect?]

@racket[region-contains-region?]

@racket[geometry-primitives:region-contains-region?]

@racket[region-intersects?]

@racket[geometry-primitives:region-intersects?]

@racket[region-intersects-rect?]

@racket[geometry:region-intersects-rect?]

@racket[region-quick-contains-rect?]

@racket[geometry:region-quick-contains-rect?]

@racket[region-quick-reject-rect?]

@racket[geometry:region-quick-reject-rect?]

@racket[region-quick-reject?]

@racket[geometry:region-quick-reject?]

@racket[region-op]

@racket[geometry-primitives:region-op]

@racket[region-union]

@racket[geometry-primitives:region-union]

@racket[region-intersect]

@racket[geometry-primitives:region-intersect]

@racket[region-difference]

@racket[geometry-primitives:region-difference]

@racket[region-xor]

@racket[geometry-primitives:region-xor]

@racket[region-op-rect]

@racket[geometry:region-op-rect]

@racket[region-clear!]

@racket[geometry:region-clear!]

@racket[region-set-rect!]

@racket[geometry:region-set-rect!]

@racket[region-translate]

@racket[geometry-primitives:region-translate]

@racket[path->region]

@racket[geometry-primitives:path->region]

@racket[region->path]

@racket[geometry-primitives:region->path]

@racket[region-rectangles]

@racket[geometry-primitives:region-rectangles]

@racket[in-region-rectangles]

@racket[geometry-primitives:in-region-rectangles]

@racket[region-clipped-rectangles]

@racket[geometry:region-clipped-rectangles]

@racket[in-region-clipped-rectangles]

@racket[geometry:in-region-clipped-rectangles]

@racket[region-spans]

@racket[geometry:region-spans]

@racket[in-region-spans]

@racket[geometry:in-region-spans]

@racket[draw-region]

@racket[geometry-primitives:draw-region]

@racket[canvas-clip-region!]

@racket[geometry-primitives:canvas-clip-region!]

@racket[vertices?]

@racket[geometry-primitives:vertices?]

@racket[make-vertices]

@racket[geometry-primitives:make-vertices]

@racket[vertices-mode]

@racket[geometry-primitives:vertices-mode]

@racket[vertices-positions]

@racket[geometry-primitives:vertices-positions]

@racket[vertices-texture-coordinates]

@racket[geometry-primitives:vertices-texture-coordinates]

@racket[vertices-colors]

@racket[geometry-primitives:vertices-colors]

@racket[vertices-indices]

@racket[geometry-primitives:vertices-indices]

@racket[vertices-count]

@racket[geometry-primitives:vertices-count]

@racket[draw-vertices]

@racket[geometry-primitives:draw-vertices]

@racket[cubic-patch?]

@racket[geometry-primitives:cubic-patch?]

@racket[make-cubic-patch]

@racket[geometry-primitives:make-cubic-patch]

@racket[cubic-patch-points]

@racket[geometry-primitives:cubic-patch-points]

@racket[cubic-patch-colors]

@racket[geometry-primitives:cubic-patch-colors]

@racket[cubic-patch-texture-coordinates]

@racket[geometry-primitives:cubic-patch-texture-coordinates]

@racket[draw-patch]

@racket[geometry-primitives:draw-patch]

@racket[image-lattice?]

@racket[geometry-primitives:image-lattice?]

@racket[make-image-lattice]

@racket[geometry-primitives:make-image-lattice]

@racket[image-lattice-x-divisions]

@racket[geometry-primitives:image-lattice-x-divisions]

@racket[image-lattice-y-divisions]

@racket[geometry-primitives:image-lattice-y-divisions]

@racket[image-lattice-bounds]

@racket[geometry-primitives:image-lattice-bounds]

@racket[image-lattice-cell-types]

@racket[geometry-primitives:image-lattice-cell-types]

@racket[image-lattice-colors]

@racket[geometry-primitives:image-lattice-colors]

@racket[draw-image-nine]

@racket[geometry-primitives:draw-image-nine]

@racket[draw-image-lattice]

@racket[geometry-primitives:draw-image-lattice]

@racket[draw-atlas]

@racket[geometry-primitives:draw-atlas]

@racket[draw-markers]

@racket[portable-drawing:draw-markers]

@racket[image-grid-cell?]

@racket[portable-drawing:image-grid-cell?]

@racket[image-nine-plan]

@racket[portable-drawing:image-nine-plan]

@racket[image-lattice-plan]

@racket[portable-drawing:image-lattice-plan]

@racket[image-grid-cell-row]

@racket[portable-drawing:image-grid-cell-row]

@racket[image-grid-cell-column]

@racket[portable-drawing:image-grid-cell-column]

@racket[image-grid-cell-kind]

@racket[portable-drawing:image-grid-cell-kind]

@racket[image-grid-cell-source]

@racket[portable-drawing:image-grid-cell-source]

@racket[image-grid-cell-destination]

@racket[portable-drawing:image-grid-cell-destination]

@racket[image-grid-cell-color]

@racket[portable-drawing:image-grid-cell-color]

@racket[image-grid-plan->jsexpr]

@racket[portable-drawing:image-grid-plan->jsexpr]

@racket[draw-image-nine/portable]

@racket[portable-drawing:draw-image-nine/portable]

@racket[draw-image-lattice/portable]

@racket[portable-drawing:draw-image-lattice/portable]

@racket[draw-atlas/portable]

@racket[portable-drawing:draw-atlas/portable]

@racket[matrix3?]

@racket[projective-matrix:matrix3?]

@racket[make-matrix3]

@racket[projective-matrix:make-matrix3]

@racket[matrix3-identity]

@racket[projective-matrix:matrix3-identity]

@racket[vector->matrix3]

@racket[projective-matrix:vector->matrix3]

@racket[matrix3->vector]

@racket[projective-matrix:matrix3->vector]

@racket[matrix3-ref]

@racket[projective-matrix:matrix3-ref]

@racket[matrix3-compose]

@racket[projective-matrix:matrix3-compose]

@racket[matrix3-transpose]

@racket[projective-matrix:matrix3-transpose]

@racket[matrix3-invert]

@racket[projective-matrix:matrix3-invert]

@racket[matrix3-perspective]

@racket[projective-matrix:matrix3-perspective]

@racket[matrix3-affine?]

@racket[projective-matrix:matrix3-affine?]

@racket[matrix->matrix3]

@racket[projective-matrix:matrix->matrix3]

@racket[matrix3->matrix]

@racket[projective-matrix:matrix3->matrix]

@racket[matrix3-map-homogeneous]

@racket[projective-matrix:matrix3-map-homogeneous]

@racket[matrix3-map-point]

@racket[projective-matrix:matrix3-map-point]

@racket[matrix3-map-rect]

@racket[projective-matrix:matrix3-map-rect]

@racket[matrix4?]

@racket[projective-matrix:matrix4?]

@racket[make-matrix4]

@racket[projective-matrix:make-matrix4]

@racket[matrix4-identity]

@racket[projective-matrix:matrix4-identity]

@racket[vector->matrix4]

@racket[projective-matrix:vector->matrix4]

@racket[matrix4->vector]

@racket[projective-matrix:matrix4->vector]

@racket[matrix4-ref]

@racket[projective-matrix:matrix4-ref]

@racket[matrix4-compose]

@racket[projective-matrix:matrix4-compose]

@racket[matrix4-transpose]

@racket[projective-matrix:matrix4-transpose]

@racket[matrix4-invert]

@racket[projective-matrix:matrix4-invert]

@racket[matrix4-translate]

@racket[projective-matrix:matrix4-translate]

@racket[matrix4-scale]

@racket[projective-matrix:matrix4-scale]

@racket[matrix4-rotate-x-degrees]

@racket[projective-matrix:matrix4-rotate-x-degrees]

@racket[matrix4-rotate-y-degrees]

@racket[projective-matrix:matrix4-rotate-y-degrees]

@racket[matrix4-rotate-z-degrees]

@racket[projective-matrix:matrix4-rotate-z-degrees]

@racket[matrix4-perspective]

@racket[projective-matrix:matrix4-perspective]

@racket[matrix4-affine-2d?]

@racket[projective-matrix:matrix4-affine-2d?]

@racket[matrix->matrix4]

@racket[projective-matrix:matrix->matrix4]

@racket[matrix4->matrix]

@racket[projective-matrix:matrix4->matrix]

@racket[matrix3->matrix4]

@racket[projective-matrix:matrix3->matrix4]

@racket[matrix4->matrix3]

@racket[projective-matrix:matrix4->matrix3]

@racket[matrix4-project-xy]

@racket[projective-matrix:matrix4-project-xy]

@racket[matrix4-map-homogeneous]

@racket[projective-matrix:matrix4-map-homogeneous]

@racket[matrix4-map-point]

@racket[projective-matrix:matrix4-map-point]

@racket[matrix4-map-rect]

@racket[projective-matrix:matrix4-map-rect]

@racket[canvas-matrix4]

@racket[canvas-matrix:canvas-matrix4]

@racket[canvas-set-matrix3!]

@racket[canvas-matrix:canvas-set-matrix3!]

@racket[canvas-concat-matrix3!]

@racket[canvas-matrix:canvas-concat-matrix3!]

@racket[canvas-set-matrix4!]

@racket[canvas-matrix:canvas-set-matrix4!]

@racket[canvas-concat-matrix4!]

@racket[canvas-matrix:canvas-concat-matrix4!]

@racket[call-with-canvas-matrix]

@racket[canvas-matrix:call-with-canvas-matrix]

@racket[with-canvas-matrix]

@racket[canvas-matrix:with-canvas-matrix]

@racket[drawable?]

@racket[drawables:drawable?]

@racket[picture->drawable]

@racket[drawables:picture->drawable]

@racket[call-with-drawable]

@racket[drawables:call-with-drawable]

@racket[draw-drawable]

@racket[drawables:draw-drawable]

@racket[drawable->picture]

@racket[drawables:drawable->picture]

@racket[drawable-bounds]

@racket[drawables:drawable-bounds]

@racket[drawable-generation-id]

@racket[drawables:drawable-generation-id]

@racket[drawable-approximate-bytes-used]

@racket[drawables:drawable-approximate-bytes-used]

@racket[drawable-notify-drawing-changed!]

@racket[drawables:drawable-notify-drawing-changed!]

@section{Racket Pict Bridge}

@racket[pict:image->pict]

@racket[pict:surface->pict]

@racket[pict:picture->pict]

@section{Racket Draw Interoperability}

@racket[racket-draw:bitmap->image]

@racket[racket-draw:image->bitmap]

@racket[racket-draw:surface->bitmap]

@racket[racket-draw:color%->rgba]

@racket[racket-draw:rgba->color%]

@racket[racket-draw:dc-path->skia-path]

@racket[racket-draw:skia-path->dc-path]

@section{Raster, Output Policy, and Diagnostics}

@racket[surface-properties?]

@racket[surface-properties:surface-properties?]

@racket[make-surface-properties]

@racket[surface-properties:make-surface-properties]

@racket[surface-properties-pixel-geometry]

@racket[surface-properties:surface-properties-pixel-geometry]

@racket[surface-properties-flags]

@racket[surface-properties:surface-properties-flags]

@racket[surface-properties-device-independent-fonts?]

@racket[surface-properties:surface-properties-device-independent-fonts?]

@racket[surface-properties-dynamic-msaa?]

@racket[surface-properties:surface-properties-dynamic-msaa?]

@racket[surface-properties-always-dither?]

@racket[surface-properties:surface-properties-always-dither?]

@racket[surface-properties->jsexpr]

@racket[surface-properties:surface-properties->jsexpr]

@racket[surface-properties-of]

@racket[make-raw-image-shader]

@racket[image-operations:make-raw-image-shader]

@racket[image-unique-id]

@racket[image-operations:image-unique-id]

@racket[image-alpha-only?]

@racket[image-operations:image-alpha-only?]

@racket[image-lazy-generated?]

@racket[image-operations:image-lazy-generated?]

@racket[image-texture-backed?]

@racket[image-operations:image-texture-backed?]

@racket[image-valid?]

@racket[image-operations:image-valid?]

@racket[image-pixels-available?]

@racket[image-operations:image-pixels-available?]

@racket[image->non-texture-image]

@racket[image-operations:image->non-texture-image]

@racket[image->raster-image]

@racket[image-operations:image->raster-image]

@racket[image-read-pixmap!]

@racket[image-operations:image-read-pixmap!]

@racket[image-scale-pixmap!]

@racket[image-operations:image-scale-pixmap!]

@racket[image->raster-buffer]

@racket[image-operations:image->raster-buffer]

@racket[image-apply-filter]

@racket[image-operations:image-apply-filter]

@racket[bitmap:image->bitmap]

@racket[bitmap:surface->bitmap]

@racket[output-backends]

@racket[output-audit:output-backends]

@racket[output-policy:output-backends]

@racket[output-feature-names]

@racket[output-audit:output-feature-names]

@racket[output-policy:output-feature-names]

@racket[output-capability?]

@racket[output-audit:output-capability?]

@racket[output-policy:output-capability?]

@racket[output-capability-for]

@racket[output-audit:output-capability-for]

@racket[output-policy:output-capability-for]

@racket[output-capability-backend]

@racket[output-audit:output-capability-backend]

@racket[output-policy:output-capability-backend]

@racket[output-capability-feature]

@racket[output-audit:output-capability-feature]

@racket[output-policy:output-capability-feature]

@racket[output-capability-status]

@racket[output-audit:output-capability-status]

@racket[output-policy:output-capability-status]

@racket[output-capability-reason]

@racket[output-audit:output-capability-reason]

@racket[output-policy:output-capability-reason]

@racket[analyze-output-page]

@racket[output-audit:analyze-output-page]

@racket[output->bytes/audit]

@racket[output-audit:output->bytes/audit]

@racket[save-output/audit]

@racket[output-audit:save-output/audit]

@racket[current-output-audit-event-limit]

@racket[output-audit:current-output-audit-event-limit]

@racket[call-with-output-label]

@racket[output-audit:call-with-output-label]

@racket[with-output-label]

@racket[output-audit:with-output-label]

@racket[output-audit-event?]

@racket[output-audit:output-audit-event?]

@racket[output-policy:output-audit-event?]

@racket[output-audit-event-page]

@racket[output-audit:output-audit-event-page]

@racket[output-policy:output-audit-event-page]

@racket[output-audit-event-operation]

@racket[output-audit:output-audit-event-operation]

@racket[output-policy:output-audit-event-operation]

@racket[output-audit-event-scope]

@racket[output-audit:output-audit-event-scope]

@racket[output-policy:output-audit-event-scope]

@racket[output-audit-event-feature]

@racket[output-audit:output-audit-event-feature]

@racket[output-policy:output-audit-event-feature]

@racket[output-audit-event-status]

@racket[output-audit:output-audit-event-status]

@racket[output-policy:output-audit-event-status]

@racket[output-audit-event-reason]

@racket[output-audit:output-audit-event-reason]

@racket[output-policy:output-audit-event-reason]

@racket[output-audit-event-details]

@racket[output-audit:output-audit-event-details]

@racket[output-policy:output-audit-event-details]

@racket[output-audit-report?]

@racket[output-audit:output-audit-report?]

@racket[output-policy:output-audit-report?]

@racket[output-audit-report-backend]

@racket[output-audit:output-audit-report-backend]

@racket[output-policy:output-audit-report-backend]

@racket[output-audit-report-pages]

@racket[output-audit:output-audit-report-pages]

@racket[output-policy:output-audit-report-pages]

@racket[output-audit-report-events]

@racket[output-audit:output-audit-report-events]

@racket[output-policy:output-audit-report-events]

@racket[output-audit-report-mode]

@racket[output-audit:output-audit-report-mode]

@racket[output-policy:output-audit-report-mode]

@racket[output-audit-report-blocking?]

@racket[output-audit:output-audit-report-blocking?]

@racket[output-policy:output-audit-report-blocking?]

@racket[output-audit-report-vector-only?]

@racket[output-audit:output-audit-report-vector-only?]

@racket[output-policy:output-audit-report-vector-only?]

@racket[output-audit-report->jsexpr]

@racket[output-audit:output-audit-report->jsexpr]

@racket[output-policy:output-audit-report->jsexpr]

@racket[exn:fail:output-audit?]

@racket[output-audit:exn:fail:output-audit?]

@racket[output-policy:exn:fail:output-audit?]

@racket[exn:fail:output-audit-event]

@racket[output-audit:exn:fail:output-audit-event]

@racket[output-policy:exn:fail:output-audit-event]

@racket[draw-output-group]

@racket[output-groups:draw-output-group]

@racket[output-raster-executor?]

@racket[output-groups:output-raster-executor?]

@racket[output-group-report?]

@racket[output-groups:output-group-report?]

@racket[output-group-report-backend]

@racket[output-groups:output-group-report-backend]

@racket[output-group-report-policy]

@racket[output-groups:output-group-report-policy]

@racket[output-group-report-strategy]

@racket[output-groups:output-group-report-strategy]

@racket[output-group-report-reason]

@racket[output-groups:output-group-report-reason]

@racket[output-group-report-bounds]

@racket[output-groups:output-group-report-bounds]

@racket[output-group-report-padded-bounds]

@racket[output-groups:output-group-report-padded-bounds]

@racket[output-group-report-pixel-size]

@racket[output-groups:output-group-report-pixel-size]

@racket[output-group-report-scale]

@racket[output-groups:output-group-report-scale]

@racket[output-group-report-features]

@racket[output-groups:output-group-report-features]

@racket[output-group-report-label]

@racket[output-groups:output-group-report-label]

@racket[output-group-report-children]

@racket[output-groups:output-group-report-children]

@racket[output-group-report-execution]

@racket[output-groups:output-group-report-execution]

@racket[output-group-report->jsexpr]

@racket[output-groups:output-group-report->jsexpr]

@racket[exn:fail:output-group?]

@racket[output-groups:exn:fail:output-group?]

@racket[exn:fail:output-group-report]

@racket[output-groups:exn:fail:output-group-report]

@racket[integer-pixel-formats]

@racket[image-info:integer-pixel-formats]

@racket[float-pixel-formats]

@racket[image-info:float-pixel-formats]

@racket[pixel-formats]

@racket[image-info:pixel-formats]

@racket[make-raster-buffer]

@racket[raster-buffers:make-raster-buffer]

@racket[make-raster-buffer-from-info]

@racket[raster-buffers:make-raster-buffer-from-info]

@racket[raster-buffer-width]

@racket[raster-buffers:raster-buffer-width]

@racket[raster-buffer-height]

@racket[raster-buffers:raster-buffer-height]

@racket[raster-buffer-row-bytes]

@racket[raster-buffers:raster-buffer-row-bytes]

@racket[raster-buffer-byte-size]

@racket[raster-buffers:raster-buffer-byte-size]

@racket[raster-buffer-copy]

@racket[raster-buffers:raster-buffer-copy]

@racket[raster-buffer->storage-bytes]

@racket[raster-buffers:raster-buffer->storage-bytes]

@racket[raster-buffer-write-storage!]

@racket[raster-buffers:raster-buffer-write-storage!]

@racket[raster-buffer->rgba-bytes]

@racket[raster-buffers:raster-buffer->rgba-bytes]

@racket[raster-buffer-write-rgba!]

@racket[raster-buffers:raster-buffer-write-rgba!]

@racket[raster-buffer-opaque?]

@racket[raster-buffers:raster-buffer-opaque?]

@racket[pixmap?]

@racket[raster-buffers:pixmap?]

@racket[call-with-raster-buffer-pixmap]

@racket[raster-buffers:call-with-raster-buffer-pixmap]

@racket[pixmap-width]

@racket[raster-buffers:pixmap-width]

@racket[pixmap-height]

@racket[raster-buffers:pixmap-height]

@racket[pixmap-row-bytes]

@racket[raster-buffers:pixmap-row-bytes]

@racket[pixmap-writable?]

@racket[raster-buffers:pixmap-writable?]

@racket[pixmap-image-info]

@racket[raster-buffers:pixmap-image-info]

@racket[pixmap-subset]

@racket[raster-buffers:pixmap-subset]

@racket[pixmap-sample]

@racket[raster-buffers:pixmap-sample]

@racket[pixmap-set-sample!]

@racket[raster-buffers:pixmap-set-sample!]

@racket[pixmap-pixel]

@racket[raster-buffers:pixmap-pixel]

@racket[pixmap-color4f]

@racket[raster-buffers:pixmap-color4f]

@racket[pixmap-alphaf]

@racket[raster-buffers:pixmap-alphaf]

@racket[pixmap-fill!]

@racket[raster-buffers:pixmap-fill!]

@racket[pixmap-set-pixel!]

@racket[raster-buffers:pixmap-set-pixel!]

@racket[pixmap-fill-color4f!]

@racket[raster-buffers:pixmap-fill-color4f!]

@racket[pixmap-set-color4f!]

@racket[raster-buffers:pixmap-set-color4f!]

@racket[pixmap-opaque?]

@racket[raster-buffers:pixmap-opaque?]

@racket[pixmap->storage-bytes]

@racket[raster-buffers:pixmap->storage-bytes]

@racket[pixmap-write-storage!]

@racket[raster-buffers:pixmap-write-storage!]

@racket[pixmap->rgba-bytes]

@racket[raster-buffers:pixmap->rgba-bytes]

@racket[pixmap-write-rgba!]

@racket[raster-buffers:pixmap-write-rgba!]

@racket[pixmap-convert!]

@racket[raster-buffers:pixmap-convert!]

@racket[pixmap-scale!]

@racket[raster-buffers:pixmap-scale!]

@racket[raster-buffer-convert]

@racket[raster-buffers:raster-buffer-convert]

@racket[raster-buffer-extract-alpha]

@racket[raster-buffers:raster-buffer-extract-alpha]

@racket[image->image-info]

@racket[raster-buffers:image->image-info]

@racket[make-surface-from-info]

@racket[raster-buffers:make-surface-from-info]

@racket[call-with-raster-buffer-canvas]

@racket[raster-buffers:call-with-raster-buffer-canvas]

@racket[color-space->descriptor]

@racket[raster-buffers:color-space->descriptor]

@racket[descriptor->color-space]

@racket[raster-buffers:descriptor->color-space]

@racket[skia-font-cache-used]

@racket[graphics:skia-font-cache-used]

@racket[skia-font-cache-limit]

@racket[graphics:skia-font-cache-limit]

@racket[skia-font-cache-count-used]

@racket[graphics:skia-font-cache-count-used]

@racket[skia-font-cache-count-limit]

@racket[graphics:skia-font-cache-count-limit]

@racket[skia-resource-cache-used]

@racket[graphics:skia-resource-cache-used]

@racket[skia-resource-cache-limit]

@racket[graphics:skia-resource-cache-limit]

@racket[skia-resource-cache-single-allocation-limit]

@racket[graphics:skia-resource-cache-single-allocation-limit]

@racket[skia-set-font-cache-limit!]

@racket[graphics:skia-set-font-cache-limit!]

@racket[skia-set-font-cache-count-limit!]

@racket[graphics:skia-set-font-cache-count-limit!]

@racket[skia-set-resource-cache-limit!]

@racket[graphics:skia-set-resource-cache-limit!]

@racket[skia-set-resource-cache-single-allocation-limit!]

@racket[graphics:skia-set-resource-cache-single-allocation-limit!]

@racket[skia-initialize!]

@racket[graphics:skia-initialize!]

@racket[skia-purge-font-cache!]

@racket[graphics:skia-purge-font-cache!]

@racket[skia-purge-resource-cache!]

@racket[graphics:skia-purge-resource-cache!]

@racket[skia-purge-all-caches!]

@racket[graphics:skia-purge-all-caches!]

@racket[skia-cache-statistics]

@racket[graphics:skia-cache-statistics]

@racket[skia-memory-statistics]

@racket[graphics:skia-memory-statistics]

@racket[memory-statistics?]

@racket[graphics:memory-statistics?]

@racket[memory-statistics-entries]

@racket[graphics:memory-statistics-entries]

@racket[memory-statistics-detailed?]

@racket[graphics:memory-statistics-detailed?]

@racket[memory-statistics-dump-wrapped?]

@racket[graphics:memory-statistics-dump-wrapped?]

@racket[memory-statistics-truncated?]

@racket[graphics:memory-statistics-truncated?]

@racket[memory-statistics-dropped-count]

@racket[graphics:memory-statistics-dropped-count]

@racket[memory-statistics-string-bytes]

@racket[graphics:memory-statistics-string-bytes]

@racket[memory-statistics-scope]

@racket[graphics:memory-statistics-scope]

@racket[memory-statistics->jsexpr]

@racket[graphics:memory-statistics->jsexpr]

@racket[memory-statistic?]

@racket[graphics:memory-statistic?]

@racket[memory-statistic-kind]

@racket[graphics:memory-statistic-kind]

@racket[memory-statistic-name]

@racket[graphics:memory-statistic-name]

@racket[memory-statistic-value-name]

@racket[graphics:memory-statistic-value-name]

@racket[memory-statistic-units]

@racket[graphics:memory-statistic-units]

@racket[memory-statistic-value]

@racket[graphics:memory-statistic-value]

@racket[skia-check!]

@racket[skia-available?]

@racket[skia-native-version]

@racket[skia-native-library-path]

@racket[harfbuzz-package-version]

@racket[harfbuzz-check!]

@racket[harfbuzz-available?]

@racket[harfbuzz-native-version]

@racket[harfbuzz-native-library-path]

@racket[native-package-version]

@racket[native-capabilities:native-package-version]

@racket[native-capabilities:native-abi-catalog]

@racket[native-capabilities:native-abi-profiles]

@racket[native-capabilities:skia-native-capabilities]

@racket[native-capabilities:skia-native-symbol-inventory]

@racket[gpu:gpu-backends]

@racket[gpu:gpu-backend?]

@racket[gpu:gpu-backend-capabilities]

@racket[gpu:gpu-provider?]

@racket[gpu:make-gpu-provider]

@racket[gpu:gpu-provider-name]

@racket[gpu:gpu-provider-backend]

@racket[gpu:exn:fail:gpu:unavailable?]

@racket[gpu:exn:fail:gpu:unavailable-step]

@racket[gpu:gpu-context?]

@racket[gpu:make-gpu-context]

@racket[gpu:call-with-gpu-context]

@racket[gpu:gpu-context-backend]

@racket[gpu:gpu-context-generation]

@racket[gpu:gpu-context-state]

@racket[gpu:gpu-context-info]

@racket[gpu:gpu-context-close!]

@racket[gpu:gpu-context-abandon!]

@racket[gpu:gpu-context-release-and-abandon!]

@racket[gpu:gpu-context-request-shutdown!]

@racket[gpu:gpu-drain-releases!]

@racket[gpu:gpu-drain-pending-contexts!]

@racket[gpu:gpu-context-options?]

@racket[gpu-context-options:gpu-context-options?]

@racket[gpu:make-gpu-context-options]

@racket[gpu-context-options:make-gpu-context-options]

@racket[gpu:gpu-context-options-avoid-stencil-buffers?]

@racket[gpu-context-options:gpu-context-options-avoid-stencil-buffers?]

@racket[gpu:gpu-context-options-runtime-program-cache-size]

@racket[gpu-context-options:gpu-context-options-runtime-program-cache-size]

@racket[gpu:gpu-context-options-glyph-cache-texture-maximum-bytes]

@racket[gpu-context-options:gpu-context-options-glyph-cache-texture-maximum-bytes]

@racket[gpu:gpu-context-options-allow-path-mask-caching?]

@racket[gpu-context-options:gpu-context-options-allow-path-mask-caching?]

@racket[gpu:gpu-context-options-manual-mipmapping?]

@racket[gpu-context-options:gpu-context-options-manual-mipmapping?]

@racket[gpu:gpu-context-options-buffer-map-threshold]

@racket[gpu-context-options:gpu-context-options-buffer-map-threshold]

@racket[gpu:gpu-context-options->jsexpr]

@racket[gpu-context-options:gpu-context-options->jsexpr]

@section{GPU Surfaces, Transfers, and Synchronization}

@racket[gpu:gpu-surface?]
@racket[gpu:make-gpu-surface]
@racket[gpu:gpu-surface-format-info]
@racket[gpu:gpu-surface-info]
@racket[gpu:gpu-surface->image-info]
@racket[gpu:gpu-image?]
@racket[gpu:image-residency]
@racket[gpu:skia-resource-gpu-context]
@racket[gpu:gpu-image-info]
@racket[gpu:gpu-upload-image]
@racket[gpu:gpu-surface-snapshot]
@racket[gpu:gpu-image-subset]
@racket[gpu:gpu-image-apply-filter]
@racket[gpu:gpu-surface->rgba-bytes]
@racket[gpu:gpu-image->rgba-bytes]
@racket[gpu:gpu-surface->raster-buffer]
@racket[gpu:gpu-image->raster-buffer]
@racket[gpu:gpu-surface->raster-image]
@racket[gpu:gpu-image->raster-image]
@racket[gpu:gpu-surface-read-pixmap!]
@racket[gpu:gpu-surface-read-raster-buffer!]
@racket[gpu:gpu-image-read-raster-buffer!]
@racket[gpu:render-gpu->raster-image]
@racket[gpu:gpu-flush!]
@racket[gpu:gpu-submit!]
@racket[gpu:gpu-flush-and-submit!]
@racket[gpu:gpu-wait!]
@racket[gpu:gpu-flush-surface!]
@racket[gpu:gpu-flush-image!]
@racket[gpu:gpu-cache-info]
@racket[gpu:gpu-set-cache-limit!]
@racket[gpu:gpu-purge-unlocked!]
@racket[gpu:gpu-purge-bytes!]
@racket[gpu:gpu-perform-deferred-cleanup!]
@racket[gpu:gpu-free-resources!]
@racket[gpu:gpu-memory-statistics]
@racket[gpu-diagnostics:gpu-memory-statistics]

@section{GPU Hosts, Diagnostics, and Interoperation}

@racket[gpu-egl:make-egl-gpu-context]
@racket[gpu-egl:make-current-egl-gpu-provider]
@racket[gpu-racket-gl:make-racket-gl-provider]
@racket[gpu:gpu-gl-interface-info]
@racket[gpu-diagnostics:gpu-gl-interface-info]
@racket[gpu:gpu-gl-has-extension?]
@racket[gpu-diagnostics:gpu-gl-has-extension?]
@racket[gpu:gpu-smoke-test]
@racket[gpu-gl-interop:call-with-gpu-external-gl]
@racket[gpu-gl-interop:call-with-gpu-gl-framebuffer]
@racket[gpu-gl-interop:gpu-copy-gl-texture]
@racket[gpu-interop:gpu-external-texture?]
@racket[gpu-interop:gpu-external-texture-info]
@racket[gpu-interop:gpu-external-texture-close!]
@racket[gpu-interop:gpu-import-image]
@racket[gpu-interop:call-with-gpu-external-surface]
@racket[unsafe-gpu-metal:call-with-gpu-metal-device]
@racket[unsafe-gpu-metal:make-metal-external-texture]
@racket[unsafe-gpu-d3d12:call-with-gpu-d3d12-device]
@racket[unsafe-gpu-d3d12:make-d3d12-external-texture]

@section{GPU Raster Output Execution}

@racket[gpu-output:make-gpu-raster-executor]

@racket[gpu-output:call-with-gpu-raster-executor]
@section{GPU Presentation and GUI Canvases}

@racket[gpu:gpu-presenter?]
@racket[gpu:gpu-presenter-backend]
@racket[gpu:gpu-presenter-context]
@racket[gpu:gpu-presenter-state]
@racket[gpu:gpu-presenter-info]
@racket[gpu:gpu-presenter-render!]
@racket[gpu:gpu-presenter-request-render!]
@racket[gpu:gpu-presenter-set-render!]
@racket[gpu:gpu-presenter-close!]
@racket[gpu:gpu-drain-pending-presenters!]
@racket[gpu:gpu-frame?]
@racket[gpu:gpu-frame-expired?]
@racket[gpu:gpu-frame-canvas]
@racket[gpu:gpu-frame-context]
@racket[gpu:gpu-frame-info]
@racket[gpu:gpu-frame-width]
@racket[gpu:gpu-frame-height]
@racket[gpu:gpu-frame-logical-width]
@racket[gpu:gpu-frame-logical-height]
@racket[gpu:gpu-frame-scale-x]
@racket[gpu:gpu-frame-scale-y]
@racket[gpu:gpu-frame-generation]
@racket[gpu:gpu-frame-index]
@racket[canvas:skia-canvas%]
@racket[canvas:skia-canvas?]
@racket[gpu-gui:gpu-canvas%]
@racket[gpu-gui:gpu-window%]
@racket[gpu-canvas:skia-gpu-canvas%]
@racket[gpu-canvas:skia-gpu-canvas?]
@racket[gpu-canvas:skia-gpu-window%]
@racket[render-canvas:make-skia-render-canvas]
@racket[render-canvas:skia-render-canvas<%>]
@racket[render-canvas:skia-render-canvas?]
@racket[render-canvas:skia-render-window%]

@section{Racket Drawing-Context Integration}

@racket[dc:skia-dc%]
@racket[dc:skia-dc?]
@racket[dc:skia-dc-capabilities]
@racket[dc:skia-dc-compatibility]
@racket[dc:exn:fail:skia-dc:unsupported]
@racket[dc:struct:exn:fail:skia-dc:unsupported]
@racket[dc:exn:fail:skia-dc:unsupported?]
@racket[dc:exn:fail:skia-dc:unsupported-method]
@racket[dc:exn:fail:skia-dc:unsupported-feature]
@racket[dc:exn:fail:skia-dc:unsupported-stage]

@racket[dc-output:call-with-output-dc]
@racket[dc-output:current-output-dc-command-limit]
@racket[dc-output:dc-annotate-url!]
@racket[dc-output:dc-define-destination!]
@racket[dc-output:dc-link-destination!]
@racket[dc-output:draw-dc-raster-group]
@racket[dc-output:make-dc-output-page]
@racket[dc-output:output-dc-capabilities]
@racket[dc-output:skia-output-dc?]

@racket[gpu-dc:call-with-gpu-frame-dc]
@racket[gpu-dc:call-with-gpu-surface-dc]
@racket[gpu-dc:skia-gpu-dc-capabilities]
@racket[gpu-dc:skia-gpu-dc?]
