# Geometry completion — 0.67

Stage baseline: `91db8bdac2431588806e128914698c354c65b260` (0.66, with its host
and CI hotfixes). Native pins remain SkiaSharp 3.119.1 / m119 and HarfBuzzSharp
8.3.1.2. Racket 8.18 and draw-lib 1.22 remain the package minimums.

`skia/geometry` is an additive module, also re-exported by `skia`. It fills the
nine reviewed geometry/paint inventory groups without replacing existing path
snapshots, matrices, region values or ownership conventions. Its new functions
use the existing native library registry; requiring the module does not create a
GPU context or GUI window.

## Paths and arcs

```racket
(path-arc-to! path rx ry rotation x y
              #:large? [large? #f] #:direction [direction 'cw])
(path-rarc-to! path rx ry rotation dx dy
               #:large? [large? #f] #:direction [direction 'cw])
(path-arc-to-oval! path x y width height start sweep #:force-move? [move? #f])
(path-tangent-arc-to! path x1 y1 x2 y2 radius)
(path-add-arc! path x y width height start sweep)
```

Angles are in **degrees**, not radians. Endpoint arcs expose Skia's small/large
arc and clockwise/counterclockwise choices directly. Coordinates follow the
normal canvas convention; a positive oval sweep is clockwise in an unreflected,
y-down coordinate system. A transformed canvas can change the visual direction.

Radii must be nonnegative finite values. Zero-radius and coincident-point cases
retain the pinned native degenerate behavior, rather than inventing another arc
algorithm. Oval/tangent forms are distinct operations, not overloads inferred
from argument shape. `path-add-arc!` begins a new contour. The oval arc-to form
may connect to the existing contour unless `#:force-move? #t` is used. The tangent
form appends the tangent arc; it does not imply a final line to `(x2,y2)`.

```racket
(path-add-rect-start! path x y width height start #:direction [direction 'cw])
(path-add-rrect! path rounded-rect #:direction [direction 'cw] #:start-index [start 0])
(path-add-polygon! path points #:closed? [closed? #t])
(path-add-transformed! path other affine-matrix #:mode [mode 'append])
(path-rewind! path)
```

Rectangle starts are indices 0..3 in the native TL/TR/BR/BL ordering; rounded
rectangle starts are the native eight tangent-point indices. Out-of-range indices
are rejected, not reduced modulo the number of vertices. A polygon accepts a list
or vector of two-element points. Its coordinates are copied and converted before
submission; an empty polygon is a no-op that still checks the destination lifetime.

`path-add-transformed!` applies a checked 2D affine matrix while appending or
extending the destination; the source is unchanged. Singular affine matrices
remain allowed. The native C-float conversion is explicit. This does not provide
an arbitrary projective path transform. `path-rewind!` clears the native path for
reuse without invalidating earlier detached snapshots; its fill provenance is
read back from the actual native path instead of guessed.

## Recognition and inspection

```racket
(path-as-line path)          ; #f or #(#(x0 y0) #(x1 y1))
(path-as-oval path)          ; #f or #(x y width height)
(path-as-rectangle path)     ; #f or path-rectangle value
(path-as-rounded-rect path)  ; #f or existing rounded-rect value
(path-rectangle-bounds description)
(path-rectangle-closed? description)
(path-rectangle-direction description)
(path-verbs path)            ; raw move/line/quad/conic/cubic/close symbols
(path-segment-kinds path)    ; distinct line/quad/conic/cubic kinds present
(path-fill-bounds path)      ; checked path-ops tight-bounds rectangle
```

Recognition follows Skia's **native representation tests**, not general symbolic
shape equivalence. Unrecognized shapes return `#f`; output buffers are never read
on failure. The results are immutable values with no native pointers, and survive
source mutation or closure. Native path-ops tight bounds is separate from existing
control-point bounds and is not a paint/stroke/filter ink-bounds query.

Existing `path-segments`, `in-path-segments`, `path-contours`, `path->commands` and
measurement APIs are unchanged. Their snapshots already provide safe replay,
peek-ahead and repeated traversal. No mutable native iterator is exposed just to
mirror a low-level C operation.

