# Image-filter graphs

Image filters are immutable native graph nodes held by owned `image-filter?`
wrappers. They can use the pixels of the drawing operation as an input, or
supply their own image, picture, or shader source. The same filters attach to
existing paints; no separate drawing language is introduced.

## A graph with two branches

```racket
#lang racket/base
(require "main.rkt") ; or (require skia)

(with-skia ([surface (make-surface 320 180 #:background 'white)]
            [shadow (make-drop-shadow-only-image-filter
                     8 6 4 4 (rgba 0 0 0 120))]
            [graph (make-merge-image-filter (list shadow #f)
                                           #:crop '(0 0 300 160))]
            [paint (make-paint #:color 'blue #:image-filter graph)])
  (draw-rounded-rect (surface-canvas surface) 40 35 190 85 14 14 paint)
  (save-png surface "filter-example.png" #:exists 'replace))
```

`#f` in an input position means **the dynamic source of the operation**, not
transparent pixels. In this example, the first branch produces a shadow of
the rounded rectangle. The second branch supplies the original rectangle.
Merge draws branches in list order with source-over compositing: back to front.
A repeated node is permitted. A nonempty vector of inputs also works and is
copied during construction.

An image filter on a paint applies to each drawing operation separately. It
is not automatically applied once to a collection of unrelated draw calls.
To filter a whole recorded drawing, use `make-picture-image-filter` as the
source of the graph. Its source is the complete picture rather than the
primitive that subsequently triggers graph evaluation.

## Crops and coordinate systems

All rectangles are `(list x y width height)` or four-element vectors, **not**
left/top/right/bottom tuples. A crop is `#f` (no additional crop) or such a
rectangle with nonnegative extents; an empty crop produces transparent output.
Other source, destination, tile, and lens rectangles require positive extents.
Coordinates and sums must be representable by native C floats. Positive extents
that disappear at that precision are rejected. Negative coordinates are allowed.

`#:crop` is an output bound in the filter's local coordinate system. It does
not change the canvas clip, translate content to the origin, resize a PDF page,
or reserve padding around a raster group. It follows the canvas transform.

The existing blur, both shadow constructors, color-filter image node, and
composition now accept `#:crop`. Their calls without that keyword are unchanged.
A standalone `make-crop-image-filter` makes crop placement explicit:

```racket
(with-skia ([cut (make-crop-image-filter '(40 20 120 90))]
            [crop-then-blur (make-blur-image-filter 6 6 #:input cut)]
            [blur-then-crop (make-blur-image-filter 6 6 #:crop '(40 20 120 90))])
  ;; The first result can spread outside the crop as it blurs.
  ;; The second result is clipped after blurring.
  (void))
```

There is a pinned-backend qualification for **blur/convolution tiling**. With
`'clamp` or `'repeat` and a crop, m119 also uses that rectangle to establish the
input tile boundary, then crops the result. `'decal` crops the result only.
Blur retains its older no-crop tiling behavior. Convolution silently ignores
non-decal tiling without a crop in m119; this wrapper rejects that combination.
`'mirror` remains rejected for blur and convolution. The standalone crop uses
transparent/decal exterior only; no unexposed native `Crop` function is assumed.

## Combining and modifying inputs

```racket
(make-crop-image-filter rectangle #:input [input #f])
(make-offset-image-filter dx dy #:input [input #f] #:crop [crop #f])
(make-merge-image-filter inputs #:crop [crop #f])
(make-blend-image-filter mode background foreground #:crop [crop #f])
(make-arithmetic-image-filter k1 k2 k3 k4 background foreground
                              #:enforce-premul? [flag #t] #:crop [crop #f])
(make-compose-image-filter outer inner #:crop [crop #f])
```

Blend uses the existing blend-mode symbols. Its first input is background/Dst;
its second is foreground/Src. Arithmetic computes, per premultiplied channel,
`k1*foreground*background + k2*foreground + k3*background + k4`. Coefficients are
finite native floats; the optional enforcement clamps RGB to the resulting
alpha. Arithmetic coefficients operate on normalized channel values, unlike the
historical 0–255 bias convention of matrix convolution.

