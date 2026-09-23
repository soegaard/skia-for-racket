# API reference — version 0.2.0

Import `(require skia)`, or `"main.rkt"` from the extracted root. The bitmap
bridge is a separate `(require skia/bitmap)` module. Signatures below use
square brackets for optional positional arguments and show keyword defaults.
No pointer or unsafe FFI declarations are exported by the public collection.

## Conventions

Coordinates accept finite real numbers within the checked C-float range.
Lengths, radii, stroke widths, and rectangle extents must be nonnegative.
Native geometry uses single-precision floats, not arbitrary-precision Racket
numbers. Surface/image dimensions must be exact integers from 1 to 32768 and
must respect the byte limit. Zero-area drawing rectangles are allowed.

The initial coordinate system has x right, y down, origin at the top left.
Rectangles always use `(x y width height)`. Mutating/drawing operations return
void unless another return value is described. Predicates accept any value.
Native resources are thread-confined; see the ownership section.

## Colors

```racket
(rgba red green blue alpha) ; transparent immutable structure, four bytes
(rgb red green blue)       ; equivalent to (rgba red green blue 255)
(rgba? value)
(rgba-red c) (rgba-green c) (rgba-blue c) (rgba-alpha c)
(color? value)
(color->rgba value)
(color->argb value)         ; unsigned integer #xAARRGGBB
```

Every channel, including alpha, is an exact byte. Accepted color inputs:

| Input | Interpretation |
|---|---|
| `rgba` value | Straight RGBA, not premultiplied |
| `"#RRGGBB"` | Opaque hex color |
| `"#RRGGBBAA"` | Hex color with alpha last |
| Integer from 0 to #xffffffff | Packed #xAARRGGBB, alpha first |
| Named symbol | One of the names below |

Names: `transparent`, `black`, `white`, `red`, `green`, `blue`, `yellow`,
`cyan`, `magenta`, `gray`, `grey`, `orange`, `purple`. `green` is #008000;
`gray`/`grey` is #808080. Hex digits are case-insensitive. Named strings,
three-digit hex, normalized float channels, and CSS color expressions are not
accepted. `color?` validates without loading the native library.

## Native library diagnostics

```racket
native-package-version       ; "3.119.1"
(skia-check!)                ; load, check milestone, resolve required symbols
(skia-available?)            ; #t if skia-check! succeeds; #f on load failure
(skia-native-version)        ; string "119.<native increment>"
(skia-native-library-path)   ; selected filename or system loader name
```

Native loading is lazy. `skia-check!` raises an exception with loader details;
`skia-available?` suppresses that exception. Failure is cached in the process's
loading promise. Start a new process after fixing a load error. The version
string is the native Skia milestone/increment, not the NuGet package version.
Do not interpret the milestone probe as full binary compatibility validation.

## Ownership and limits

```racket
(skia-resource? value)  ; surface, paint, path, image, typeface, font; not borrowed canvas
(skia-closed? resource-or-canvas)
(skia-close! resource)
(call-with-skia-resource resource procedure-of-one-argument)
(with-skia ([name expression] ...) body ...)
current-skia-byte-limit ; parameter, default (* 256 1024 1024)
```

Each owned wrapper has one lifetime cell. Closing invalidates aliases before
calling its native destructor. Explicit closure is idempotent. A live canvas
keeps its owning surface reachable, but cannot prevent explicit surface
closure; subsequent canvas operations then raise instead of using freed memory.
Passing a canvas to `skia-close!` is an error.

`with-skia` is sequential: later bindings may use earlier bindings. Cleanup
occurs in reverse order after normal return, an exception, or a later
constructor failure. Body return values are preserved. It uses continuation
barriers, so re-entering an expired resource scope is unsupported. The
procedure form has the same semantics and receives its resource as an argument.
Do not escape by terminating the entire process and expect dynamic cleanup.

GC finalization is a fallback; neither immediate reclamation nor custodian
resource management is provided. Every native resource may only be used or
explicitly closed on its creating Racket thread. Type predicates, immutable
metadata accessors, and `skia-closed?` do not access native memory.

The byte limit guards requested surface/pixel sizes and copied encoded output,
not total memory consumption or the encoder's internal allocations. Set it
with `parameterize` before allocating or reading larger images.

## Surfaces and PNG

```racket
(surface? value)
(make-surface width height #:background [color 'transparent])
(surface-width surface)
(surface-height surface)
(surface-canvas surface) ; borrowed canvas, shares the surface's graphics state
(surface-pixel surface x y) ; one rgba value, exact pixel indices
(surface->rgba-bytes surface #:premultiplied? [flag #f])
(surface->png-bytes surface #:compression [level 6])
(save-png surface path #:exists [mode 'error] #:compression [level 6])
```

