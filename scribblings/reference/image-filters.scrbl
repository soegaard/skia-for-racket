#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/effects))

@title[#:tag "skia-image-filters"]{Image Filters}

@(declare-exporting skia)

An @deftech{image filter} processes drawing content, potentially using nearby
pixels and producing output beyond the original geometry. A @deftech{filter graph}
connects filters by their input slots. Attach its final filter with
@racket[paint-set-image-filter!] or the @racket[#:image-filter] option of
@racket[make-paint]. Construction does not execute the graph or change an image.

A false input slot denotes the dynamic source supplied when the graph is used,
not a transparent image and not a disabled branch. For example, two false
inputs to a blend node refer to the same source. A composition substitutes
one graph into another's source slots. A paint filter processes each drawing
operation, not everything already present on the canvas. Explicit source nodes retain
an image or shader.

Each constructor returns an owned filter and retains native references to its
inputs. Closing caller-owned input wrappers afterward is permitted. Retained
GPU-dependent content preserves its context restrictions. Operations require
open resources on their owning thread; native rejection raises an exception.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-filter-rectangles"]{Coordinates, Inputs, and Crops}

Filter coordinates are local drawing coordinates, transformed with the drawing
operation. Rectangles are lists or vectors of @tt{x, y, width, height}, not
left/top/right/bottom coordinates. Width and height are nonnegative. Source,
lens, and tile rectangles specifically require positive extents. Coordinates,
coefficients, and computed edges must be drawing scalars. Positive extents that
collapse after native rounding are rejected.

The optional crop constrains the filter node's output region. It is not a
canvas clip and does not move pixels. Cropping a child before a blur can produce
a different result from cropping the blur's output. The absence of a crop does
not imply an infinite pixel allocation. Native bounds, drawing clips, memory
limits, and output-backend restrictions still apply.

@defproc[(image-filter? [v any/c]) boolean?]{
Returns @racket[#t] for an image-filter resource and @racket[#f] otherwise.
A closed wrapper still satisfies the predicate. This does not determine whether
a particular output backend can preserve the filter without rasterization.
}

@section{Blur, Shadows, and Composition}

@defproc[(make-blur-image-filter
          [sigma-x (and/c real? (>=/c 0))]
          [sigma-y (and/c real? (>=/c 0))]
          [#:tile-mode tile-mode (or/c 'decal 'clamp 'repeat) 'decal]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a Gaussian blur of the input colors and alpha. At least one sigma
must be positive. Sigma is a standard deviation in each local axis, not a
hard support radius. Decal samples outside the input as transparent; clamp
extends edge samples and repeat tiles them. Mirror is rejected by this API.
Non-decal edge behavior should be used with an explicit crop; the native
legacy no-crop path does not provide the same crop-relative tiling guarantee.
The input and crop follow @secref["skia-filter-rectangles"].

@racketblock[
(with-skia ([filter (make-blur-image-filter 6 6)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 160 90 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 35 25 90 40 8 8 paint))
]

@reference-figure["blur-image-filter.png"
                  "A blue rounded rectangle blurred outward in both axes."]
}

@defproc[(make-drop-shadow-image-filter
          [dx real?]
          [dy real?]
          [sigma-x (and/c real? (>=/c 0))]
          [sigma-y (and/c real? (>=/c 0))]
          [color color?]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a colored, blurred shadow behind the original input.
The shadow is derived from input alpha, blurred by the two sigmas and offset
by @racket[dx] and @racket[dy]. Both sigmas may be zero for an unblurred shadow.
Offsets are local-coordinate displacements, not device-pixel offsets.
The crop can remove part of the shadow as well as the source.

@racketblock[
(with-skia ([filter
             (make-drop-shadow-image-filter 8 8 5 5
                                            (rgba 0 0 0 140))]
            [paint (make-paint #:color "#EFA02B" #:image-filter filter)]
            [surface (make-surface 180 100 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 40 25 90 45 8 8 paint))
]

@reference-figure["drop-shadow-filter.png"
                  "An orange rounded rectangle with a soft dark shadow displaced down and to the right."]
}

@defproc[(make-drop-shadow-only-image-filter
          [dx real?]
          [dy real?]
          [sigma-x (and/c real? (>=/c 0))]
          [sigma-y (and/c real? (>=/c 0))]
          [color color?]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns only the colored, blurred shadow, without the original input.
The shadow is derived from input alpha, blurred by the two sigmas and offset
by @racket[dx] and @racket[dy]. Both sigmas may be zero for an unblurred shadow.
Offsets are local-coordinate displacements, not device-pixel offsets.
The crop can remove part of the shadow as well as the source.
}

@defproc[(make-color-filter-image-filter
          [filter color-filter?]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a graph node applying a color filter to its input. The color filter
is retained. A false image input uses the dynamic source; it does not suppress
the color operation.
}

@defproc[(make-compose-image-filter
          [outer image-filter?]
          [inner image-filter?]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a graph that feeds @racket[inner] into the dynamic source slots of
@racket[outer]. Both arguments must be filters, not @racket[#f]. The optional
crop applies to the composed result. Swapping the arguments generally changes
the output.
}

@section{Graph Construction and Combining Inputs}

@defproc[(make-crop-image-filter
          [rectangle (or/c (list/c real? real? real? real?) (vector/c real? real? real? real?))]
          [#:input input (or/c image-filter? #f) #f]) image-filter?]{
Returns a filter that restricts its input to the specified rectangle.
With a false input, the rectangle crops the dynamic source. An empty rectangle
is allowed and produces no content.
}

@defproc[(make-offset-image-filter
          [dx real?]
          [dy real?]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter translating its input by the specified local displacement.
Zero offset is allowed and still returns an owned filter. The crop is applied
to the offset result.

@racketblock[
(with-skia ([shift (make-offset-image-filter 10 0)]
            [paint (make-paint #:color 'red #:image-filter shift)]
            [surface (make-surface 30 10)])
  (draw-rect (surface-canvas surface) 0 0 5 5 paint)
  (list (surface-pixel surface 2 2) (surface-pixel surface 12 2)))
]

The rectangle moves to the right; the false input slot receives that drawing.
}

@defproc[(make-merge-image-filter
          [inputs (or/c (listof (or/c image-filter? #f)) (vectorof (or/c image-filter? #f)))]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter drawing its inputs in order with source-over blending.
Later inputs are composited over earlier ones. The sequence must be nonempty,
fit the native signed-int count, and fit the pointer-array byte limit. Each
false entry draws the dynamic source again. The input sequence is copied.

@racketblock[
(with-skia ([shift (make-offset-image-filter 55 0)]
            [both (make-merge-image-filter (list #f shift))]
            [paint (make-paint #:color 'blue #:image-filter both)]
            [surface (make-surface 150 60 #:background 'white)])
  (draw-rect (surface-canvas surface) 15 15 30 30 paint)
  (list (surface-pixel surface 25 25) (surface-pixel surface 80 25)))
]

The original and translated drawings are both present.

@reference-figure["image-filter-merge.png"
                  "Two blue squares on a white background: the original square and a copy translated to the right by an image-filter graph."]
}

@defproc[(make-blend-image-filter
          [mode
           (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in 'src-out 'dst-out 'src-atop
            'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten 'color-dodge
            'color-burn 'hard-light 'soft-light 'difference 'exclusion 'multiply 'hue 'saturation
            'color 'luminosity)]
          [background (or/c image-filter? #f)]
          [foreground (or/c image-filter? #f)]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter blending foreground as the source and background as the
destination, using @secref["skia-blend-modes"]. The argument order is background
first, foreground second. Either false slot denotes the dynamic source.
An identity result still returns an owned filter.
}

@defproc[(make-arithmetic-image-filter
          [k1 real?]
          [k2 real?]
          [k3 real?]
          [k4 real?]
          [background (or/c image-filter? #f)]
          [foreground (or/c image-filter? #f)]
          [#:enforce-premul? enforce-premul? boolean? #t]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter computing @math{k1 S D + k2 S + k3 D + k4} per normalized
premultiplied channel, where @math{S} is foreground and @math{D} is background.
Results are clamped to the channel range. When @racket[enforce-premul?] is
true, RGB is additionally limited by the resulting alpha. With it false,
the caller can produce colors inconsistent with premultiplied alpha.
The inputs are retained and false slots denote the dynamic source.
}

@section{Morphology, Displacement, and Convolution}

@defproc[(make-dilate-image-filter
          [radius-x (and/c real? (>=/c 0))]
          [radius-y (and/c real? (>=/c 0))]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter taking the component-wise maximum over a rectangular
neighborhood. The radii are nonnegative local distances and may be zero.
This is a channel-wise morphology operation, not an expansion or contraction
of the original vector path. The native backend determines the raster
neighborhood after transforming the radii.

@racketblock[
(with-skia ([plain (make-paint #:color "#326DE6")]
            [filter (make-dilate-image-filter 6 6)]
            [filtered (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-circle (surface-canvas surface) 50 45 18 plain)
  (draw-circle (surface-canvas surface) 125 45 18 filtered))
]

@reference-figure["dilate-image-filter.png"
                  "Two blue circles, with the filtered circle visibly expanded by dilation."]
}

@defproc[(make-erode-image-filter
          [radius-x (and/c real? (>=/c 0))]
          [radius-y (and/c real? (>=/c 0))]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter taking the component-wise minimum over a rectangular
neighborhood. The radii are nonnegative local distances and may be zero.
This is a channel-wise morphology operation, not an expansion or contraction
of the original vector path. The native backend determines the raster
neighborhood after transforming the radii.

@racketblock[
(with-skia ([plain (make-paint #:color "#326DE6")]
            [filter (make-erode-image-filter 6 6)]
            [filtered (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rect (surface-canvas surface) 25 20 50 50 plain)
  (draw-rect (surface-canvas surface) 105 20 50 50 filtered))
]

@reference-figure["erode-image-filter.png"
                  "Two blue squares, with the filtered square visibly contracted by erosion."]
}

@defproc[(make-displacement-map-image-filter
          [x-channel (or/c 'red 'green 'blue 'alpha)]
          [y-channel (or/c 'red 'green 'blue 'alpha)]
          [scale real?]
          [displacement (or/c image-filter? #f)]
          [color (or/c image-filter? #f)]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter resampling the color input according to channels from the
displacement input. For normalized selected channel values @math{u} and
@math{v}, displacement is proportional to @math{scale (u - 1/2)} and
@math{scale (v - 1/2)}. The midpoint is neutral. Scale is signed, so a negative
value reverses displacements. A false input slot uses the dynamic source.
}

@defproc[(make-matrix-convolution-image-filter
          [width (integer-in 1 2048)]
          [height (integer-in 1 2048)]
          [kernel (or/c list? vector?)]
          [#:offset offset
           (or/c #f (list/c exact-nonnegative-integer? exact-nonnegative-integer?)
            (vector/c exact-nonnegative-integer? exact-nonnegative-integer?)) #f]
          [#:gain gain real? 1]
          [#:bias bias real? 0]
          [#:tile-mode tile-mode (or/c 'decal 'clamp 'repeat) 'decal]
          [#:convolve-alpha? convolve-alpha? boolean? #t]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a convolution filter with exactly @math{width height} row-major
kernel coefficients. The copied coefficient payload must fit the byte limit.
Offset selects the kernel's alignment and must lie within its dimensions;
false uses @math{(floor(width/2), floor(height/2))}. The weighted sum is scaled
by gain and then bias is added. Bias uses the native eight-bit channel scale:
a bias of 255 corresponds to one full normalized channel unit.

When @racket[convolve-alpha?] is true all channels are convolved. Otherwise
RGB is convolved in unpremultiplied form, the original alpha is restored,
and the result returns to premultiplied form. RGB is limited by the resulting
alpha. Non-decal tiling
requires an explicit crop; mirror is rejected. Unlike a color matrix, the
kernel combines neighboring samples rather than channels of one sample.

@racketblock[
(with-skia ([filter
             (make-matrix-convolution-image-filter
              3 3 '(0 -1 0 -1 5 -1 0 -1 0))]
            [paint (make-paint #:color "#EFA02B" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-circle (surface-canvas surface) 90 45 28 paint))
]

@reference-figure["matrix-convolution.png"
                  "An orange circle rendered through a sharpening three-by-three convolution kernel."]
}

@section{Placement and Explicit Sources}

@defproc[(make-matrix-transform-image-filter
          [matrix matrix?]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter transforming its input in local coordinates. The matrix
must have a representable inverse. The selected sampling applies while
resampling the transformed input. The optional crop bounds the transformed
result, not the original source.
}

@defproc[(make-image-source-filter
          [image image?]
          [#:source source
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f]
          [#:destination destination
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter that draws a retained image instead of the dynamic source.
The source defaults to the full image and must be a positive rectangle inside
it. A missing destination uses the source rectangle itself, preserving its
coordinates and scale; it does not automatically relocate a subset to the
origin. An explicit destination must also have positive extents.
Closing the caller's image wrapper does not invalidate the filter.
}

@defproc[(make-shader-image-filter
          [shader shader?]
          [#:dither? dither? boolean? #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns an image-filter source that evaluates the retained shader. It does
not filter the dynamic source. Dithering requests reduction of quantization
artifacts when supported by the destination. A crop is useful for bounding
otherwise unbounded shader content. Shader GPU dependencies remain in force.
}

@defproc[(make-tile-image-filter
          [source (or/c (list/c real? real? real? real?) (vector/c real? real? real? real?))]
          [destination (or/c (list/c real? real? real? real?) (vector/c real? real? real? real?))]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter repeating the source rectangle of its input across the
destination rectangle. Both rectangles require positive extents. This repeats
content; it does not scale one source rectangle to fill the destination.
The optional crop further restricts the result.
}

@defproc[(make-magnifier-image-filter
          [lens (or/c (list/c real? real? real? real?) (vector/c real? real? real? real?))]
          [zoom real?]
          [#:inset inset (and/c real? (>=/c 0)) 0]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a magnified view of the input inside the positive lens rectangle.
Zoom must be at least one after native rounding. Inset controls the width of
the transition around the magnified content, rather than moving the lens.
It is nonnegative. The optional crop bounds the result.
}

@section[#:tag "skia-lighting-from-alpha"]{Lighting from Alpha}

Lighting filters interpret input alpha as a height field, scaled by
@racket[#:surface-scale], and estimate normals from neighboring samples. They
compute a lit surface, not the input's original RGB illuminated in place.
Diffuse output uses Lambert-style lighting; specular output uses a highlight
exponent. The light color supplies RGB; its alpha is not a surface opacity.
Surface scale is a signed drawing scalar. Coefficient must be nonnegative
before conversion. The direction, location, and target use three drawing-scalar
coordinates. A distant light's direction must be nonzero after native rounding;
a spotlight's location and target must remain distinct after rounding. The
current two-dimensional drawing transform does not turn these into a
three-dimensional scene or camera model.

Specular shininess controls the highlight's concentration and ranges from 1
through 128. A spotlight's exponent controls angular concentration and ranges
from 0 through 128; its cutoff angle ranges from 0 through 90 degrees. These
three ranges apply after single-precision rounding. Input slots and optional
output crops follow @secref["skia-filter-rectangles"].

@defproc[(make-distant-lit-diffuse-image-filter
          [direction (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a diffuse lighting filter for a light with a fixed direction.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@defproc[(make-point-lit-diffuse-image-filter
          [location (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a diffuse lighting filter for a point light at the given
location. The direction to the light varies across the height field.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@defproc[(make-spot-lit-diffuse-image-filter
          [location (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [target (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:exponent exponent real? 1]
          [#:cutoff-angle cutoff-angle real? 45]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a diffuse lighting filter for a spotlight aimed from location
to target. Its exponent and cutoff angle control the angular falloff.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@defproc[(make-distant-lit-specular-image-filter
          [direction (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:shininess shininess real? 16]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a specular lighting filter for a light with a fixed direction.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@defproc[(make-point-lit-specular-image-filter
          [location (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:shininess shininess real? 16]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a specular lighting filter for a point light at the given
location. The direction to the light varies across the height field.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@defproc[(make-spot-lit-specular-image-filter
          [location (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [target (or/c (list/c real? real? real?) (vector/c real? real? real?))]
          [color color?]
          [#:exponent exponent real? 1]
          [#:cutoff-angle cutoff-angle real? 45]
          [#:surface-scale surface-scale real? 1]
          [#:coefficient coefficient (and/c real? (>=/c 0)) 1]
          [#:shininess shininess real? 16]
          [#:input input (or/c image-filter? #f) #f]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a specular lighting filter for a spotlight aimed from location
to target. Its exponent and cutoff angle control the angular falloff.
The shared constraints are specified in @secref["skia-lighting-from-alpha"].
}

@section{Custom Blending}

@(declare-exporting skia skia/effects #:use-sources (skia/effects))

@defproc[(make-blender-image-filter
          [blender blender?]
          [background (or/c image-filter? #f)]
          [foreground (or/c image-filter? #f)]
          [#:crop crop
           (or/c #f (list/c real? real? real? real?) (vector/c real? real? real? real?)) #f])
         image-filter?]{
Returns a filter using the supplied blender to combine foreground and
background. The foreground is the blender's source and the background is its
destination. The blender and explicit inputs are retained. False slots refer
to the dynamic source, including for identity combinations.
}


@section[#:tag "skia-picture-image-source"]{Picture Sources}

@(declare-exporting skia)

@defproc[(make-picture-image-filter [picture picture?]
                                    [#:target target (or/c list? vector? #f) #f]
                                    [#:crop crop (or/c list? vector? #f) #f]) image-filter?]{
Returns an owned image-filter source that renders a recorded picture. It retains
the picture independently of the caller's wrapper and ignores the dynamic
source supplied to the surrounding graph. This operation rasterizes picture
content for filtering; it does not guarantee vector replay on PDF or SVG.

The optional target is a four-element x, y, width, height list or vector with
positive extents and drawing-scalar coordinates. It selects the picture's
rasterization rectangle, not a fit-to-size transform of the recorded commands.
Omitting it uses the picture's native cull rectangle. The result is clipped to
both the target and the picture's cull rectangle. The optional crop uses the
common image-filter output-region rules. The source picture must be open
during construction; retained GPU dependencies keep their own affinity rules.
}

@section{Additional Visual Examples}

These examples show several graph nodes that transform, combine, or replace an image-filter input.

@racketblock[
(with-skia ([filter (make-offset-image-filter 55 20)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rect (surface-canvas surface) 20 15 45 35 paint))
]
@reference-figure["offset-image-filter.png"
                  "A blue rectangle shifted down and right by an offset image filter."]

@racketblock[
(with-skia ([shift (make-offset-image-filter 55 0)]
            [filter (make-blend-image-filter 'src-over #f shift)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 20 25 50 40 8 8 paint))
]
@reference-figure["blend-image-filter.png"
                  "A blue rounded rectangle combined with a translated copy by an image-filter blend node."]

@racketblock[
(with-skia ([shift (make-offset-image-filter 50 0)]
            [filter (make-arithmetic-image-filter 0 0.5 0.5 0 #f shift)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-circle (surface-canvas surface) 45 45 25 paint))
]
@reference-figure["arithmetic-image-filter.png"
                  "A blue circle and translated copy combined by an arithmetic image filter with equal source weights."]

@racketblock[
(with-skia ([filter (make-crop-image-filter '(65 20 60 50))]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rounded-rect (surface-canvas surface) 25 10 120 70 10 10 paint))
]
@reference-figure["crop-image-filter.png"
                  "Only the central rectangular portion of a larger blue rounded rectangle remains after cropping."]

@racketblock[
(with-skia ([color-filter
             (make-color-matrix-filter
              '(0 0 0 0 1  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0))]
            [filter (make-color-filter-image-filter color-filter)]
            [paint (make-paint #:color 'blue #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-circle (surface-canvas surface) 90 45 26 paint))
]
@reference-figure["color-filter-image-filter.png"
                  "A circle whose blue dynamic source has been converted to red by a color-filter image-filter node."]

@racketblock[
(with-skia ([filter (make-matrix-transform-image-filter
                     (matrix-compose (matrix-translate 75 10)
                                     (matrix-rotate-degrees 22)))]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)]
            [surface (make-surface 190 110 #:background 'white)])
  (draw-rect (surface-canvas surface) 20 35 60 35 paint))
]
@reference-figure["matrix-transform-image-filter.png"
                  "A blue rectangle translated and rotated by a matrix-transform image filter."]

@racketblock[
(with-skia ([shader (make-linear-gradient-shader 20 0 160 0 '(red yellow blue))]
            [filter (make-shader-image-filter shader #:crop '(20 15 140 60))]
            [paint (make-paint #:color 'white #:image-filter filter)]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-rect (surface-canvas surface) 0 0 180 90 paint))
]
@reference-figure["shader-image-filter.png"
                  "A bounded red-yellow-blue gradient produced by a shader image-filter source."]

@racketblock[
(with-skia ([source-surface (make-surface 40 30 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source-surface) 12 15 9 blue)
  (with-skia ([image (surface-snapshot source-surface)]
              [source (make-image-source-filter image)]
              [filter (make-tile-image-filter '(0 0 40 30) '(0 0 180 90)
                                              #:input source)]
              [paint (make-paint #:color 'white #:image-filter filter)]
              [surface (make-surface 180 90 #:background 'white)])
    (draw-rect (surface-canvas surface) 0 0 180 90 paint)))
]
@reference-figure["tile-image-filter.png"
                  "A small yellow-and-blue image repeated as tiles across a larger destination rectangle."]

@section{Further Visual Examples}

These examples isolate additional graph combinations and source filters.

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)]
            [filter (make-blur-image-filter 12 2)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)])
  (draw-circle (surface-canvas surface) 100 50 26 paint))
]
@reference-figure["blur-anisotropic-stage8.png"
                  "A blue circle blurred much more horizontally than vertically by unequal blur sigmas."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)]
            [filter (make-drop-shadow-only-image-filter
                     12 10 5 5 (rgba 32 52 78 170))]
            [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
  (draw-rounded-rect (surface-canvas surface) 45 22 90 48 10 10 paint))
]
@reference-figure["shadow-only-stage8.png"
                  "Only the soft dark shadow of a rounded rectangle is visible; the orange source itself is omitted."]

@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)]
            [blur (make-blur-image-filter 5 5)]
            [shift (make-offset-image-filter 45 20)]
            [filter (make-compose-image-filter shift blur)]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)])
  (draw-circle (surface-canvas surface) 45 42 20 paint))
]
@reference-figure["compose-filter-stage8.png"
                  "A blue circle is blurred and then translated down and to the right by a composed image-filter graph."]

@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)]
            [shift1 (make-offset-image-filter 55 0)]
            [shift2 (make-offset-image-filter 110 0)]
            [filter (make-merge-image-filter (list #f shift1 shift2))]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)])
  (draw-circle (surface-canvas surface) 30 50 17 paint))
]
@reference-figure["merge-three-stage8.png"
                  "Three equal blue circles appear in a row after merging the source with two translated filter inputs."]

@racketblock[
(with-skia ([surface (make-surface 240 100 #:background 'white)]
            [plain (make-paint #:color "#326DE6")]
            [dilate-filter (make-dilate-image-filter 6 6)]
            [erode-filter (make-erode-image-filter 6 6)]
            [dilate (make-paint #:color "#326DE6" #:image-filter dilate-filter)]
            [erode (make-paint #:color "#326DE6" #:image-filter erode-filter)])
  (draw-rect (surface-canvas surface) 20 25 45 50 plain)
  (draw-rect (surface-canvas surface) 97 25 45 50 dilate)
  (draw-rect (surface-canvas surface) 174 25 45 50 erode))
]
@reference-figure["morphology-stage8.png"
                  "Three blue rectangles compare the original, a visibly expanded dilation, and a visibly contracted erosion."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)]
            [filter
             (make-matrix-convolution-image-filter
              3 3 '(-2 -1 0 -1 1 1 0 1 2)
              #:bias 128)]
            [paint (make-paint #:color "#EFA02B" #:image-filter filter)])
  (draw-rounded-rect (surface-canvas surface) 45 22 110 56 10 10 paint))
]
@reference-figure["convolution-emboss-stage8.png"
                  "An orange rounded rectangle is converted into a light-and-dark embossed edge pattern by a convolution kernel."]

@racketblock[
(with-skia ([source-surface (make-surface 40 40 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source-surface) 20 20 13 blue)
  (with-skia ([image (surface-snapshot source-surface)]
              [filter (make-image-source-filter
                       image #:destination '(20 10 180 80)
                       #:sampling 'nearest)]
              [paint (make-paint #:image-filter filter)]
              [surface (make-surface 220 100 #:background 'white)])
    (draw-paint (surface-canvas surface) paint)))
]
@reference-figure["image-source-filter-stage8.png"
                  "An image-source filter enlarges a small yellow tile with a blue circle into a wide destination rectangle."]

@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)]
            [filter
             (make-matrix-transform-image-filter
              (matrix-compose (matrix-translate 105 58)
                              (matrix-rotate-degrees 24)
                              (matrix-translate -55 -30)))]
            [paint (make-paint #:color "#326DE6" #:image-filter filter)])
  (draw-rect (surface-canvas surface) 20 20 90 50 paint))
]
@reference-figure["matrix-transform-filter-stage8.png"
                  "A blue rectangle is translated and rotated by an image-filter matrix rather than by the canvas transform."]