Composition substitutes `inner(source)` for the dynamic source consumed by
`outer`. It is not the same as merging two independent outputs. Composition
continues to require two actual `image-filter?` values; the other input-taking
constructors allow `#f` as documented above.

Valid identity operations, including zero offset, zero morphology radii,
zero displacement, and Src/Dst blends of the dynamic source, return usable
owned filters. The implementation supplies a private identity source node where
native simplification would otherwise return a null input. A `'clear` blend
produces empty pixels; it is not confused with the dynamic source.

## Morphology, displacement, convolution, and transforms

```racket
(make-dilate-image-filter radius-x radius-y #:input [input #f] #:crop [crop #f])
(make-erode-image-filter radius-x radius-y #:input [input #f] #:crop [crop #f])
(make-displacement-map-image-filter x-channel y-channel scale displacement color
                                   #:crop [crop #f])
(make-matrix-convolution-image-filter width height kernel
                                     #:offset [offset #f]
                                     #:gain [gain 1] #:bias [bias 0]
                                     #:tile-mode [mode 'decal]
                                     #:convolve-alpha? [flag #t]
                                     #:input [input #f] #:crop [crop #f])
(make-matrix-transform-image-filter matrix #:sampling [sampling 'linear]
                                   #:input [input #f] #:crop [crop #f])
(make-tile-image-filter source destination #:input [input #f] #:crop [crop #f])
(make-magnifier-image-filter lens zoom #:inset [inset 0]
                            #:sampling [sampling 'linear]
                            #:input [input #f] #:crop [crop #f])
```

Morphology radii are nonnegative. Dilate and erode operate on color channels as
well as alpha, rather than being exclusively outline operations. Displacement
channels are `'red`, `'green`, `'blue`, or `'alpha`; the displacement map and the
color image are separate inputs. Scale may be negative or zero.

Convolution's kernel is a **flat row-major** list or vector of exactly
`width*height` finite coefficients. Width and height are exact integers from 1
through the pinned limit of 2048. Large kernels can be extremely expensive;
this is a validity limit, not a performance recommendation. Offsets are exact
indices inside the kernel. `#f` selects `(quotient width 2, quotient height 2)`.
The coefficient data is copied; mutating or discarding the original vector does
not change the filter. Gain defaults to 1. Bias uses Skia's historical **0–255
channel scale**. With `#:convolve-alpha? #f`, source alpha is copied.

The convolution kernel dimensions and offsets are in **filter-layer pixels**,
not automatically scaled drawing units. A 3x3 edge effect therefore has a
resolution-dependent physical footprint. Use blur for a scale-aware Gaussian
operation; do not assume a 3x3 convolution has the same physical radius at 72
and 144 DPI. Large native kernels may use a quantized representation.

Matrix transform accepts an affine `matrix?` with a representable inverse. It
transforms filtered pixels before the enclosing canvas transform. It differs
from `path-transform`, which changes vector geometry. Sampling is `'nearest`
or `'linear`. Crop is applied after this transform. Tile repeats a positive
source rectangle to cover its positive destination rectangle. Magnifier zoom
must be at least 1, and inset is a nonnegative local-space distance.

## Explicit source nodes

```racket
(make-image-source-filter image #:source [source #f] #:destination [destination #f]
                          #:sampling [sampling 'linear] #:crop [crop #f])
(make-picture-image-filter picture #:crop [crop #f])
(make-shader-image-filter shader #:dither? [flag #f] #:crop [crop #f])
```

The image source rectangle defaults to the full image and must lie within it.
An omitted destination preserves the source rectangle's coordinates and scale.
An explicit destination remaps that subset. Picture and shader inputs retain
their native resources independently. Shader sources can be unbounded without
a crop; the destination's clip still limits evaluation. These nodes replace
the dynamic source, so a neutral `draw-paint` can trigger their evaluation:

```racket
(with-skia ([pic (call-with-picture 240 140
                  (lambda (c)
                    (with-skia ([p (make-paint #:color 'blue)])
                      (draw-circle c 80 60 30 p)
                      (draw-rect c 110 45 60 45 p))))]
            [source (make-picture-image-filter pic)]
            [blur (make-blur-image-filter 3 3 #:input source)]
            [paint (make-paint #:image-filter blur)])
  (draw-paint canvas paint)) ; canvas is a caller-owned live canvas
```

