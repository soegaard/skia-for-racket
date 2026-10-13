#lang scribble/manual

@(require (for-label racket/base skia
                     (prefix-in color: skia/color)
                     (prefix-in geometry: skia/geometry)
                     (prefix-in effects: skia/effects)
                     (prefix-in filters: skia/color-filters)
                     (prefix-in runtime: skia/runtime-effects)
                     (prefix-in matrix: skia/matrix)
                     (prefix-in typefaces: skia/typefaces)
                     (prefix-in fonts: skia/fonts)
                     (prefix-in blobs: skia/text-blobs)
                     (prefix-in primitives: skia/geometry-primitives)))

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

@racket[blobs:text-blob-builder?]

@racket[make-text-blob-builder]

@racket[blobs:make-text-blob-builder]

@racket[text-blob-builder-run-count]

@racket[blobs:text-blob-builder-run-count]

@racket[text-blob-builder-add-run!]

@racket[blobs:text-blob-builder-add-run!]

@racket[text-blob-builder-add-horizontal-run!]

@racket[blobs:text-blob-builder-add-horizontal-run!]

@racket[text-blob-builder-add-positioned-run!]

@racket[blobs:text-blob-builder-add-positioned-run!]

@racket[text-blob-builder-add-transformed-run!]

@racket[blobs:text-blob-builder-add-transformed-run!]

@racket[text-blob-builder-add-shaped-run!]

@racket[blobs:text-blob-builder-add-shaped-run!]

@racket[text-blob-builder-finish!]

@racket[blobs:text-blob-builder-finish!]

@racket[text-blob-run-count]

@racket[blobs:text-blob-run-count]

@racket[text-blob-runs]

@racket[blobs:text-blob-runs]

@racket[text-blob-run-font]

@racket[blobs:text-blob-run-font]

@racket[text-blob-intercepts]

@racket[blobs:text-blob-intercepts]

@racket[text-run-info?]

@racket[blobs:text-run-info?]

@racket[text-run-info-positioning]

@racket[blobs:text-run-info-positioning]

@racket[text-run-info-glyphs]

@racket[blobs:text-run-info-glyphs]

@racket[text-run-info-positions]

@racket[blobs:text-run-info-positions]

@racket[text-run-info-transforms]

@racket[blobs:text-run-info-transforms]

@racket[text-run-info-utf8]

@racket[blobs:text-run-info-utf8]

@racket[text-run-info-clusters]

@racket[blobs:text-run-info-clusters]

@racket[positioned-glyphs->path]

@racket[blobs:positioned-glyphs->path]

@racket[shaped-run->text-blob/on-path]

@racket[blobs:shaped-run->text-blob/on-path]

@racket[draw-shaped-run/on-path]

@racket[blobs:draw-shaped-run/on-path]

@racket[atlas-transform?]

@racket[primitives:atlas-transform?]

@racket[make-atlas-transform]

@racket[primitives:make-atlas-transform]

@racket[atlas-transform-coefficients]

@racket[primitives:atlas-transform-coefficients]

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
@racket[filters:make-hsla-matrix-filter]
@racket[make-linear-to-srgb-gamma-color-filter]
@racket[filters:make-linear-to-srgb-gamma-color-filter]
@racket[make-srgb-to-linear-gamma-color-filter]
@racket[filters:make-srgb-to-linear-gamma-color-filter]
@racket[make-lerp-color-filter]
@racket[filters:make-lerp-color-filter]
@racket[make-luma-color-filter]
@racket[filters:make-luma-color-filter]
@racket[make-high-contrast-color-filter]
@racket[filters:make-high-contrast-color-filter]
@racket[make-table-color-filter]
@racket[filters:make-table-color-filter]
@racket[make-table-argb-color-filter]
@racket[filters:make-table-argb-color-filter]
@racket[make-lighting-color-filter]
@racket[filters:make-lighting-color-filter]
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
@racket[runtime:runtime-effect?]
@racket[make-runtime-effect]
@racket[runtime:make-runtime-effect]
@racket[runtime-effect-kind]
@racket[runtime:runtime-effect-kind]
@racket[runtime-effect-source]
@racket[runtime:runtime-effect-source]
@racket[runtime-effect-uniform-byte-size]
@racket[runtime:runtime-effect-uniform-byte-size]
@racket[runtime-effect-uniforms]
@racket[runtime:runtime-effect-uniforms]
@racket[runtime-effect-children]
@racket[runtime:runtime-effect-children]
@racket[runtime-effect-uniform-bytes]
@racket[runtime:runtime-effect-uniform-bytes]
@racket[runtime-effect->shader]
@racket[runtime:runtime-effect->shader]
@racket[runtime-effect->color-filter]
@racket[runtime:runtime-effect->color-filter]
@racket[runtime-effect->blender]
@racket[runtime:runtime-effect->blender]
@racket[runtime-uniform?]
@racket[runtime:runtime-uniform?]
@racket[runtime-uniform-name]
@racket[runtime:runtime-uniform-name]
@racket[runtime-uniform-offset]
@racket[runtime:runtime-uniform-offset]
@racket[runtime-uniform-type]
@racket[runtime:runtime-uniform-type]
@racket[runtime-uniform-count]
@racket[runtime:runtime-uniform-count]
@racket[runtime-uniform-byte-size]
@racket[runtime:runtime-uniform-byte-size]
@racket[runtime-uniform-array?]
@racket[runtime:runtime-uniform-array?]
@racket[runtime-uniform-color?]
@racket[runtime:runtime-uniform-color?]
@racket[runtime-uniform-half-precision?]
@racket[runtime:runtime-uniform-half-precision?]
@racket[runtime-child?]
@racket[runtime:runtime-child?]
@racket[runtime-child-name]
@racket[runtime:runtime-child-name]
@racket[runtime-child-kind]
@racket[runtime:runtime-child-kind]
@racket[runtime-child-index]
@racket[runtime:runtime-child-index]
@racket[exn:fail:skia-sksl?]
@racket[runtime:exn:fail:skia-sksl?]
@racket[exn:fail:skia-sksl-kind]
@racket[runtime:exn:fail:skia-sksl-kind]
@racket[exn:fail:skia-sksl-source]
@racket[runtime:exn:fail:skia-sksl-source]
@racket[exn:fail:skia-sksl-diagnostics]
@racket[runtime:exn:fail:skia-sksl-diagnostics]
@racket[blender?]
@racket[runtime:blender?]
@racket[make-blend-mode-blender]
@racket[runtime:make-blend-mode-blender]
@racket[paint-blender]
@racket[runtime:paint-blender]
@racket[paint-set-blender!]
@racket[runtime:paint-set-blender!]
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