A new surface is initialized to its background color; it never exposes
uninitialized pixels. Internal storage is CPU RGBA8888 with premultiplied
alpha and no explicit color-space object. Pixel readback copies data into
ordinary Racket byte strings; default output is straight RGBA. Rows are
contiguous with stride `4*width`, starting at the top row.

PNG is encoded by Skia's native PNG encoder, not `racket/draw`. Compression is
an exact integer from 0 through 9. All PNG scanline filters are enabled. PNG
byte output contains the full image. `save-png` accepts only `'error` (default,
refuse existing files) or `'replace` (explicitly overwrite). Encoding finishes
before opening the output file; filesystem write failures are still possible,
and file writes are not transactional. Parent directories are not created.
The two pixel-output flags must be booleans.

## Paints

```racket
(paint? value)
(make-paint #:color [color 'black]
            #:style [style 'fill]
            #:stroke-width [width 1]
            #:antialias? [flag #t]
            #:cap [cap 'butt]
            #:join [join 'miter]
            #:miter-limit [limit 4]
            #:blend-mode [mode 'src-over])
(paint-copy paint)
(paint-color paint) ; rgba value
(paint-set-color! paint color)
(paint-set-style! paint style)
(paint-set-stroke-width! paint width)
(paint-set-antialias! paint boolean)
(paint-set-cap! paint cap)
(paint-set-join! paint join)
(paint-set-miter-limit! paint limit)
(paint-set-blend-mode! paint mode)
```

Styles: `'fill`, `'stroke`, `'stroke-and-fill`. Caps: `'butt`, `'round`,
`'square`. Joins: `'miter`, `'round`, `'bevel`. Width 0 requests Skia's hairline
stroke semantics, not an invisible stroke. The default is fill; request stroke
explicitly when drawing open curves. `draw-line` uses line-stroke semantics.
Paints are mutable; `paint-copy` creates an independently owned copy.

Blend modes:

```racket
'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in 'src-out 'dst-out
'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten
'color-dodge 'color-burn 'hard-light 'soft-light 'difference 'exclusion
'multiply 'hue 'saturation 'color 'luminosity
```

The wrapper maps these names to the pinned native enumeration. It does not
implement separate blend math in Racket. Alpha is supplied through the paint
color; there is no separate normalized-alpha API.

## Canvas state and transforms

```racket
(canvas? value)
(canvas-clear! canvas color)
(canvas-save! canvas)          ; previous save count
(canvas-save-count canvas)     ; current count, initially 1
(canvas-restore! canvas)
(canvas-restore-to-count! canvas count)
(call-with-canvas-state canvas thunk)
(with-canvas-state canvas body ...)
(canvas-translate! canvas dx dy)
(canvas-scale! canvas sx [sy sx])
(canvas-rotate! canvas degrees)
(canvas-rotate-radians! canvas radians)
(canvas-skew! canvas kx ky)
(canvas-reset-transform! canvas)
```

Transforms concatenate onto the current matrix. Scaling can be negative or
zero. `canvas-skew!` takes shear factors, not angles. Reset changes the matrix,
not clipping or previously drawn pixels. Clear replaces pixels within the
current clip with the specified color and ignores the current transform.
To clear the entire surface, do so before introducing clipping or restore the
unclipped base state first.

Save/restore retains the matrix and clip, not paints and not pixel history.
Restoring the base state itself is an error. `restore-to-count!` accepts only
an existing positive count at or above the active scope's protected floor.
A scoped state reserves its save frame, restores its entry count on exit, and
removes extra saves made in the body. Manual restore cannot pop that reserved
frame, including through another canvas alias. Closing the surface in the body
is allowed; state cleanup then avoids accessing the invalidated pointer.

## Clipping

```racket
(canvas-clip-rect! canvas x y width height
                   #:operation [operation 'intersect]
                   #:antialias? [flag #f])
(canvas-clip-path! canvas path
                   #:operation [operation 'intersect]
                   #:antialias? [flag #f])
```

Operation is `'intersect` or `'difference`. The shape is interpreted using the
current transform. Clipping changes future drawing; it does not retroactively
edit pixels. Use a state scope to make a temporary clip. Path clipping uses the
path's fill rule, not a paint's stroke settings.

## Drawing geometry

```racket
(draw-paint canvas paint)
(draw-line canvas x0 y0 x1 y1 paint)
(draw-rect canvas x y width height paint)
(draw-rounded-rect canvas x y width height radius-x radius-y paint)
(draw-circle canvas center-x center-y radius paint)
(draw-oval canvas x y width height paint)
(draw-path canvas path paint)
(draw-polygon canvas points paint #:closed? [flag #t])
```

`draw-paint` covers the current clip. Other operations apply the canvas
transform and clipping. `points` is a nonempty list of two-element lists,
for example `'((10 10) (90 20) (40 80))`. The polygon helper constructs and
closes a temporary path automatically. Pass `#:closed? #f` for an open polyline;
use a stroke paint to avoid implicit filled-contour closure by the rasterizer.
Rectangles with excessively large corner radii use Skia's radius fitting.

