# Small remaining gaps — 0.78b

Package version: **0.78**. Starting GitHub commit:
`4a6082274e06456aa385fa9337c31528f2f44a4a` (Update release-scope).
The SkiaSharp 3.119.1 / m119 native pin and Racket 8.18 / draw-lib 1.22
minimums are unchanged. No GPU driver, native layout, or compiler is added.

## XYZ-D50 matrix operations

`color-space.rkt`, also re-exported by `main.rkt` (`skia`), provides:

```racket
(xyz-d50-concat a b)       ; -> immutable vector of nine finite coefficients
(xyz-d50-invert matrix)    ; -> immutable vector of nine finite coefficients or #f
```

Inputs are flat lists or vectors of exactly nine real coefficients in row-major
order, compatible with `named-xyz-d50`, `primaries->xyz-d50`, and
`color-space-xyz-d50`. Inputs are copied and rounded to binary32 before native
entry. Each input coefficient must satisfy the existing finite C-float boundary
(`-3.402823e38` through `3.402823e38`). Booleans, complex values, NaNs, infinities,
nested rows, and geometric 4-by-4 matrices are rejected. Both concatenation
arguments are checked before native loading. Named gamut symbols are not an
implicit argument convention: call `named-xyz-d50` explicitly.

`xyz-d50-concat` computes **a times b**. With column sample vectors, **b is
applied first**. Singular matrices are valid multiplication operands and a
singular result is allowed. A nonfinite native result raises an exception rather
than returning an infinity or NaN. This is the pinned native operation, not a
Racket double-precision approximation promised to match every binary32 result.

`xyz-d50-invert` returns `#f` when native inversion fails, including singularity
after binary32 rounding, or when no finite binary32 result is produced. It does
not impose a Racket determinant epsilon before calling Skia. A returned inverse
is not a condition-number estimate or a guarantee of numerical accuracy for an
ill-conditioned matrix. Underflow follows binary32 behavior. Invalid input
raises an argument exception; it is not confused with the `#f` failure result.

The implementation uses the existing 36-byte `sk_colorspace_xyz_t` layout and
the two pinned functions `sk_colorspace_xyz_concat` and
`sk_colorspace_xyz_invert`. Input and output buffers are distinct (skcms forbids
in-place inversion), rooted for the synchronous native call, and never exposed.
Returned values do not depend on a live color-space, canvas, or GPU context.
Requiring the module does not initialize the native library; valid arithmetic
calls require the pinned native library.

### Color-space meaning

Matrix arithmetic alone is **not** encoded-pixel color conversion. It does not
decode or encode transfer functions, premultiply alpha, clip, tone-map, perform
ICC intent selection, or change a surface's color-space metadata.

For already-linear, column-vector RGB samples, a basis conversion can be formed
from the source and destination RGB-to-XYZ-D50 matrices:

```racket
(define source (named-xyz-d50 'srgb))
(define destination (named-xyz-d50 'display-p3))
(define inverse (xyz-d50-invert destination))
(unless inverse (error 'example "destination has no finite inverse"))
(define source-linear->destination-linear
  (xyz-d50-concat inverse source))
```

A composed finite, nonsingular gamut can be supplied to `make-rgb-color-space`.
That constructor retains its own gamut validation; these arithmetic operations
do not relax it. Use the existing explicit image/raster conversion APIs to
convert stored samples.

## Null surfaces: intentionally excluded

The native `sk_surface_new_null` factory remains **intentionally excluded** and
unbound. This is an explicit release-scope decision, not a claim of equivalent
null-surface implementation or an increase in graphics feature parity.

The pinned implementation creates a `SkNoDrawCanvas`, reports unknown image
information, drops writes/drawing, and returns no image from an image snapshot.
It rejects nonpositive extents. Exposing that object as an ordinary Racket
`surface?` would introduce a storage-less surface with materially different
snapshot, readback, format, encoding, and output-target semantics. No consumer
requiring persistent null-surface ownership has been identified in this stage.
The existing scoped no-draw API covers the chosen diagnostic authoring task
without making promises about images or surface ownership that it cannot meet.

Use the existing public alternative:

```racket
(call-with-nodraw-canvas 320 200
  (lambda (canvas)
    (with-canvas-state canvas
      (canvas-translate! canvas 10 20)
      (with-skia ([paint (make-paint #:color (rgb 30 100 180))])
        (draw-rect canvas 0 0 80 40 paint)))))
```

The callback receives a borrowed `canvas?`, **not a `surface?`**. Its execution
backend is `nodraw`; no raster, GPU, PDF, or SVG output is claimed. It has no
public image snapshot/readback/encoding route. The borrow expires on callback
return or exception; retaining the Racket canvas value does not extend the
native lifetime. The existing conservative extent gate (integers 1 through
32768 and the nominal RGBA byte-limit check) is unchanged, despite no image
storage being produced. Zero/negative dimensions and invalid callbacks are
rejected before native entry.

Reconsider the exclusion only for a concrete persistent-null-surface consumer,
with a separately reviewed storage-less surface kind, ownership/closure rules,
borrowed-canvas lifetime, extent limits, snapshot/readback/encoding rejection,
and output-audit/backend behavior. Do not classify no-draw support as an
implementation of the native null-surface family.

## Acceptance and evidence

`tests/small-gap-pure-test.rkt` checks pre-native argument rejection, immutable
boundary copies, binary32 rounding, and the existing no-draw input gates.
`tests/small-gap-native-test.rkt` exercises matrix layout, order, independent
products, inverses, singularity/overflow, detached results, named gamuts, RGB
color-space integration, and actual native no-draw state/lifetime behavior.
Both suites are registered in `run-tests.rkt`. The focused example uses only
public APIs. Existing CPU CI therefore exercises these tests on its declared
platforms, including the minimum Racket version; defining that integration is
not a claim that a particular new run has passed.

```bash
python3 tools/validate-small-gaps.py --racket /absolute/path/to/racket
python3 tools/validate-release-scope.py --check --require-no-open-gaps
```

The first command requires Racket and native execution, saves command logs, and
rejects partial/duplicate/failed suite output. It refuses an existing evidence
directory. `--source-only` is an explicit alternative that does **not** establish
Racket or native execution. The receipt separately records pure/native/GPU/
document execution, scope closure, and release readiness. The source auditor
never silently recaptures changed hashes. `--write` only regenerates a report
after the deliberately captured ledger validates.

Closing this stage's two policy decisions does not implement every deferred
feature, certify GPU/document execution, or approve a release. **0.78c** public
API/documentation stabilization and **0.78d** end-to-end release validation
remain outstanding.

## Pinned implementation references

- C wrappers: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_colorspace.cpp
- Row-major layout and non-aliasing inversion contract: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/modules/skcms/skcms.h
- Storage-less surface behavior: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/image/SkSurface_Null.cpp
