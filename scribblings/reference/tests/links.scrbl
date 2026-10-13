#lang scribble/manual

@(require (for-label racket/base skia
                     (prefix-in color: skia/color)
                     (prefix-in geometry: skia/geometry)
                     (prefix-in matrix: skia/matrix)))

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
