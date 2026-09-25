# Racket Skia — 0.20.0

An experimental standalone CPU-rendering binding to Skia through the native
SkiaSharp C ABI. It is a Racket collection named `skia`; its public API is
Racket-level and keeps the unsafe ABI layer private.

**Verification status:** versions 0.1 through 0.19 have been reported green on
macOS/aarch64 with Racket 9.3.0.2, SkiaSharp 3.119.1, and HarfBuzzSharp
8.3.1.2. This revision starts from the pushed 0.19 ICC-corrected baseline,
`257517a5c9f561b075c2fff23dd3ccad3be39d9a`, and preserves that correction.
The previous Unicode 15.1 conformance baseline remains **10274/10274
LineBreakTest** and **91707/91707 BidiCharacterTest**; it is not a new 0.20 run.

Version 0.20 adds owned codecs, fully composited GIF/WebP frame decoding,
all eight encoded-orientation transforms, and frame/loop/color-space metadata.
**The new Racket/native tests have not been run in the authoring environment.**
See [the 0.20 validation instructions](docs/CODEC-TESTING.md) for the complete
local build/test/doctor/visual sequence and the exact verification boundary.

## Animated frames and orientation

```racket
(with-skia ([codec (codec-from-file "animation.gif")])
  (printf "~a selectable frames\n" (codec-frame-count codec))
  (with-skia ([frame (codec->image codec #:frame-index 0)])
    ;; The frame is a detached full-canvas raster, normalized by default.
    (save-image frame "frame-0.png" 'png #:exists 'replace)))
```