## Paths

```racket
(skia-path? value)
(make-path [commands '()] #:fill-rule [rule 'winding])
(path-copy path)
(path-move-to! path x y)
(path-line-to! path x y)
(path-quad-to! path control-x control-y x y)
(path-cubic-to! path c1x c1y c2x c2y x y)
(path-close! path)
(path-reset! path)
(path-add-rect! path x y width height #:direction [direction 'cw])
(path-add-oval! path x y width height #:direction [direction 'cw])
(path-add-circle! path x y radius #:direction [direction 'cw])
(path-bounds path)        ; FOUR VALUES: x, y, width, height
(path-tight-bounds path)  ; FOUR VALUES: x, y, width, height
(path-contains? path x y)
(path-fill-rule path)
(path-set-fill-rule! path rule)
```

The predicate is deliberately `skia-path?`, leaving Racket's filesystem
`path?` unshadowed. Paths are mutable and own their native object. `path-copy`
creates an independent copy. The command grammar is:

```racket
(move x y)
(line x y)
(quad control-x control-y x y)
(cubic c1x c1y c2x c2y x y)
(close)
```

Supply commands as Racket lists, normally quoted or quasiquoted. The native
path is cleaned up if a command is invalid. Fill rules are `'winding` or
`'even-odd`; directions are `'cw` or `'ccw` in the default y-down coordinates.
`path-reset!` clears geometry **and resets the fill rule to winding**.

Bounds are in path coordinates, independent of canvas transforms and paint
stroke widths. Ordinary bounds include Bézier control points; tight bounds
consider curve extrema. Neither reports the extent of a rendered stroke.
Containment tests the filled path interior, not stroke-distance hit testing.
For a list of bounds, use `(call-with-values (lambda () (path-bounds p)) list)`.

## Images

```racket
(image? value)
(image-width image)
(image-height image)
(surface-snapshot surface)
(rgba-bytes->image width height pixels #:premultiplied? [flag #f])
(image->rgba-bytes image #:premultiplied? [flag #f])
(draw-image canvas image x y
            #:sampling [mode 'nearest]
            #:paint [paint-or-false #f])
(draw-image-rect canvas image x y width height
                 #:sampling [mode 'linear]
                 #:paint [paint-or-false #f])
```

Images expose immutable pixel content but are owned resources that must be
closed. A snapshot remains valid after its source surface changes or closes.
RGBA input is copied, not borrowed, and must contain exactly `4*width*height`
bytes in top-to-bottom row order. In premultiplied input every RGB channel must
be at most alpha; invalid input is rejected. Output is copied as for surfaces.

Sampling is `'nearest` or `'linear`. The first drawing function places an image
at its natural size before the canvas transform. The second maps the **entire
source image** to the destination rectangle; there is no source-crop parameter.
The optional paint is passed to Skia for image compositing. A false paint
selects native defaults. This version has no encoded PNG/JPEG loading API.

## Typefaces, fonts, and simple text

### Typefaces

```racket
(typeface? value)
(make-typeface)
(typeface-from-family family
                      #:weight [weight 'normal]
                      #:width [width 'normal]
                      #:slant [slant 'upright])
(typeface-from-file path #:index [index 0])
(typeface-family-name typeface)
(typeface-weight typeface)
(typeface-width typeface)
(typeface-slant typeface)
```

A typeface is an owned native resource. `make-typeface` returns the platform
Skia default typeface. `typeface-from-family` asks Skia/platform font services
for a family and style. The returned face can be a platform-selected match, so
inspect `typeface-family-name`, `typeface-weight`, `typeface-width`, and
`typeface-slant` when the exact matched face matters.

`weight` accepts an exact integer from 0 through 1000 or one of:

```racket
'invisible 'thin 'extra-light 'light 'normal 'medium
'semi-bold 'bold 'extra-bold 'black 'extra-black
```

The named values map to 0, 100, 200, ..., 1000 respectively. `width` accepts
an exact integer from 1 through 9 or:

```racket
'ultra-condensed 'extra-condensed 'condensed 'semi-condensed 'normal
'semi-expanded 'expanded 'extra-expanded 'ultra-expanded
```

`slant` is `'upright`, `'italic`, or `'oblique`. `typeface-weight` and
`typeface-width` return the numeric native values; `typeface-slant` returns a
symbol.

`typeface-from-file` opens a local font file. `index` is an exact nonnegative
integer and selects a face in a collection where the native codec supports it.
The file must already exist. The wrapper passes an absolute NUL-terminated path
to the pinned native API and does not retain Racket path storage afterward.

### Fonts