## Alpha-height lighting

Distant, point, and spot lights have diffuse and specular constructors:

```racket
(make-distant-lit-diffuse-image-filter direction color
 #:surface-scale [height 1] #:coefficient [kd 1] #:input [input #f] #:crop [crop #f])
(make-point-lit-diffuse-image-filter location color
 #:surface-scale [height 1] #:coefficient [kd 1] #:input [input #f] #:crop [crop #f])
(make-spot-lit-diffuse-image-filter location target color
 #:exponent [exponent 1] #:cutoff-angle [degrees 45]
 #:surface-scale [height 1] #:coefficient [kd 1] #:input [input #f] #:crop [crop #f])
(make-distant-lit-specular-image-filter direction color
 #:surface-scale [height 1] #:coefficient [ks 1] #:shininess [shininess 16]
 #:input [input #f] #:crop [crop #f])
(make-point-lit-specular-image-filter location color
 #:surface-scale [height 1] #:coefficient [ks 1] #:shininess [shininess 16]
 #:input [input #f] #:crop [crop #f])
(make-spot-lit-specular-image-filter location target color
 #:exponent [exponent 1] #:cutoff-angle [degrees 45]
 #:surface-scale [height 1] #:coefficient [ks 1] #:shininess [shininess 16]
 #:input [input #f] #:crop [crop #f])
```

These use input alpha as a height field; they are not general 3D scene lights.
Positions, targets, and directions are three-element lists/vectors. A direction
must be nonzero and a spot's location must differ from its target. Surface
scale is finite; the reflection coefficient is nonnegative. The wrapper accepts
shininess 1–128, spot exponent 0–128, and cutoff angle 0–90 degrees. Soft alpha
edges, for example from a blur, make the height response particularly visible.

## Ownership and validation

The constructors validate options before native loading and validate the
creator thread/liveness of every input before calling its native factory.
Native graph nodes retain their input references: closing a child wrapper does
not invalidate its already-constructed parent, and closing a graph wrapper does
not invalidate a paint that retained it. Do not keep using a closed wrapper
itself. Graphs are acyclic by construction; constructors never mutate an input.

Pointer arrays, kernels, geometry structs, and sampling options are temporary
synchronous arguments. Copied kernel bytes and input arrays are bounded by
`current-skia-byte-limit`. This does **not** bound all native evaluation memory,
filter work, total graph depth, or native image-cache allocation. Explicit
raster groups remain subject to the existing pixel-allocation checks.

## PDF, SVG, and raster output

| Destination | Applying these filter graphs |
|---|---|
| Raster surface | Evaluated by the native CPU backend. |
| PDF canvas | Passed to the native PDF backend. Some results are rasterized or expanded; being in a PDF does not make a filter vector. |
| SVG canvas | General filter graphs are not faithfully supported by the pinned serializer. Use a bounded `draw-rasterized` group. |

No general automatic SVG fallback or page-capability analyzer is introduced.
For SVG, keep filter inputs and the required compositing backdrop inside the
explicit raster group. Include enough padding for the intended effect. Crop
and padding have different roles: a crop limits filter output; padding provides
space in the enclosing raster in which that output can exist.

`examples/filter-graphs.rkt` deliberately routes native graphs to PDF and the
independent raster reference, but rasterizes each filter panel explicitly for
SVG. Each of its three SVGs has six 416x256 PNG panels. Checkerboards, borders,
and outlined labels remain vector. Its review page displays actual SVG files
beside independently drawn raster references, not their rasterizations.

## Pinned implementation references

Semantics were checked against Skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7` used by SkiaSharp 3.119.1:

- [C factories and ownership](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_imagefilter.cpp)
- [Filter contracts](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/effects/SkImageFilters.h)
- [Crop and blur tile behavior](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/effects/imagefilters/SkBlurImageFilter.cpp)
- [Convolution bounds, pixel units, copying, and tile behavior](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/effects/imagefilters/SkMatrixConvolutionImageFilter.cpp)
- [Src/Dst identity simplification](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/effects/imagefilters/SkBlendImageFilter.cpp)

These references describe the backend; they are not evidence of a live run of
this Racket implementation. See [validation instructions](FILTER-TESTING.md).
