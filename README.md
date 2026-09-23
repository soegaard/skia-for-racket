# Racket Skia — 0.2.0

An experimental standalone CPU-rendering binding to Skia through the native
SkiaSharp C ABI. It is a Racket collection named `skia`; its public API is
Racket-level and keeps the unsafe ABI layer private.

**Verification status:** the 0.1 drawing/image baseline was live-validated on
macOS/aarch64 with Racket 9.3.0.2: the doctor passed, all 57 source test cases
passed, and all three original examples rendered correctly. Version 0.2 adds
font and simple-text support. Those new paths were source/ABI checked in the
authoring environment, but could not be executed there because Racket and the
native library were unavailable. Run the included doctor and 69-case suite
locally before treating 0.2 as validated. See [TESTING.md](TESTING.md).

## Implemented

CPU RGBA surfaces; canvas save/restore, translation, scaling, rotation, skew,
and clipping; fills, strokes, circles, ovals, rounded rectangles, polygons,
quadratic and cubic Bézier paths; paint settings and blend modes; path bounds
and containment; immutable image snapshots and copied RGBA input; image
placement/scaling; native PNG encoding; default/family/file-backed typefaces;
configurable fonts and metrics; UTF-8 simple-text drawing/measurement; glyph
IDs and text/glyph outline paths; explicit/scoped resource cleanup and GC
fallback. An optional module copies pixels into a Racket `bitmap%`.

The unsafe ABI layer is private. Public resource wrappers do not expose raw
pointers. The source distribution contains no native binary or font files.

## Quick start on macOS

From the extracted directory:

```sh
cd racket-skia-0.2.0-20260923

RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

bash tools/install-native.sh &&
"$RACO" make main.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt &&
"$RACKET" tools/doctor.rkt &&
"$RACKET" run-tests.rkt &&
mkdir -p output &&
"$RACKET" examples/circle.rkt output/circle.png &&
"$RACKET" examples/gallery.rkt output/gallery.png &&
"$RACKET" examples/text.rkt output/text.png &&
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

`current-skia-byte-limit` defaults to 256 MiB per checked buffer/surface size.
It is **not** a process memory budget: encoding, snapshots, bridges, and copies
may consume additional memory. Surfaces are not custodian-memory-accounted.
Dimensions are restricted to 1 through 32768 on each axis.

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

No GPU/Metal/Vulkan support, text shaping/paragraph layout, gradients, filters,
dashes, SVG/PDF output, encoded-image-file decoding, arbitrary matrix concat,
source-rectangle cropping, font-manager/fallback API, or `dc<%>` compatibility
is implemented. Image input is RGBA bytes or surface snapshots. Text is the
low-level simple-text/glyph layer; complex-script shaping and bidirectional
layout require a later text layer.

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
examples/                circle, gallery, text, bitmap bridge
tests/                  pure, lifetime, and live-rendering suites
tools/                  explicit native installer and doctor
docs/                   API reference and ABI/source notes
```

See [API reference](docs/API.md), [ABI notes](docs/ABI.md),
[upstream sources](docs/SOURCES.md), and [third-party notice](NOTICE.md).