```racket
(font? value)
(make-font [typeface #f]
           #:size [size 12]
           #:scale-x [scale-x 1]
           #:skew-x [skew-x 0]
           #:edging [edging 'antialias]
           #:hinting [hinting 'normal]
           #:subpixel? [flag #f]
           #:linear-metrics? [flag #f]
           #:embolden? [flag #f])

(font-size font)
(font-set-size! font size)
(font-scale-x font)
(font-set-scale-x! font scale-x)
(font-skew-x font)
(font-set-skew-x! font skew-x)
(font-edging font)
(font-set-edging! font edging)
(font-hinting font)
(font-set-hinting! font hinting)
(font-subpixel? font)
(font-set-subpixel! font boolean)
(font-linear-metrics? font)
(font-set-linear-metrics! font boolean)
(font-embolden? font)
(font-set-embolden! font boolean)
```

A font is an owned native `SkFont` wrapper. If no typeface is supplied,
`make-font` creates and retains a private default typeface for the lifetime of
the font wrapper. If the caller supplies a typeface, closing the font never
closes that wrapper. The native font retains what it needs from the face, so a
caller-supplied typeface wrapper may be closed after successful font creation.

`size` and `scale-x` must be positive finite scalars; `skew-x` is any checked
finite scalar. `edging` is `'alias`, `'antialias`, or `'subpixel-antialias`.
`hinting` is `'none`, `'slight`, `'normal`, or `'full`. The three boolean
options expose Skia's corresponding low-level font flags; they do not add a
layout or shaping engine.

### Metrics

```racket
(font-get-metrics font) ; -> font-metrics?
(font-metrics? value)
(font-metrics-top metrics)
(font-metrics-ascent metrics)
(font-metrics-descent metrics)
(font-metrics-bottom metrics)
(font-metrics-leading metrics)
(font-metrics-average-character-width metrics)
(font-metrics-max-character-width metrics)
(font-metrics-x-min metrics)
(font-metrics-x-max metrics)
(font-metrics-x-height metrics)
(font-metrics-cap-height metrics)
(font-metrics-underline-thickness metrics)
(font-metrics-underline-position metrics)
(font-metrics-strikeout-thickness metrics)
(font-metrics-strikeout-position metrics)
(font-metrics-spacing metrics)
```

`font-metrics` is an immutable Racket value copied from native metrics. In the
usual y-down canvas convention ascent/top are normally negative and
descent/bottom positive relative to the baseline. `spacing` is the value
returned by the native metrics call. Underline and strikeout positions or
thicknesses are `#f` when the native validity flags say that field is not
available; the remaining fields are numbers.

### Simple text, glyph IDs, and outlines

```racket
(draw-simple-text canvas text x y font paint)
(measure-simple-text font text #:paint [paint-or-false #f])
(simple-text-bounds font text #:paint [paint-or-false #f])
(font-text->glyphs font text) ; -> vector of exact glyph IDs
(font-char->glyph font char-or-unicode-scalar)
(font-glyph-path font glyph-id) ; -> skia-path? or #f
(simple-text-path font text [x 0] [y 0]) ; -> skia-path?
```

These functions intentionally say **simple text**. `text` must be a Racket
string and is encoded as UTF-8. The layer maps/draws the run through Skia's
low-level font API; it does **not** perform HarfBuzz-style shaping, bidi
reordering, line breaking, paragraph layout, or multi-font fallback. It is
appropriate for simple runs whose appearance does not require contextual
shaping. Complex scripts and full typography need a later shaping/layout API.

`draw-simple-text` places the run at `(x,y)`, where `y` is the text baseline,
and applies the current canvas transform and clip. The paint controls color,
style, stroke, antialiasing, and compositing exactly as for geometry.

`measure-simple-text` returns the native advance width. `simple-text-bounds`
returns four values `(x y width height)` for the measured run relative to its
origin. Supplying a paint allows native measurement to account for relevant
paint geometry such as stroking. A false paint requests native defaults.

`font-text->glyphs` returns a newly allocated Racket vector; no native buffer is
retained. `font-char->glyph` accepts either a Racket character or an exact
Unicode scalar value. Glyph ID 0 can represent a missing glyph. A typeface can
lack an outline for a glyph; in that case `font-glyph-path` returns `#f`.
`simple-text-path` returns a newly owned path containing the outlines Skia
produces for the simple text run at the supplied baseline origin.

## Racket bitmap bridge

Separate module `(require skia/bitmap)`:

```racket
(surface->bitmap surface) ; bitmap% with alpha and backing scale 1
(image->bitmap image)     ; bitmap% with alpha and backing scale 1
```

Both perform pixel copies and return an independent bitmap. Premultiplied
RGBA is reordered to premultiplied ARGB before `set-argb-pixels`. They load
`racket/draw`; importing the main drawing module alone does not. This bridge
does not provide a Skia `dc%`, zero-copy sharing, or vector interchange.
