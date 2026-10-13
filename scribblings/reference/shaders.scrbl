#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-shaders"]{Shaders and Gradients}

A @deftech{shader} supplies colors as a function of local drawing coordinates.
Attaching it to a paint changes the color source, not the geometry. Shader
resources are immutable: a transformed or combined shader is a new owned
wrapper. Combinations retain their native inputs rather than borrowing the
caller's wrappers, and preserve any GPU-context dependency.

@section[#:tag "skia-tile-modes"]{Tile Modes and Gradient Stops}

Tile modes specify values outside a gradient's unit interval or an image's
bounds. The @indexed-racket['clamp] mode extends edge colors;
@indexed-racket['repeat] repeats the interval; @indexed-racket['mirror] alternates
forward and reversed intervals; @indexed-racket['decal] uses transparent color
outside the interval. Image shaders select a separate mode for each axis.

Gradient colors are a list or vector of at least two @tech{color specification}s.
Positions, when supplied, are a list or vector of the same length, containing
nondecreasing drawing scalars between zero and one. Repeated positions are
permitted for sharp transitions. Omitted positions are evenly spaced. Skia
extends the first and last colors to interval endpoints when their positions
are inside the interval. The temporary color and position arrays together must
fit @racket[current-skia-byte-limit], at four bytes per color and per position.

The gradient is parameterized in local coordinates before the canvas transform.
These byte-color constructors do not accept a separate interpolation color space.
Destination color processing and finite native precision still affect rendered
pixels; a gradient is not a color-profile declaration.

@section{Constant and Linear Shaders}

@defproc[(make-color-shader [color color?]) shader?]{
Returns a shader that produces the same color at every coordinate. Its input
is normalized to the byte-valued color representation.
}

@defproc[(make-linear-gradient-shader [x0 real?] [y0 real?] [x1 real?] [y1 real?]
                                     [colors (or/c list? vector?)]
                                     [#:positions positions (or/c list? vector? #f) #f]
                                     [#:tile-mode tile-mode
                                      (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]) shader?]{
Returns a gradient whose parameter is zero at the first endpoint and one at
the second. The parameter is constant along lines perpendicular to the line
joining the endpoints. Both endpoints must be drawing scalars and must differ
after the wrapper's numeric conversion. Color and position restrictions are
listed in @secref["skia-tile-modes"]. Native construction can fail even when
wrapper checks pass, for example when precision makes geometry degenerate.

@racketblock[
(with-skia ([surface (make-surface 120 40)]
            [shader (make-linear-gradient-shader 0 0 120 0 '(red blue))]
            [paint (make-paint #:shader shader)])
  (draw-rect (surface-canvas surface) 0 0 120 40 paint)
  (save-png surface "gradient.png" #:exists 'replace))
]
}

@section{Radial, Sweep, and Conical Shaders}

@defproc[(make-radial-gradient-shader [x real?] [y real?]
                                     [radius (and/c real? (>/c 0))]
                                     [colors (or/c list? vector?)]
                                     [#:positions positions (or/c list? vector? #f) #f]
                                     [#:tile-mode tile-mode
                                      (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]) shader?]{
Returns a gradient centered at coordinates @racket[x] and @racket[y]. The
parameter is distance from the center divided by @racket[radius]. The radius
must be a positive drawing scalar. Colors, positions, and tiling follow
@secref["skia-tile-modes"].
}

@defproc[(make-sweep-gradient-shader [x real?] [y real?] [colors (or/c list? vector?)]
                                    [#:positions positions (or/c list? vector? #f) #f]
                                    [#:tile-mode tile-mode
                                     (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
                                    [#:start-angle start-angle real? 0]
                                    [#:end-angle end-angle real? 360]) shader?]{
Returns an angular gradient about coordinates @racket[x] and @racket[y]. Angles
are degrees, with zero on the positive x axis and increasing angles clockwise
in downward-y coordinates. Start and end angles map to parameters zero and one;
the start must be less than the end. Color stops and tiling follow
@secref["skia-tile-modes"]. This is an angular color field, not a stroked arc.
}

@defproc[(make-two-point-conical-gradient-shader
          [x0 real?] [y0 real?] [radius0 (and/c real? (>=/c 0))]
          [x1 real?] [y1 real?] [radius1 (and/c real? (>=/c 0))]
          [colors (or/c list? vector?)]
          [#:positions positions (or/c list? vector? #f) #f]
          [#:tile-mode tile-mode (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]) shader?]{
Returns a gradient described by two circles. The first circle corresponds to
parameter zero and the second to one. The native conical interpolation varies
both center and radius; it is not simply distance from one fixed center.
Radii must be nonnegative drawing scalars, and the two circles must differ.
A circle pair rejected by native Skia raises an exception rather than returning
@racket[#f]. Stop and tile restrictions are those in @secref["skia-tile-modes"].
}

@section{Image and Composite Shaders}

@defproc[(make-image-shader [image image?]
                           [#:tile-x tile-x (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
                           [#:tile-y tile-y (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
                           [#:sampling sampling (or/c 'nearest 'linear) 'nearest]) shader?]{
Returns a shader that samples @racket[image], with image pixels initially
aligned to local drawing units. The native shader retains the image, so closing
the caller's image wrapper does not invalidate the shader. A GPU image still
restricts the shader to its GPU context. Use @racket[shader-with-local-matrix]
to change the image's local placement or scale.
}

@defproc[(make-blend-shader [mode symbol?] [destination shader?] [source shader?]) shader?]{
Returns a shader that combines two shader outputs using a mode from
@secref["skia-blend-modes"]. The argument order is destination first, source
second, unlike a source-first description of the blending equation. This blend
happens between shaders; the paint's blend mode subsequently combines that
result with the drawing target.
}

@defproc[(shader-with-local-matrix [shader shader?] [matrix matrix?]) shader?]{
Returns a new shader whose local mapping includes @racket[matrix]. The source
shader is unchanged and retained by the result. For an invertible local matrix,
its inverse maps incoming coordinates to the source shader: a scale of two
therefore makes its pattern twice as large. Native rejection raises an exception;
a singular matrix is not promised to have a useful sampling interpretation.
}
