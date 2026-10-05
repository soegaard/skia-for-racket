# Additional effects and composition — 0.66

This stage uses the pinned SkiaSharp 3.119.1 / Skia m119 C interface. It adds
factories without changing native pins, package minimums, RGBA defaults, or the
existing CPU/GPU/canvas callback lifetimes. Import `skia` or `skia/effects`.

## Public additions

```racket
(make-1d-path-effect path advance [phase 0] #:style [style 'translate])
(make-2d-line-path-effect width matrix)
(make-2d-path-effect matrix path)
(make-table-mask-filter bytes256)
(make-gamma-mask-filter gamma)
(make-clip-mask-filter minimum maximum)
(make-shader-mask-filter shader)
(make-fractal-noise-shader frequency-x frequency-y octaves [seed 0]
                          #:tile-size [size #f])
(make-turbulence-shader frequency-x frequency-y octaves [seed 0]
                       #:tile-size [size #f])
(make-empty-shader)
(shader-with-color-filter shader color-filter)
(make-blender-shader blender destination-shader source-shader)
(make-arithmetic-blender k1 k2 k3 k4 #:enforce-premul? [enforce? #t])
(make-blender-image-filter blender background foreground #:crop [crop #f])

;; Existing API extended additively; exported through skia, not skia/effects.
(make-picture-image-filter picture #:target [target #f] #:crop [crop #f])
```

All results are ordinary owned resources. Their dependencies are copied or
retained by Skia during construction. Closing a source wrapper does not invalidate
a successfully constructed effect; passing an already-closed source is an error.
Resources retain the existing owner-thread restrictions.

### Stamping

A 1D effect repeats copied path geometry along the receiving path. Styles are
`'translate`, `'rotate`, and `'morph`. The native phase convention is retained;
it is not reinterpreted as an independently animated global translation. Advance
must remain positive after C-float rounding. An empty stamp is rejected.

2D effects use the existing immutable **affine** `matrix?` value to define their
lattice. Width must remain positive; a matrix with no representable inverse is
rejected. These factories do not introduce an alternate mutable matrix API.
Stamp control-point payloads are checked against `current-skia-byte-limit`.
Skia's effect expansion can still allocate additional geometry while drawing;
that parameter is not a total native-memory or iteration-cost guarantee.

### Coverage masks

Table masks copy exactly 256 bytes. Gamma is a positive finite C float. Clip
thresholds must satisfy `0 <= minimum < maximum <= 255`; requests that the native
factory would silently normalize are rejected instead.

These modify **coverage**, not color channels. A shader mask uses shader alpha.
Shader masks are an explicitly tracked C-shim extension, not a claim that the
pinned managed `SKMaskFilter` class exposes the same factory.

A mask made from a GPU-dependent shader inherits that context affinity. The
association is preserved through paints, copied paints, and `paint-mask-filter`
getters. CPU/PDF/SVG and wrong-context use reject instead of silently reading back.
Plain blur/table/gamma/clip masks stay CPU-independent, including when constructed
inside an unrelated GPU scope. Internal Skia mask evaluation is not claimed to be
GPU-only: the transfer ledger observes wrapper I/O, not all driver/Skia activity.

### Procedural and composed shaders

Noise frequencies must be nonnegative finite C floats; octaves are exact integers
from 0 through 255. Seeds are finite C floats. `#:tile-size` accepts `#f` or two
positive integer dimensions at most 32768. This is a periodicity hint, not an
allocated image. Small octave counts are normally useful; allowing 255 does not
imply that evaluating 255 octaves is inexpensive.

A fixed seed is expected to repeat within a fixed backend/configuration. It does
not promise universal CPU/GPU bit identity. Empty shaders are real native empty
shaders, not aliases for transparent paint. Composed shaders retain their child
resources, provenance, and any GPU dependencies.

### Blenders and image filters

Arithmetic follows the native premultiplied equation
`k1 * source * destination + k2 * source + k3 * destination + k4`, with native
clamping and optional premultiplied-color enforcement. `make-blender-shader`
accepts destination before source, matching the existing blend-shader ordering.
The same blender can also be attached through `paint-set-blender!`.

For `make-blender-image-filter`, a `#f` input is the dynamic source image, **not**
transparent black. An owned identity-source filter keeps optimizer-returned
source results representable without confusing native NULL with allocation
failure. Background and foreground retain the existing image-filter convention.

Picture `#:target` is a positive finite rectangle in picture coordinates. It
constrains drawing together with the picture's cull rect; it neither relocates nor
scales the picture. `#:crop` remains the separate output-crop operation.

## Document behavior

New resources contribute to the existing detached provenance summaries. Perlin,
empty shaders, and arithmetic blenders have explicit conservative PDF/SVG policies.
Other factories preserve the existing mask/path/filter/composition classifications.

Use `draw-output-group` for bounded fallback. `#:policy 'require-vector` rejects
incompatible effects. Needed blending backdrops belong inside the isolated group.
Annotations and semantic text must not silently disappear into fallback images.
The fixtures keep a vector marker and URL annotation outside each effect group.
This stage does not claim vector serialization for these effect families.

## Acceptance

`tools/validate-effects.py` requires the source manifest and reconciled capability
inventory, compiles all new Racket workers/examples, runs `run-tests.rkt`, generates
32 actual PDF/SVG documents, and inspects their raster bounds/vector/link structure.
`--require-renderers` requires Poppler and librsvg and compares independently
rendered document pixels against direct raster references. `--require-gpu` reruns
the effect pixel suite on an actual selected offscreen GPU and tests shader-mask
context affinity and deterministic cleanup. Missing selected backends fail.

The new `Effects` workflow selects Linux Mesa (Racket 8.18/9.3), with independent
document renderers, and Windows D3D12 WARP (Racket 9.3), with document structure.
All prior workflows remain. Branch protection and `CI required` aggregation are
not changed; this new workflow must also pass before accepting the stage.

## Rebuilt delivery limitation

The original chat's 0.66 download paths had no retained files. This is a rebuilt
replacement, not a byte-for-byte recovery. The authoring environment could execute
Python/source/patch checks but had no Racket executable, native Skia library, or
complete checkout. Exact retained files and source-context fragments were used
for patch construction. The delivery's external validation record describes the
checks actually run. Local and CI Racket/native acceptance remain required.

## Implementation references

The ABI and ownership review uses mono/skia revision
`40f75dc0051d141913c07c20d4c19590c7da0cb7`: `include/c/sk_patheffect.h`,
`sk_maskfilter.h`, `sk_shader.h`, `sk_blender.h`, `sk_imagefilter.h` and their
`src/c/` implementations. Factory behavior is described in
`include/effects/SkPerlinNoiseShader.h`, `SkImageFilters.h`, and
`src/effects/Sk1DPathEffect.cpp` / `SkTableMaskFilter.cpp` at that same revision.