## Conics and ordered boolean batches

```racket
(conic->quadratics p0 p1 p2 weight #:subdivisions [power 2])
(path-combine operations)
current-path-operation-limit  ; defaults to 4096
```

Conic conversion uses the pinned native routine. The weight must be finite and
strictly positive after C-float rounding. The deliberately bounded subdivision
exponent is 0..5: the output has at most `2^power` quadratics, each an immutable
vector of three immutable points. Adjacent triples share equal endpoint values.
The native result count is checked and used; this is not an adaptive
error-tolerance interface.

A boolean batch is a list/vector of `(operation path)` pairs, using `union`,
`difference`, `intersect`, `xor` or `reverse-difference`. The accumulator starts
empty. For example:

```racket
(with-skia ([outer (make-path)] [hole (make-path)])
  (path-add-rect! outer 0 0 100 60)
  (path-add-circle! hole 50 30 15)
  (with-skia ([result (path-combine
                       (list (list 'union outer) (list 'difference hole)))])
    (draw-path canvas result paint)))
```

Inputs remain locked for the synchronous native builder operation and are not
modified. The builder is always destroyed; only a completed owned result is
published. Empty input yields an owned empty path. Failure does not publish a
partial path. This intentionally offers a bounded batch rather than a persistent
mutable native builder.

The operation count and submitted control-point/verb payload obey limits before
builder construction. `current-skia-byte-limit` is a **submitted-payload bound**,
not a total native-memory limit or a time/complexity guarantee for path operations.

## Paint inspection, reset and geometric expansion

```racket
(paint-style paint)
(paint-stroke-width paint)
(paint-cap paint)
(paint-join paint)
(paint-miter-limit paint)
(paint-antialias? paint)
(paint-dither? paint)
(paint-set-dither! paint boolean)
(paint-blend-mode-or-src-over paint)
(paint-reset! paint)
(paint->fill-path paint path #:cull [cull #f] #:matrix [matrix matrix-identity])
```

The long blend getter name is deliberate. The pinned shim reports **SrcOver when
a custom blender cannot be represented as a blend-mode enum**. It is not an exact
custom-blender introspector; use the existing retained blender API when that
resource matters.

`paint-reset!` means **native SkPaint defaults**, not `make-paint`'s configured
wrapper defaults. It releases the native paint's child references, resets scalar
state, and clears the corresponding detached audit and GPU-affinity slots **after
native reset succeeds**. A separately obtained shader/mask/filter wrapper still
owns its own reference and retains its original context affinity. A reset paint
can be reused on another context because the old dependencies are gone, not
because affinity checks were disabled.

`paint->fill-path` returns **two values**: an owned result path and the native
`fillable?` result. In particular, a valid hairline result has `fillable? = #f`
but still returns its path; it is not treated as a failed allocation. Callers must
honor that flag instead of blindly filling the result. Path effects and stroke
geometry are expanded; color, shader, mask/image/color filters and blending are
**not baked into the resulting geometry**. The supplied matrix controls native
precision; it does not transform the returned coordinates. A cull rectangle is a
native optimization hint, not a replacement for a destination clip.

Explicit paint dithering receives a conservative PDF/SVG `needs-raster` policy.
Use the existing bounded output-group policy or disable dithering for vector-only
output. Reset and disabling dithering remove its audit feature. This does not add
a float-color/HDR API, which remains a later roadmap stage.

## Regions

```racket
(region-intersects-rect? region rectangle)
(region-quick-contains-rect? region rectangle)
(region-quick-reject-rect? region rectangle)
(region-quick-reject? a b)
(region-clear! region)
(region-set-rect! region rectangle)
(region-op-rect region rectangle operation)
(region-clipped-rectangles region clip)
(in-region-clipped-rectangles region clip)
(region-spans region y left right)
(in-region-spans region y left right)
```

Rectangles use `(x y width height)`. The existing sentinel-safe coordinate range
`[-1073741823,1073741823]` is retained. Span results are immutable `#(left right)`
vectors and use **half-open** intervals. A zero-width span window is valid and
empty; reversed bounds are rejected.