`image-frame-from-bytes` and `image-frame-from-file` offer one-shot decoding.
Use `#:normalize-origin? #f` for encoded pixel coordinates. Existing image
constructors retain their previous behavior. Run `examples/advanced-codecs.rkt`
for the animation/orientation contact sheet. Detailed contracts are in
[the API reference](docs/API.md#animated-codecs-and-encoded-orientation).

## Implemented

CPU RGBA surfaces; canvas save/restore, translation, scaling, rotation, skew,
and clipping; fills, strokes, circles, ovals, rounded rectangles, polygons,
quadratic and cubic Bézier paths; paint settings and blend modes; path bounds
and containment; immutable image snapshots and copied RGBA input; image
placement/scaling; native PNG encoding; font-manager enumeration and fallback;
default/family/file-backed typefaces; configurable fonts and metrics; UTF-8
simple-text drawing/measurement; positioned text blobs; HarfBuzz-shaped glyph runs; mixed-script/bidi run layout and font fallback; Unicode 15.1 line breaking; paragraph wrapping/alignment/justification; glyph IDs and text/glyph
outline paths; owned shaders; color, linear, radial, sweep,
and conical gradients; image tiling; shader blending; PNG/JPEG/WebP encoded
image decode and encode; codec metadata probing; image subsets and source-rectangle
drawing; dash/corner/discrete/trim/composed path effects; path measurement,
segments and tangents; boolean path operations; color-matrix/blend/composed
color filters; blur mask filters; blur, drop-shadow, color, and composed image
filters; immutable pictures; picture recording/replay; picture rasterization; expanded path/SVG geometry; explicit/scoped resource cleanup and GC fallback. An optional module
copies pixels into a Racket `bitmap%`.

The unsafe ABI layer is private. Public resource wrappers do not expose raw
pointers. The source distribution contains no native binary or font files.

## Quick start on macOS

From the extracted directory:

```sh
cd racket-skia-0.19.0-20260925

RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
bash tools/install-harfbuzz.sh &&
bash tools/audit-symbols.sh &&
bash tools/audit-harfbuzz-symbols.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&
mkdir -p output &&
"$RACKET" examples/circle.rkt output/circle.png &&
"$RACKET" examples/gallery.rkt output/gallery.png &&
"$RACKET" examples/text.rkt output/text.png &&
"$RACKET" examples/text-blobs.rkt output/text-blobs.png &&
"$RACKET" examples/shaping.rkt output/shaping.png &&
"$RACKET" examples/layout.rkt output/layout.png &&
"$RACKET" examples/mixed-text.rkt output/mixed-text.png &&
"$RACKET" examples/line-breaking.rkt output/line-breaking.png &&
"$RACKET" examples/justification.rkt output/justification.png &&
"$RACKET" examples/bidi-controls.rkt output/bidi-controls.png &&
"$RACKET" examples/break-providers.rkt output/break-providers.png &&
"$RACKET" examples/script-justification.rkt output/script-justification.png &&
"$RACKET" examples/color-spaces.rkt output/color-spaces.png &&
"$RACKET" examples/gradients.rkt output/gradients.png &&
"$RACKET" examples/codecs.rkt output/codecs.png &&
"$RACKET" examples/path-effects.rkt output/path-effects.png &&
"$RACKET" examples/filters.rkt output/filters.png &&
"$RACKET" examples/pictures.rkt output/pictures.png &&
"$RACKET" examples/svg-paths.rkt output/svg-paths.png &&
"$RACKET" examples/bitmap-bridge.rkt output/bitmap.png
```

Adjust the two executable paths for another Racket installation. The examples
refuse to overwrite existing output files; choose a new output name on reruns.
The public `save-png` function supports an explicit `#:exists 'replace` option.

The installer downloads **SkiaSharp.NativeAssets.macOS 3.119.1** and extracts
`runtimes/osx/native/libSkiaSharp.dylib`. It does not install .NET, compile Skia,
use `sudo`, or run the downloaded library. The doctor command is the first
actual native load and rendering smoke test.

Racket 8.7+ is the declared source target; it has not been tested across that
range. A full Racket distribution normally supplies `draw-lib` and
`rackunit-lib`. Package installation below resolves the declared dependencies.

### Linux

With Racket on `PATH`, use the same commands with `racket` and `raco` instead of
the macOS paths. The installer selects x86-64 or ARM64 from the host architecture
and uses `SkiaSharp.NativeAssets.Linux.NoDependencies` 3.119.1. This initial
installer targets glibc Linux, not Alpine/musl, Windows, or cross-compilation.
A system runtime is still required; “NoDependencies” is the upstream package
name, not a promise that the binary works on every Linux distribution.

### Testing without a native library

```sh
racket run-tests.rkt --pure
```

This runs the color/validation/ABI-layout tests and the actual ownership layer
with synthetic native tokens. It does not exercise Skia. Without `--pure`, a
missing or incompatible library is an error, not a silently skipped test.

### Use an existing native library

```sh
export RACKET_SKIA_LIBRARY="/absolute/path/to/libSkiaSharp.dylib"
racket tools/doctor.rkt
```

The override is a **filename**, not a directory, and must match the pinned
3.119.1 ABI. It takes precedence over every other location; an invalid override
does not silently load another library. Otherwise the loader tries the local
`native/<platform>/` directory, then the system library search path.

The loader checks native milestone 119 and resolves every required symbol
before allocating objects. This is an early error check, not a proof that an
arbitrary custom milestone-119 build is ABI-compatible. Use the pinned package.
Library loading is lazy and performs no downloads. After a failed load or a
change to the environment variable, start a fresh Racket process.

An already downloaded NuGet archive can be installed offline:

```sh
bash tools/install-native.sh --archive /path/to/native-assets.3.119.1.nupkg
```

The installer validates the archive's package ID and version, retains the
original archive and metadata, and records hashes. Those recorded hashes are
not independent signature verification; HTTPS/NuGet is the download trust
boundary. Stop active renderers before reinstalling a native library.

## Native symbol audit

`tools/audit-symbols.sh` compares every `define-native` declaration in
`private/native.rkt` against the symbols actually exported by the selected
`libSkiaSharp`. Unlike `skia-check!`, which stops when symbol resolution first
fails, the audit reports all missing native names in one pass. Run it after
installing or replacing the native asset and before the doctor when changing
the FFI layer. It honors `RACKET_SKIA_LIBRARY` or accepts an explicit library
filename.

## Install as a Racket package

Installation is optional for the examples, which use relative module paths.
From this directory, after choosing the Racket executables:

```sh
"$RACO" pkg install --auto --name racket-skia "$PWD"
```

The collection can then be imported with:

```racket
(require skia)
```

The package is not published to a Racket catalog by this source distribution.
Package installation does not automatically download native code; run the
installer explicitly. Do not remove a linked source directory while the
package remains installed.

## First drawing

This program works as a file in the extracted root using `"main.rkt"`. Replace
that module path with `skia` after package installation.

```racket
#lang racket/base
(require "main.rkt")

(with-skia ([surface (make-surface 640 480 #:background 'white)]
            [fill (make-paint #:color "#326DE6")]
            [outline (make-paint #:color "#18243B"
                                  #:style 'stroke
                                  #:stroke-width 4)])
  (define canvas (surface-canvas surface))
  (draw-circle canvas 320 240 100 fill)
  (draw-circle canvas 320 240 100 outline)
  (save-png surface "circle.png"))
```

`with-skia` closes resources in reverse binding order, including when an
exception escapes or a later resource constructor fails. Resources can also
be managed explicitly with `skia-close!`; closing twice is harmless. GC
cleanup is a fallback, not a reason to retain thousands of native objects.
Do not return a live resource from a scope that closes that resource.

A canvas is borrowed from a surface, keeps that surface reachable, and is not
closed separately. Explicitly closing the surface invalidates every canvas
alias. A snapshot image owns its own reference and can outlive the original
surface. The wrappers reject use after closure before invoking C.

## Fonts and simple text

Version 0.2 adds owned typefaces and fonts without adding a shaping engine.
The deliberately explicit `draw-simple-text` name means exactly that: Skia
maps the UTF-8 run to glyphs and draws it at a baseline position, but this API
does not perform script shaping, bidirectional layout, line breaking, or font
fallback across a run.

```racket
(with-skia ([surface (make-surface 800 220 #:background 'white)]
            [face (make-typeface)]
            [font (make-font face #:size 48)]
            [paint (make-paint #:color "#18243B")])
  (define canvas (surface-canvas surface))
  (draw-simple-text canvas "Skia from Racket" 40 100 font paint)
  (define metrics (font-get-metrics font))
  (define advance (measure-simple-text font "Skia from Racket"))
  (printf "advance: ~a; ascent: ~a; descent: ~a\n"
          advance
          (font-metrics-ascent metrics)
          (font-metrics-descent metrics))
  (save-png surface "text.png"))
```

`make-typeface` selects the platform default. `typeface-from-family` requests
a named system family/style, while `typeface-from-file` opens a font file and
an optional collection index. `font-glyph-path` and `simple-text-path` expose
Skia's glyph outlines as ordinary owned `skia-path?` values. See the API
reference for ownership, metrics, and accepted style names.

## Shaders and gradients

Version 0.3 adds reference-counted shader resources and attaches them to ordinary
paints. The basic gradient API is intentionally Racket-level rather than a raw
C-array interface:

```racket
(with-skia ([s (make-surface 640 240 #:background 'white)]
            [gradient (make-linear-gradient-shader
                       40 0 600 0 '("#326DE6" "#16A598" "#F38C42")
                       #:positions '(0 1/2 1))]
            [paint (make-paint #:shader gradient)])
  (draw-rounded-rect (surface-canvas s) 40 40 560 160 24 24 paint)
  (save-png s "gradient.png"))
```

Tile modes are `'clamp`, `'repeat`, `'mirror`, and `'decal`. Image shaders can
tile an `image?` independently on x and y; blend shaders combine two shader
outputs using the same blend-mode names as paints. The native paint/shader relationship is reference counted, so closing the
supplied shader wrapper does not invalidate a paint that already retained it.
`paint-shader` returns a distinct owned native reference from the m119 C shim.
Shader-local matrices are not yet public API.

## Encoded images and codecs

Version 0.4 adds high-level encoded image I/O without exposing native codec or
stream pointers. Encoded bytes are copied into Skia-owned data, and encoded
output is copied back into ordinary Racket byte strings.

```racket
(with-skia ([source (make-surface 320 200 #:background 'white)]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source) 160 100 70 blue)
  (with-skia ([image (surface-snapshot source)])
    (define png  (image->png-bytes image))
    (define jpeg (image->jpeg-bytes image #:quality 90))
    (define webp (image->webp-bytes image #:lossless? #t))

    (define info (encoded-image-info-from-bytes jpeg))
    (printf "~a × ~a, ~a\n"
            (encoded-image-info-width info)
            (encoded-image-info-height info)
            (encoded-image-info-format info))

    (with-skia ([decoded (image-from-bytes png)])
      (save-image decoded "copy.webp" 'webp #:exists 'replace))))
```

`image-from-file` and `encoded-image-info-from-file` provide file-backed entry
points. The probe API reports format, dimensions, color/alpha type, encoded
orientation, and the pinned codec shim's frame-info count without materializing
a public image object. `draw-image-subrect` maps a source rectangle directly to
a destination rectangle; `image-subset` instead creates a new owned image.

The implemented encoders are PNG, JPEG, and WebP. JPEG exposes quality,
subsampling, and alpha behavior; WebP exposes quality and lossy/lossless mode.
See the API reference for the exact option symbols and the m119 frame-count
semantics.

## Path effects, measurement, and boolean operations

Version 0.5 extends the vector side of the library without exposing native path
pointers. Path effects are owned, reference-counted resources and can be attached
to ordinary stroke paints:

```racket
(with-skia ([s (make-surface 640 240 #:background 'white)]
            [effect (make-dash-path-effect '(12 7) 3)]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 6
                               #:cap 'round
                               #:path-effect effect)]
            [curve (make-path
                    '((move 40 180)
                      (cubic 140 20 480 260 600 60)))])
  (draw-path (surface-canvas s) curve paint)
  (save-png s "dashed-curve.png"))
```

Also available are corner, discrete, trim, compose, and sum effects. A paint
retains its own native path-effect reference, and `paint-path-effect` returns a
newly owned wrapper.

`make-path-measure` deliberately snapshots the supplied path. This differs from
raw `SkPathMeasure`, which stores a pointer to path data: mutating or explicitly
closing the original Racket path therefore cannot invalidate the measure.
Measurement is contour-based and supports length, closed-state queries,
position/tangent sampling, contour traversal, and segment extraction.

```racket
(with-skia ([p (make-path '((move 0 0) (line 100 0)))]
            [m (make-path-measure p)])
  (define-values (x y tx ty)
    (path-measure-position+tangent m 25))
  (printf "point=(~a,~a), tangent=(~a,~a)\n" x y tx ty))
```

Boolean operations return new owned paths: union, intersection, difference,
xor, reverse difference, simplification, and conversion to winding fill.

## Filters and effects

Version 0.6 adds three owned filter families that attach directly to paints and
can also be composed into native filter graphs:

```racket
(with-skia ([s (make-surface 420 220 #:background 'white)]
            [shadow (make-drop-shadow-image-filter
                     12 14 7 7 (rgba 20 35 60 150))]
            [paint (make-paint #:color "#F38C42" #:image-filter shadow)])
  (draw-rounded-rect (surface-canvas s) 90 55 220 110 22 22 paint)
  (save-png s "shadow.png"))
```

Color filters include 4×5 row-major color matrices, blend-mode filters, and
composition. Mask filters currently expose Gaussian blur with the four Skia
styles `'normal`, `'solid`, `'outer`, and `'inner`. Image filters include
Gaussian blur, drop shadow, shadow-only, color-filter wrapping, and composition.
An omitted image-filter input means “use the dynamically drawn source”; supplied
input filters are retained natively, so their Racket wrappers may be closed after
successful construction.

Paints accept `#:color-filter`, `#:mask-filter`, and `#:image-filter`. The three
getter functions return independently owned references, just like the shader and
path-effect getters. Image-filter blur defaults to `'decal` at its input edge;
the pinned m119 blur implementation does not support `'mirror`, so that tile
mode is rejected explicitly by this wrapper.

## Paths and scoped state

```racket
(with-skia ([s (make-surface 640 480 #:background 'white)]
            [p (make-paint #:color 'blue #:style 'stroke #:stroke-width 3)]
            [curve (make-path
                    '((move 0 0)
                      (cubic 60 -100 140 100 200 0)))])
  (define c (surface-canvas s))
  (with-canvas-state c
    (canvas-translate! c 200 240)
    (canvas-scale! c 1.5)
    (draw-path c curve p))
  (save-png s "curve.png"))
```

State scopes restore transforms, clipping, and save-stack depth after normal
return or an exception. They do not undo already drawn pixels. A protected
state cannot be popped by manual restore calls, even through another canvas
alias. Resource and state scopes use continuation barriers; resuming a
continuation into an expired native-resource scope is not supported.

## Coordinates and pixels

The initial origin is the top-left pixel corner. Positive x points right,
positive y points down, and positive degree rotation appears clockwise.
Rectangle arguments are **x, y, width, height**, not opposite corners.
`canvas-rotate!` uses degrees; `canvas-rotate-radians!` is explicit.

`rgba` channels, including alpha, are exact integers from 0 to 255. Inputs are
straight/unpremultiplied colors; the internal surface is premultiplied RGBA8888.
Accepted colors include `(rgb 255 0 0)`, `(rgba 255 0 0 128)`, `'red`,
`"#FF000080"` (RRGGBBAA), and `#x80FF0000` (AARRGGBB). String and integer
conventions intentionally differ and are documented in the API reference.

`surface->rgba-bytes` and `image->rgba-bytes` return copies of tightly packed,
row-major RGBA pixels, with straight alpha by default. Pass
`#:premultiplied? #t` for premultiplied output. No returned buffer aliases Skia
memory. Eight-bit premultiplication can lose color precision at low alpha;
fully transparent RGB values are not preserved by a premultiplied surface.

`current-skia-byte-limit` defaults to 256 MiB per checked buffer/surface or
encoded-input/output size. It is **not** a process memory budget: decoding,
encoding, snapshots, bridges, and copies may consume additional memory. Surfaces
are not custodian-memory-accounted. Dimensions are restricted to 1 through
32768 on each axis for public image resources.

## Interoperation with racket/draw

```racket
(require skia skia/bitmap)

(define bitmap
  (with-skia ([s (make-surface 320 240 #:background 'white)]
              [p (make-paint #:color 'blue)])
    (draw-circle (surface-canvas s) 160 120 80 p)
    (surface->bitmap s)))
```

The bridge copies and reorders premultiplied RGBA to premultiplied ARGB for
`bitmap%`. The resulting bitmap can outlive the surface. This is interoperability through pixels, not a Skia-backed `dc%`.

## Boundaries of this version

No GPU/Metal/Vulkan support, text shaping/paragraph layout, SVG/PDF output,
arbitrary matrix concat, shader-local matrices, advanced filter families/crop
rectangles, font-manager/fallback API, animation-frame decoding, orientation
normalization, public color-space/codec objects, or `dc<%>` compatibility is
implemented.
Encoded image support is currently high-level single-image decode/probe plus
PNG/JPEG/WebP encode. Text remains the low-level simple-text/glyph layer;
complex-script shaping and bidirectional layout require a later text layer.

Native resources are confined to the Racket thread that created them. The
implementation rejects cross-thread drawing and explicit destruction.
Synchronous CPU drawing and encoding can block the Racket scheduler; there is
no threaded or GPU renderer here. Create independent resources in workers
rather than sharing a resource. Parallel-place execution has not been tested.

## Layout

```text
main.rkt                 public drawing API
color.rkt                pure color values/conversions
bitmap.rkt               optional racket/draw pixel-copy bridge
private/native.rkt       lazy, version-checked C ABI binding
private/types.rkt        exact native struct layouts
private/lifetime.rkt     ownership cells and scoped cleanup
private/core.rkt         drawing/resource implementation
private/check.rkt        argument validation and option mapping
examples/                circle, gallery, text, gradients, codecs, path effects, filters, bitmap bridge
tests/                  pure, lifetime, and live-rendering suites
tools/                  explicit native installer and doctor
docs/                   API reference and ABI/source notes
```

See [API reference](docs/API.md), [ABI notes](docs/ABI.md),
[upstream sources](docs/SOURCES.md), and [third-party notice](NOTICE.md).


## Pictures and recording

Version 0.7 adds `picture?` and `picture-recorder?` wrappers over Skia's display-list recording API. A picture is an immutable recording of canvas
commands that can be replayed any number of times onto any canvas.

```racket
(with-skia ([picture
             (call-with-picture
              120 120
              (lambda (c)
                (with-skia ([p (make-paint #:color "#326DE6")])
                  (draw-circle c 60 60 36 p))))]
            [surface (make-surface 300 160 #:background "#F3F5F8")])
  (draw-picture (surface-canvas surface) picture #:x 20 #:y 20)
  (draw-picture (surface-canvas surface) picture #:x 160 #:y 20
                #:width 100 #:height 100)
  (save-png surface "pictures.png"))
```

For incremental use, `make-picture-recorder`,
`picture-recorder-begin-recording!`, and
`picture-recorder-finish-recording!` expose the underlying begin/finish cycle.
Use `picture->image` to rasterize a picture into an immutable `image?`.


## Expanded paths and SVG path data

Version 0.8 extends the path layer with relative commands (`path-rline-to!`,
`path-rquad-to!`, `path-rconic-to!`, `path-rcubic-to!`), direct conic
segments, rounded-rect insertion, path composition, point queries, and SVG
path-data conversion.

```racket
(with-skia ([p (svg-path->path "M 10 10 L 80 10 L 80 50 Z")])
  (path-add-rounded-rect! p 12 12 20 14 4 4)
  (define points (path-points p))
  (define svg-again (path->svg-path p))
  ...)
```

This stage is intentionally limited to SVG **path data** (`d=` content), not a
full SVG document parser or renderer.


## Font managers and positioned text blobs

Version 0.9 adds the native font-manager layer that future shaping code will
use for system font discovery and fallback, together with immutable positioned
`text-blob?` resources. This stage still does **not** perform shaping.

```racket
(with-skia ([fm (default-font-manager)])
  (define face (font-manager-match-character fm #\A #:languages '("en")))
  (when face
    (call-with-skia-resource
     face
     (lambda (tf)
       (with-skia ([font (make-font tf #:size 32)]
                   [paint (make-paint #:color 'black)]
                   [surface (make-surface 260 90 #:background 'white)])
         (define glyphs (font-text->glyphs font "AB"))
         (with-skia ([blob (make-positioned-text-blob
                            font glyphs '((0 0) (38 0)))])
           (draw-text-blob (surface-canvas surface) blob 20 58 paint)
           (save-png surface "positioned.png")))))))
```

`font-manager-match-character` can request a family/style and an ordered list
of BCP-47 language tags. A successful match returns a newly owned `typeface?`;
`#f` means the manager could not provide a matching face. `text-blob?` values
copy the supplied `SkFont` state into native blob storage and can therefore
outlive the Racket font/typeface wrappers used to construct them.

Text blobs take glyph IDs and **absolute positions within the run**. HarfBuzz
shaping is intentionally left for the next stage, where shaping output can be
converted to these positioned runs.


## HarfBuzz shaping

Version 0.10 adds an optional second native dependency: HarfBuzzSharp 8.3.1.2,
which packages HarfBuzz 8.3.1. Requiring `skia` still loads neither native
library eagerly. `make-shaper` is the first operation that needs HarfBuzz.

```racket
(with-skia ([face (make-typeface)]
            [font (make-font face #:size 42)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color "#326DE6")])
  (define run
    (shape-text shaper "office"
                #:language "en"
                #:features '("kern=1")))
  (draw-shaped-run canvas shaper run 40 90 paint))
```

`shape-text` returns an immutable `shaped-run?` containing glyph IDs, UTF-8
cluster byte offsets, explicit glyph positions, and final x/y advances. Optional
`#:direction`, `#:script`, `#:language`, and `#:features` arguments map directly
to HarfBuzz run properties. This stage shapes one font run; it does not yet do
Unicode bidi paragraph resolution, script/fallback run segmentation, line
breaking, or paragraph layout.


## Paragraph text layout

Version 0.11 builds a lightweight paragraph layer above shaped runs. `layout-text`
performs explicit-newline handling, Unicode line breaking, alignment,
and font-metric-based baseline placement. `draw-text-layout` draws the
result with the same shaper retained by the layout.

```racket
(with-skia ([font (make-font #:size 28)]
            [sh (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define layout
    (layout-text sh "A paragraph that wraps across several lines."
                 #:width 220
                 #:align 'center))
  (draw-text-layout canvas layout 20 20 paint))
```

A layout is a pure Racket value containing shaped lines and keeps its shaper
wrapper reachable. Explicitly closing that shaper invalidates subsequent drawing
from the layout. With `#:width`, version 0.13 selects greedy line fits from UAX
#14 opportunities; a span with no legal opportunity is not emergency-split and
may expand the reported layout width beyond `#:width`.

`layout-text` remains a single-run-per-line API: it does not perform UAX #9
mixed-direction bidi resolution or script/font run segmentation. With
`#:direction 'auto`, HarfBuzz guesses the shaping direction; start/end alignment
infers RTL from descending HarfBuzz cluster offsets and otherwise defaults to
LTR. Use `layout-mixed-text` when a line needs mixed-direction or fallback runs.


## Mixed-script and bidirectional layout

Version 0.12 adds a multi-run paragraph layer above `layout-text`. It resolves
ordinary mixed LTR/RTL text, segments by bidi level and HarfBuzz Unicode script,
and chooses fallback system fonts at grapheme-cluster boundaries.

```racket
(with-skia ([fm (default-font-manager)]
            [face (make-typeface)]
            [font (make-font face #:size 28)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define layout
    (layout-mixed-text shaper fm
                       "Racket שלום 123 مرحبا"
                       #:width 280))
  (draw-mixed-text-layout canvas layout 20 20 paint))
```

`mixed-text-layout?` exposes visual lines, and each `mixed-text-run?` exposes
its text, shaped run, visual x origin, bidi level/direction, script, and
fallback family (or `#f` for the base shaper). The layout is a pure Racket
value but retains references to the caller-owned base shaper and font manager;
both must remain live while drawing it.

The mixed bidi resolver now implements ordinary UAX #9 resolution plus explicit
embeddings, overrides, and isolates. `LRE/RLE/LRO/RLO/PDF` use the directional
status stack; `LRI/RLI/FSI/PDI` use isolating run sequences, including FSI's
first-strong direction rule and the specification's overflow limits. Formatting
controls are omitted from HarfBuzz input after they have affected resolved
levels. Paragraph levels are resolved before wrapping and line-specific L1 is
reapplied after UAX #14 chooses visual line boundaries, so an explicit scope can
span wrapped lines without being restarted.

## Unicode line breaking

Version 0.13 replaces the whitespace-only wrapping policy with the default UAX
#14 revision 51 rules over Unicode 15.1 `Line_Break` data. Both paragraph APIs
can therefore wrap unspaced CJK text and respect opening/closing punctuation,
numeric context, non-breaking spaces, word joiners, Hangul, regional indicators,
emoji modifiers, and the Brahmic orthographic-syllable rules introduced in
Unicode 15.1. BK/CR/LF/NL hard separators form explicit layout lines.

The implementation uses the UAX #14 tailoring that keeps Racket default
grapheme clusters intact. SA text uses UAX #14's default AL/CM resolution in
the core resolver. Version 0.17 lets higher-level code supplement those breaks
with dictionary or hyphenation boundaries; emergency breaking inside otherwise-
unbreakable spans is still not synthesized.

## Paragraph justification

Version 0.14 adds `'justify` and `'justify-all` alignment to both paragraph
APIs. `'justify` fills wrapped non-final lines and leaves each paragraph's final
line at logical start; `'justify-all` also fills final and single lines. A
positive `#:width` is required for either mode.

Justification preserves HarfBuzz shaping and bidi/script/font-fallback run
boundaries. It expands only ordinary U+0020 inter-word spaces by shifting the
already-positioned glyphs. NBSP/NNBSP, CJK inter-character expansion, general
letter spacing, and Arabic kashida insertion are intentionally unchanged; those
require script- or language-specific policies beyond this stage.

## Unicode conformance tooling

Version 0.15 adds a development-time harness for the official Unicode 15.1
`LineBreakTest.txt` and `BidiCharacterTest.txt` corpora. The large upstream test
files are not vendored. Run `tools/run-unicode-conformance.sh` to download the
pinned files temporarily, or pass `--data-dir` to use an offline copy. The
line-break runner filters expected opportunities inside default grapheme
clusters to match this library's documented UAX #14 tailoring.

## Explicit bidirectional controls

Version 0.16 completes the explicit-control layer used by `layout-mixed-text`.
Embeddings, overrides, isolates, FSI, overflow behavior, bracket resolution in
isolating run sequences, and line-specific trailing resets are handled before
script/font segmentation. The controls themselves remain formatting metadata
and do not become drawable glyphs.

## External segmentation and hyphenation hooks

Version 0.17 adds `#:break-provider` to both paragraph APIs. A provider is a
procedure of two arguments, `(paragraph language)`, called once for each
hard-break-delimited paragraph when wrapping is enabled. It returns a list of
additional string indices or `layout-break-opportunity?` values. The indices
supplement normal UAX #14 opportunities and must fall on Racket default-
grapheme boundaries.

`make-layout-break-opportunity` can attach display-only text to a boundary. For
example, `(make-layout-break-opportunity 5 "-")` makes index 5 a legal break
and draws the hyphen only if that boundary is selected. This supports external
Thai/Lao/Khmer segmenters and language-specific hyphenators without building a
dictionary into this standalone Skia binding. In mixed bidi text the suffix
inherits the resolved level immediately before the break and does not alter the
logical paragraph's UAX #9 resolution.

## Script-aware justification

Version 0.18 extends `'justify` and `'justify-all` beyond U+0020 word spaces.
Han, Hiragana, Katakana, and Hangul runs gain inter-character opportunities
between adjacent CJK grapheme clusters, including compatible boundaries between
separate visual runs. Common punctuation is not turned into a stretch point.

Arabic runs use Unicode 15.1 Joining_Type data to find cursive boundaries where
U+0640 ARABIC TATWEEL can be inserted as display-only shaping material. The
logical line text and bidi paragraph remain unchanged; HarfBuzz reshapes the
justified display run, cluster offsets are mapped back to logical UTF-8
coordinates, and any small width remainder is absorbed at the same
cursive connections. Mixed lines distribute slack across word-space, CJK, and
Arabic opportunities instead of assigning it to one script. The candidate
selection is structural rather than a language-specific typographic ranking;
font-specific `jalt` policies and editorial kashida preferences remain outside
this stage.

## Color spaces and ICC color management

Version 0.19 adds explicit color-space metadata to the CPU image/surface path.
`make-srgb-color-space` and `make-linear-srgb-color-space` expose owned wrappers
around Skia's built-in spaces; gamma/equality helpers and transfer-function
conversion keep the native color-space object behind the Racket API.

ICC profiles can be imported from and exported to byte strings. Raster surfaces
and copied RGBA images accept `#:color-space`; snapshots retain that tag.
`surface->rgba-bytes` and `image->rgba-bytes` optionally take a destination
color space, so Skia converts pixels during CPU readback instead of merely
relabeling the channel bytes. Encoded-output ICC injection and arbitrary RGB
transfer/matrix construction are not part of this stage.