Clipped-rectangle and span iterators exist only inside a synchronous locked native
scope. Results are copied and bounded before returning; the sequence variants
snapshot immediately and can outlive or be traversed independently of the source.
Existing `region-rectangles` already provides safe repeated traversal, so no native
rewind handle is added.

The quick predicates are **sufficient tests, not exact converses**. `#f` from quick
rejection means “not proven disjoint,” not “definitely intersects.” Exact rectangle
intersection remains separately available. `region-op-rect` returns an independent
region; an empty result is not allocation failure. Mutating clear/set-rectangle
operations return void and do not rewrite earlier snapshots.

## Rounded rectangles

```racket
(make-empty-rounded-rect)
(make-nine-patch-rounded-rect x y width height left top right bottom)
(rounded-rect-normalize rounded-rect)
(rounded-rect-type rounded-rect)
(rounded-rect-inset rounded-rect dx dy)
(rounded-rect-outset rounded-rect dx dy)
(rounded-rect-offset rounded-rect dx dy)
(rounded-rect-transform rounded-rect affine-matrix)
```

The existing immutable specification remains public. Empty construction is pure.
Other new operations copy **native-normalized bounds and radii** out of temporary
native objects. The nine-patch arguments are corner-radius components, not image
nine-patch sampling. Inset/outset distances are nonnegative; offsets may be signed.
Types are `empty`, `rect`, `oval`, `simple`, `nine-patch`, or `complex`.

Not every affine image of an RRect is another native RRect. Unrepresentable
transforms return `#f`; the API does not silently flatten, approximate or rasterize
the shape. Use `path-add-rrect!` followed by the existing path transform when a
more general path representation is wanted.

## Acceptance and evidence

`tools/validate-geometry-completion.py` first checks the source manifest and
inventory, then the Python source/parser tests. It compiles `run-tests.rkt`, every
native suite named by its runtime-path declarations, and the new workers/example
before running regressions. This preserves the 0.66 recompilation fix without
deleting compiled directories.

The seven shared scenes cover arcs, tangent arcs, boolean holes, stroke outlines,
regions, rounded rectangles and polygons. The doctor exports **14 documents**
(seven PDF and seven SVG), with vector-only audit and require-vector groups. The
inspector rejects image/inline-image/foreign-object fallbacks, requires vector
geometry and links, and validates page dimensions. It recursively inspects PDF
Form XObjects; zero images are required even in nested resources.

`--require-renderers` adds real Poppler/librsvg renders. Interior/exterior probes,
a separate vector marker, bounded channel-error tests, and outside-scene checks
catch missing/misplaced/wrongly filled geometry while allowing limited viewer
edge-antialiasing differences. Synthetic inspector tests are not rendering
acceptance evidence.

`--require-gpu` selects real offscreen EGL, Metal or Direct3D rendering. It checks
seven scene captures with zero drawing readbacks and one explicit inspection
readback each. A separate reset test uses two sequentially entered contexts and
requires one intentional capture after cross-context reuse of a reset paint.
Both contexts must close. No physical display, GUI or performance claim is made.

The **Geometry completion** workflow adds Linux Mesa lanes for Racket 8.18/9.3
(with independent document renderers) and Windows D3D12 WARP 9.3 (with document
structure). All six existing workflows remain selected. The new seventh workflow
must pass too; the existing `CI required` aggregator and branch protection are not
silently changed.

The authoring environment can run Python and patch checks but has no Racket
executable, installed Skia library or complete source checkout. The accompanying
delivery validation record lists what actually ran. Racket compilation, native
pixels and the cross-platform matrix remain host/CI acceptance requirements.

## Pinned implementation sources

The ABI is defined by `mono/skia` commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`: `include/c/sk_path.h`,
`include/c/sk_region.h`, `include/c/sk_rrect.h`, `include/c/sk_paint.h`, their C
shim implementations, `src/pathops/SkOpBuilder.cpp`, and the existing m119
path/paint/RRect contracts. Public names and source equivalents are recorded in
`api/capabilities.json`; stage classification does not manufacture native execution
evidence.
