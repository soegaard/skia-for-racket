# Implementation plan: explicit `skia/racket-draw` interoperability

Status: proposal, not an implementation or a test-completion report.

Date: October 15, 2026.

Source baseline: `2dcd956dd9a41c76399c905971e2fa381a636bc2` and the working
checkout inspected on this date. Recheck these modules before implementation;
the bitmap, pict, and conversion bridges have recently changed. This plan does
not assign a release number or change the existing minimum supported versions.

## 1. Objective and recommended scope

Provide an opt-in module for explicit, eager conversions between ordinary
Racket Draw values and Skia values:

```racket
(require skia/racket-draw)
```

The first release should expose seven names: five new conversion procedures
and the two existing bitmap exports, re-exported unchanged. Conversions copy
data; they do not create live adapters, shared mutable views, or ownership
transfers. Path conversions remain vector geometry, subject to explicit
representability limits. Bitmap conversions are raster snapshots.

Keep the module out of `skia`/`main.rkt`. Do not automatically accept Draw
objects in existing core operations, attach new conversion properties, or
make existing Skia objects implicitly act like Draw objects.

Recommended decisions:

| Concern | First-release policy |
|---|---|
| Bitmap import | Copy current pixels into an owned CPU Skia image; no PNG round trip. |
| High-DPI bitmaps | Physical-resolution readback by default; explicit logical-resolution option. No backing-scale metadata is carried by the resulting image. |
| Masks | Apply the loaded mask by default; allow ignoring it or supplying a replacement. Bake its coverage into alpha. |
| Colors | Copy straight RGBA components, quantizing Draw alpha to a byte. No color-name or profile conversion. |
| Paths | Preserve representable contour geometry, order, closure, and fill interpretation. Never rasterize. |
| Unrepresentable path topology | Raise an error; do not close, connect, or reorder open contours. |
| Rational conics | Reject non-unit conics by default; provide explicitly requested, bounded approximation. |
| Fill style on export | Return it as a second value alongside the `dc-path%`. |
| Fonts | Deferred; family names and font objects are not reliable identity mappings. |

The two most important limitations belong in the introductory documentation,
not just in implementation notes: bitmap density metadata does not survive,
and not every Skia path can be represented by one `dc-path%`.

## 2. Existing code to build on

| Component | Reuse and constraints |
|---|---|
| [`bitmap.rkt`](../bitmap.rkt) | Already exports `image->bitmap` and `surface->bitmap`. Re-export these exact bindings. |
| [`private/bitmap-transfer.rkt`](../private/bitmap-transfer.rkt) | Shared premultiplied RGBA-to-ARGB transfer used by current bitmap/pict code. A natural home for a small inverse channel permutation. |
| [`private/dc-bitmap.rkt`](../private/dc-bitmap.rkt) | Already snapshots Draw bitmaps, computes backing geometry, handles masks, and checks allocation budgets. Its monochrome foreground/background behavior is drawing-specific, not neutral image conversion. |
| [`color.rkt`](../color.rkt) | Defines immutable byte-valued `rgba`; `color->rgba` does not currently accept `color%`. Preserve that contract. |
| [`private/dc-native-util.rkt`](../private/dc-native-util.rkt) and [`private/dc-styles.rkt`](../private/dc-styles.rkt) | Establish existing alpha rounding and path emission conventions. Their DC-specific records and resource scopes need not become public. |
| [`private/dc-geometry.rkt`](../private/dc-geometry.rkt) | Reads the public `dc-path%` datum and creates move/line/cubic/close commands. Reuse or minimally factor its checked geometry conversion. |
| [`private/path-matrix.rkt`](../private/path-matrix.rkt) | Supplies detached raw path segments, contour inspection, and bounded native iteration. Use the existing iterator rather than adding FFI. |
| [`geometry.rkt`](../geometry.rkt) | Already has `conic->quadratics` with bounded subdivision powers. Reuse it for the optional approximation policy. |
| [`private/core.rkt`](../private/core.rkt) | Supplies `rgba-bytes->image`, native path construction, pixel readback, resource checks, and ownership. |
| [`pict.rkt`](../pict.rkt) | A separate opt-in consumer; its explicit sRGB handling must not be confused with the unchanged legacy bitmap exports. |
| [`docs/API-CONTRACTS.md`](../docs/API-CONTRACTS.md) | Governs ownership, errors, module inventory, signature baselines, and compatibility review. |

The implementation should use documented Racket Draw methods and existing Skia
operations. No Cairo pointer access, private Draw representation mutation,
new native symbols, GPU context creation, or system font probing is needed.

## 3. Proposed public API

The following are proposed signatures, not currently available calls:

```racket
(bitmap->image bitmap
               #:resolution [resolution 'physical]
               #:mask [mask 'loaded])
  ; -> image?                         ; fresh owned CPU resource

(image->bitmap image)                 ; existing binding from skia/bitmap
  ; -> (is-a?/c bitmap%)

(surface->bitmap surface)             ; existing binding from skia/bitmap
  ; -> (is-a?/c bitmap%)

(color%->rgba color)
  ; -> rgba?

(rgba->color% color)
  ; -> (is-a?/c color%)                ; fresh mutable object

(dc-path->skia-path path
                    #:fill-style [fill-style 'odd-even])
  ; -> path?                          ; fresh owned Skia resource

(skia-path->dc-path path
                    #:conic-subdivisions [power #f])
  ; -> (values (is-a?/c dc-path%)
  ;            (or/c 'odd-even 'winding))
```

Contracts and naming:

- `bitmap` and a supplied mask must be `bitmap%` instances with successful
  `ok?` checks. Unsupported or invalid sources raise, rather than returning
  an empty image or `#f`.
- `resolution` is exactly `'physical` or `'logical`.
- `mask` is exactly `'loaded`, `#f`, or a valid `bitmap%` instance.
- `color%->rgba` accepts a `color%`; `rgba->color%` accepts an `rgba`, not the
  wider set of names, strings, and integers accepted by core `color->rgba`.
- `fill-style` uses Draw spelling: `'odd-even` or `'winding`. Translate
  `'odd-even` to Skia's `'even-odd` internally.
- `power` is `#f` or an exact integer from 0 through 5, matching the existing
  conic subdivision helper. Zero enables approximation; it is not strict mode.
- Do not re-export all of `racket/draw`, `skia`, or private helper structures.

### Why path export returns two values

Skia stores the fill rule on its path; Racket supplies a fill style at the
`draw-path` call. Returning geometry alone would quietly lose information.
The proposed two-value result deliberately makes the caller handle this:

```racket
(define-values (draw-path fill-style)
  (skia-path->dc-path skia-path))
(send dc draw-path draw-path 0 0 fill-style)
```

The import keyword defaults to Draw's normal `'odd-even` drawing convention,
not Skia's default `'winding`. A `dc-path%` itself cannot tell the importer
which style its caller intended. [Racket: dc<%>](https://docs.racket-lang.org/draw/dc___.html)

Treat the second result as part of the documented API and test it directly:
the repository's input-signature reflection does not infer result arity.

## 4. Bitmap conversions

### 4.1 Snapshot semantics and density

Read the bitmap's current public pixel data once per conversion. Do not use
its original encoded-file data: the bitmap may have changed since loading.
Do not cache by object identity, since the bitmap API supplies no mutation
revision suitable for validating that cache.

Let `Lw`, `Lh` be the reported logical dimensions and `b` the backing scale.
Validate dimensions, scale, finite products, and checked native limits before
allocating bridge pixel buffers.

| Mode | Output pixel dimensions | Public readback |
|---|---|---|
| `'physical` | `ceil(Lw*b)` by `ceil(Lh*b)` | `get-argb-pixels` with `#:unscaled? #t` |
| `'logical` | `Lw` by `Lh` | `get-argb-pixels` with `#:unscaled? #f` |

Logical mode intentionally delegates resampling to Racket Draw. It is not a
new selectable Skia sampling algorithm. Physical mode avoids this logical
downsampling, preserving the detail exposed by unscaled readback.

The public API reports logical dimensions and backing scale, not a universal
exact underlying-storage extent. For an imported image whose encoded size is
not divisible by its backing scale, logical dimensions are rounded up. Thus
physical mode means the public readback rectangle above, not a promise to
recover the original encoded dimensions; toolkit edge padding may be included.
Do not inspect Cairo handles or decode the old file to guess another extent.
[Racket: bitmap%](https://docs.racket-lang.org/draw/bitmap_.html)

This agrees with the geometry convention already used by `dc-bitmap-snapshot`.
Test odd-sized loaded bitmaps explicitly and document the actual public
readback behavior of supported runtimes; do not assume padded pixels are
transparent. Include the nominal rectangle and scale in failure diagnostics.

A Skia image retains only output pixel dimensions, not `b`, DPI, or `Lw`/`Lh`.
For a 20-by-10 Draw bitmap at backing scale 2, the default result is 40-by-20
pixels. Use `draw-image-rect` with the original logical dimensions when that
layout size matters. The existing `image->bitmap` creates a backing-scale-1
bitmap, so the default round trip is not a backing-metadata round trip.

### 4.2 Pixel representation and masks

Use a neutral pixel conversion, independent of a DC's pen, brush, text color,
background, alpha, clipping, transform, or bitmap drawing style.

1. Resolve the mask once. `'loaded` selects `get-loaded-mask`; `#f` ignores it;
   a supplied bitmap replaces the loaded mask. Never apply both masks.
2. Require a resolved mask to have the same logical dimensions as the source.
   Allow different positive backing scales under the explicit sampling rule
   below. Reject invalid masks before reading either pixel buffer.
3. Read source ARGB with `just-alpha? #f`, `pre-multiplied? #t`, and the chosen
   `#:unscaled?`. Opaque sources become alpha 255. A monochrome source becomes
   literal opaque black and white, not a foreground-colored stencil.
4. If present, read mask coverage through public `get-argb-pixels` with
   `just-alpha? #t`. Only the alpha slots of that buffer are meaningful. This
   uses the mask's own alpha where present and Draw's black-opaque,
   white-transparent mask interpretation otherwise.
5. Reorder source ARGB to RGBA. Multiply all four premultiplied components by
   mask coverage using `mul255(c, m) = quotient(c*m + 127, 255)`. Do not
   multiply only alpha, or unpremultiply and premultiply unnecessarily.
6. Create an independent CPU image with
   `rgba-bytes->image ... #:premultiplied? #t #:color-space #f`.

For logical mode, read source and mask at their common logical dimensions, so
their readback pixels align directly. For physical mode, read each at its own
physical dimensions and sample mask coverage at source-pixel centers:

```text
mask-x = min(mask-width - 1, floor((source-x + 0.5) * mask-scale / source-scale))
mask-y = min(mask-height - 1, floor((source-y + 0.5) * mask-scale / source-scale))
```

This nearest-center rule matches the existing DC bridge's scale alignment.
It is a defined mask policy, not a claim to reproduce every backend's filtered
`draw-bitmap` rasterization. Likewise, reading both inputs at logical size and
then multiplying coverage need not equal multiplying at high resolution and
then downsampling.

Mask interpretation and premultiplied pixel transfer are documented public
Draw operations. [Racket: bitmap-dc%](https://docs.racket-lang.org/draw/bitmap-dc_.html)

The automatic loaded-mask default is an intentional new convenience policy;
it does not change existing DC drawing behavior. Document `#:mask #f` next to
the first example. Ignore a mask bitmap's own loaded mask: coverage does not
recursively expand into a chain of masks.

Validate the resulting premultiplied invariant `R,G,B <= A`; malformed pixel
data must not enter native Skia. Fully transparent output has zero RGB.
When mask coverage is 255, numerical source premultiplied bytes are unchanged.

### 4.3 Color and fidelity boundaries

The new importer produces untagged RGBA8888 pixels, consistent with the
existing direct-byte bridge. It does not infer an ICC profile, assign an
unverified profile, transform channels, or promise wide-gamut fidelity.

Keep `image->bitmap` and `surface->bitmap` numerically and behaviorally
unchanged. In particular, do not quietly replace their implementation with
the newer pict bridge's sRGB conversion policy. A future color-managed bridge
would need explicit options and separate compatibility review.

Document that this conversion does not preserve source file format, encoded
metadata, palette/monochrome storage, loaded-mask object identity, hidden RGB
under zero alpha, color-space tags, HDR/float precision, or backing scale.
For an alpha bitmap at scale 1 with no mask, compare round trips in
premultiplied public pixels; arbitrary unpremultiplied byte round trips are
not a meaningful exactness guarantee.

### 4.4 Ownership, resource limits, and errors

The source bitmap and mask remain caller-owned and unmodified. Successful
conversion retains neither. Later mutations to either do not affect the
image. The returned image uses ordinary Skia ownership and can be managed with
`with-skia`; it does not borrow a Racket bitmap's native storage.

Read directly through the bitmap method, including when the source is already
selected into a `bitmap-dc%`. Never select or deselect it internally.
The caller must prevent concurrent mutation during conversion; an eager copy
does not make arbitrary Draw subclasses or simultaneous writers atomic.

Before allocating buffers, charge a conservative bridge budget of at least
`12*W*H + 4*Mw*Mh` bytes, omitting the mask term when absent. This accounts for
source ARGB, destination RGBA, one image-sized copy allowance, and mask ARGB.
Audit the final implementation for additional simultaneous copies and increase
the charge if necessary. Use existing checked dimension arithmetic and
`current-skia-byte-limit`; do not rely solely on the final image's byte count.

This is a bridge allocation admission policy, not a whole-process memory cap:
Draw readback and Skia can allocate internal storage. Avoid an unnecessary
immutable-byte copy unless its lifetime benefit justifies its cost.

Bad types/options/dimensions use checked argument errors. Invalid bitmap
state, unavailable native support, and readback/native failures raise with the
public procedure's context. Never publish partially initialized output or
substitute a blank bitmap after failure. Preserve the old outbound procedures'
existing errors and CPU/GPU restrictions.

## 5. Color conversions

### 5.1 `color%->rgba`

Read the public red, green, blue, and alpha components and construct a fresh
immutable Skia `rgba`. Preserve byte RGB exactly. Convert alpha using the
rounding convention already used by the DC adapter:

```racket
(inexact->exact (round (* 255 alpha)))
```

Require finite alpha in `[0,1]` and valid byte RGB. Racket's `round` uses
ties-to-even; do not silently switch to truncation. The alpha quantization
error is at most half a byte step relative to the input component, apart
from floating-point arithmetic at a tie. Do not premultiply RGB, perform
gamma conversion, or interpret a color's original name.

### 5.2 `rgba->color%`

Construct a fresh, mutable `color%` using byte RGB and alpha `A/255.0`.
Do not return a shared color-database object or cache. Mutation of the result
must not affect other conversions or the source `rgba`.

Draw uses byte RGB and a real alpha component; Skia's existing `rgba` uses
four bytes. That representational difference is the only intended lossy
step here. [Racket: color%](https://docs.racket-lang.org/draw/color_.html)

Both procedures must work without loading Skia or HarfBuzz. Keep core
`color->rgba`, named-color behavior, and extended `color4f` APIs unchanged.

## 6. Path conversions

### 6.1 Import: `dc-path->skia-path`

Use the documented `get-datum` method and the existing checked command
translation in `private/dc-geometry.rkt`:

1. Snapshot the closed-subpath list and final open-subpath list once.
2. Validate list/vector shapes and all coordinates; first points are two
   coordinates, subsequent elements are lines or six-coordinate cubics.
3. Emit each closed contour in order, followed by the open contour. Append a
   real close verb only to closed contours.
4. Map the explicit fill style and create a fresh Skia path.
5. Populate it with move/line/cubic/close operations and return it only after
   success. Close any partially constructed owned resource on failure.

Racket's path datum describes its existing geometry; ellipses and arcs have
already been expressed in that representation. Do not reconstruct their
original high-level construction calls or infer better-fitting circles.

No DC transform, pen width, brush, clipping region, or text state is copied.
Coordinates stay in the same axes and units; there is no implicit origin
shift, Y inversion, or half-pixel adjustment. Validate against Skia's finite
scalar range. Conversion to native binary32 can round Draw coordinates;
"preserves geometry" does not promise exact arbitrary-precision coordinates.

Do not simply return a path created inside `call-with-path` or `with-skia`:
the existing scoped helper disposes of its temporary result. The public
converter must transfer a successfully constructed owned path to its caller.

### 6.2 Export: preserve topology before translating curves

Read fill rule and detached segments using existing raw inspection:

```racket
(path-segments path #:mode 'raw #:force-closed? #f)
```

Raw mode is important: normal iteration can insert closing geometry or
normalize contours. Consume the start/end/control-point conventions of
`path-segment` correctly; non-move segments include their start point.

A `dc-path%` has closed subpaths and at most one final open subpath. Its
`move-to` closes a currently open subpath. Therefore replaying arbitrary
Skia moves would silently change stroke caps, closure edges, and possibly
filling. [Racket: dc-path%](https://docs.racket-lang.org/draw/dc-path_.html)

Preflight the complete snapshot before constructing a result:

- Accept any number of closed contours, optionally followed by one open
  contour. Accept an empty path.
- Reject an open contour followed by another contour, even if reordering
  would make it fit. Reject multiple open contours.
- Preserve contour order, direction, and explicit close verbs. Do not
  convert a close to a line or equate a final line-to-start with closure.
- Handle move-only and zero-length geometry deliberately; preserve what the
  public representations expose and reject unrepresentable cases. Do not
  delete degenerates just to avoid the topology check.
- Reject unsupported fill types rather than approximating inverse fills
  with an invented clipping rectangle. Current public Skia fill rules are
  winding/even-odd; do not add inverse-fill support as part of this project.

After preflight, build a new `dc-path%` using only public `move-to`, `line-to`,
`curve-to`, and `close`. Return it with the translated fill style. The result
is independent of subsequent mutation or closing of the Skia path.

Skia can canonicalize degenerate authoring operations before inspection. The
contract preserves the observed path, not the exact sequence of calls that
originally built it. A structural round trip is consequently not promised.

### 6.3 Curve mapping and strict default

| Skia verb | Draw representation |
|---|---|
| Move | `move-to`, subject to topology preflight |
| Line | `line-to` |
| Cubic | `curve-to` with copied controls and endpoint |
| Quadratic | Exact degree elevation to a cubic, apart from arithmetic roundoff |
| Conic with weight exactly 1 | Treat as a quadratic |
| Other positive finite conic weight | Error unless explicit approximation is requested |
| Close | `close` |
| Unknown/invalid verb or weight | Error |

For a quadratic with endpoints `P0`, `P2` and control `Q`, emit cubic controls:

```text
C1 = P0 + (2/3) * (Q  - P0)
C2 = P2 + (2/3) * (Q  - P2)
```

Check computed coordinates as well as source coordinates. Do not turn a
near-unit conic into a unit conic using an undocumented epsilon.

Common Skia circles, ellipses, and arcs can contain rational conics. The
strict default will therefore reject some ordinary paths, not just exotic
input. Make the opt-in alternative visible in the documentation.

### 6.4 Explicit conic approximation

When `#:conic-subdivisions` is an integer `p` from 0 through 5, use existing
`conic->quadratics ... #:subdivisions p` and elevate each resulting quadratic
to a cubic. The maximum expansion is `2^p` quadratic/cubic pieces per conic;
the helper may return fewer. Preserve piece order and shared endpoints.

```racket
(define-values (draw-path fill-style)
  (skia-path->dc-path ellipse-path #:conic-subdivisions 4))
```

This remains vector output, but it is an approximation. The keyword is a
subdivision power, not a world-space or device-pixel error tolerance. Do not
claim that any fixed power guarantees a geometric error bound for all
weights, coordinate ranges, and later transforms. An adaptive tolerance API
would be a separate design, not an alias for this option.

Approximation addresses curve representation only. It does not permit
topology changes, raster fallback, invalid weights, or unsupported fill rules.

### 6.5 Path budgets and lifetime guarantees

Apply `current-skia-byte-limit` to detached input commands, predicted output
commands, and conic expansion scratch space before expensive construction.
Use the existing segment-accounting convention as a basis, including command
overhead and point storage; do not treat a list of arbitrary length as free
merely because the native iterator's individual allocation is bounded.

For export, calculate the worst-case expanded command count from the single
snapshot. For import, validate/count the returned datum before creating a
native path. `get-datum` itself can allocate in Draw, so this remains bounded
bridge admission rather than a promise to cap all third-party allocations.

Inputs are borrowed for the call, not mutated or closed. Honor existing
closed-resource and owner-thread checks. Source mutation during conversion is
not supported. Empty results are valid; resource or representability failures
raise instead of returning a truncated path. Diagnostics should identify the
offending contour/segment and, for a conic, mention the explicit approximation
option without automatically retrying.

## 7. Module layout and implementation strategy

Keep `racket-draw.rkt` a small public facade with explicit `provide` forms and
clear checked wrappers. Import Draw names with a prefix or `only-in` so Skia
and Draw classes/operations cannot collide.

Suggested responsibilities:

| File | Intended change |
|---|---|
| `racket-draw.rkt` | Five new procedures, two exact re-exports, public argument/error context. |
| `private/bitmap-transfer.rkt` | Small tested inverse premultiplied channel-order helper, if it reduces duplication. Preserve existing exports/behavior. |
| `private/racket-draw-bitmap.rkt` | New neutral bitmap snapshot, mask sampling, and budget helpers, without native allocation at import time. |
| `private/racket-draw-path.rkt` | Checked topology analysis and segment/curve translation; keep pure preparation separable from native allocation. |
| `private/dc-geometry.rkt` | Reuse existing Draw datum conversion, or extract a small shared helper if necessary; preserve DC behavior. |
| `tests/racket-draw-pure-test.rkt` | Imports, signatures, colors, checked detached conversions, budgets, and failure cases. |
| `tests/racket-draw-native-test.rkt` | Owned images/paths, actual pixel transfer, curve fidelity, and resource tests. |
| `tests/racket-draw-consumer-test.rkt` | Ordinary Draw/Skia consumption and integration cases. May share fixtures with the native suite. |
| `scribblings/reference/racket-draw.scrbl` | Public reference with copy, density, mask, fill, and approximation contracts. |
| `examples/public/racket-draw.rkt` | Runnable examples using public APIs only. |

These private filenames are suggestions, not an invitation to build a generic
conversion framework. Keep the first implementation small enough to review.

Do not route neutral monochrome import through `dc-bitmap-snapshot` with an
arbitrary style/foreground merely to reuse code. Share low-level checks or
sampling formulas where useful; retain the distinct drawing and conversion
policies. No broad refactor of `skia-dc%` is required.

## 8. Implementation stages and gates

### Stage A — API boundary, colors, and bitmap ingress

1. Recheck the baseline, supported Racket/draw-lib versions, and existing
   uncommitted work. Confirm the exact old bitmap bindings before editing.
2. Add the opt-in facade, color copies, and direct premultiplied bitmap import.
3. Implement both resolution modes and the specified mask policy, including
   geometry and aggregate allocation checks.
4. Add import/contract tests and bitmap/color fixtures immediately.
5. Document bitmap density, loaded-mask defaults, literal monochrome behavior,
   and untagged output before presenting the feature as ready.

Gate: color conversion and module loading work with Skia/HarfBuzz unavailable;
native bitmap import passes exact premultiplied-byte fixtures. Existing
bitmap exports have unchanged identity, signatures, and behavior.

### Stage B — Strict vector path bridge

1. Implement the owned Draw-to-Skia path factory with explicit fill style.
2. Implement raw Skia snapshot preflight, exact line/cubic/quadratic mapping,
   and topology rejection.
3. Return a fresh Draw path and fill style together.
4. Test holes/fill rules, closure/strokes, coordinates, error paths, and
   independence from source mutation/closure.

Gate: representable paths stay vector geometry with documented numeric
precision; unrepresentable paths fail without semantic alteration.

### Stage C — Bounded explicit conic approximation

1. Wire the existing conic subdivision helper into the checked translator.
2. Preflight worst-case command expansion and aggregate scratch budgets.
3. Test weights, power limits, endpoint continuity, segment counts, and
   representative numerical errors; retain strict behavior by default.
4. Add an ellipse example contrasting strict failure with explicit conversion.

Gate: the opt-in approximation works with no claimed tolerance guarantee;
topology and fill restrictions remain enforced. Do not publish the keyword
before its behavior and tests are complete.

### Stage D — Consumers, documentation, and compatibility evidence

1. Register suites with `run-tests.rkt`; do not let new tests exist only as
   manually runnable files.
2. Add the reference chapter to the reference manual and update discoverability
   from bitmap/image, path, and DC documentation.
3. Add the module to the headless public API policy and review the observed
   export/signature diff. Only the seven planned exports should appear.
4. Recommend the stable call-boundary classification once these gates pass,
   consistent with `skia/bitmap`. The policy currently propagates experimental
   classification across shared exports: do not accidentally downgrade the
   existing bitmap bindings by classifying this facade differently.
5. Update generated API/reference inventories and relevant release-scope/source
   checksums through the established reviewed process. Do not fabricate a
   reflection snapshot or regenerate hashes simply to silence failures.
6. Run focused suites, existing affected consumer tests, aggregate pure/native
   checks, and public API validation on the supported platform matrix.

Gate: a clean package can require the module without a GUI, examples run with
public imports, consumers render correctly, and failures/skips are reported
separately. This feature alone does not establish overall release readiness.

Stages A–C can be reviewed independently, but the proposed complete first
release includes all three plus Stage D. If an earlier bitmap/color-only
release is wanted, publish only that documented subset rather than stubs for
unfinished path operations.

## 9. Detailed test and acceptance matrix

### Import boundary and compatibility

- Require `skia/racket-draw` in a fresh headless process with both Skia and
  HarfBuzz overrides pointing to nonexistent libraries. Import must not load
  either, create a GUI/eventspace, or initialize GPU/font machinery. Draw's
  own platform libraries are still legitimate dependencies.
- Require `skia/bitmap` and `skia/racket-draw` together without conflicting
  identifiers; verify the outbound exports are the original bindings.
- Confirm `skia` gains none of the five new conversions and acquires no new
  Draw dependency through this work.
- Verify positional arities/keyword sets with the public API machinery; test
  defaults and the two-value path result explicitly.

### Bitmap and color cases

- Exact asymmetric channel fixtures, alpha 0/1/127/128/254/255, opaque sources,
  premultiplied RGB near alpha, and zero-alpha canonicalization. Catch both
  swapped channels and accidental double premultiplication.
- Alpha-free color and literal black/white monochrome sources; no implicit
  foreground tinting or white transparency without a mask.
- Loaded mask, ignored mask, replacement mask, no loaded mask, color-alpha
  mask, grayscale mask, monochrome mask, and a mask with its own loaded mask.
  Test nontrivial source alpha multiplied by nontrivial mask coverage.
- Reject invalid sources/masks and mismatched logical dimensions. Cover
  differing mask backing scales and the center-sampling boundary pixels.
- Backing scales 1, 2, and fractional scales; odd logical dimensions; both
  resolution modes. Include an odd-sized encoded image loaded at scale 2 to
  exercise rounded logical extents rather than assuming physical dimensions.
- Compare byte transfer against the public Draw readback rectangle, including
  its observed edge behavior. Never compare against guessed private storage.
- Mutate source/mask after conversion and verify snapshot independence. Re-run
  conversion after mutation to detect stale caches. Test an already-selected
  bitmap and verify the existing DC selection/state is unchanged.
- Small byte limits at and below admission boundaries; dimension overflow;
  failure before native image creation; no leaked result after an exception.
- Scale-1 no-mask image/bitmap round trip using premultiplied bytes. Verify that
  density and mask metadata are not falsely advertised as round-tripped.
- All 256 `rgba` alpha values round-trip through `color%`; include half-step
  rounding checks, endpoint alpha, random RGB, and independent mutable results.
- Colors and detached transfer helpers run in the pure suite. Tests actually
  requiring an owned Skia image belong in the native suite.

### Path cases

- Empty, line, cubic, quadratic, closed polygon, several closed contours, and
  closed contours followed by one open contour. Include negative/fractional
  coordinates, repeated points, move-only contours, and zero-length segments.
- Multiple open contours and open-before-closed order must fail. Verify no
  hidden closing edge or reordered contour is produced.
- Test an open curve whose endpoint equals its start separately from an
  explicitly closed curve. Stroke cap/join behavior must not be conflated.
- Test nested contours with differing winding and odd-even results. Use the
  returned fill style in consumer rendering and assert it directly.
- Check quadratic degree elevation algebraically and at sampled parameters.
  Compare geometric bounds, not control-point bounds, which may differ after
  degree elevation even for the same curve.
- Unit and non-unit conics, invalid weights when representable by a fixture,
  powers 0 and 5, invalid powers, default failure, endpoint continuity, and
  bounded expansion. Sampled numerical checks do not prove a global tolerance.
- NaN/infinity/out-of-range coordinates, malformed datum supplied by a test
  subclass, computed-control overflow, resource closure, and wrong-owner use
  where the existing resource contract requires rejection.
- Mutate/close each source after successful conversion and verify the result
  remains usable. On failed native construction, verify cleanup using the
  repository's established lifetime instrumentation.
- Low input/output/expansion budgets must fail before publishing partial
  results. Unknown verb/fill handling can be tested in the pure translator;
  do not add unsafe FFI solely to manufacture otherwise inaccessible states.

### Real consumers and regression coverage

- Draw imported bitmap pixels on an ordinary Skia surface, convert back, and
  consume with `bitmap-dc%` and ordinary pict bitmap composition.
- Feed exported paths and the returned style to `bitmap-dc%`, `pdf-dc%`, and
  `skia-dc%`; feed a Draw-authored path through the importer and Skia drawing.
  Vector path export must not create a hidden bitmap on the PDF route.
- Check obvious holes, open ends, orientation, placement, and semitransparent
  pixels numerically. Use tolerances for backend antialiasing; do not require
  bit-identical cross-renderer edges.
- Re-run existing DC bitmap/mask/style, path/matrix, geometry/conic, pict, and
  document consumer suites when touching shared helpers. Keep their existing
  expectations intact instead of adjusting them to match a new policy.
- Exercise the minimum supported Racket version and a current version on
  Windows, macOS, and Linux through existing CI. Do not add a GUI requirement
  to the pure/headless test group.

Useful existing validation entry points, after registering the new suites:

```sh
racket run-tests.rkt --pure
racket run-tests.rkt
python3 tools/test-public-api.py
python3 tools/validate-public-api.py --source-only
python3 tools/validate-public-api.py --racket /absolute/path/to/supported/racket
```

Use the repository's configured native-library environment for native tests
and its established GUI host for the full API inventory check. Source-only
or headless-only validation is partial evidence, not a full acceptance pass.

## 10. Documentation examples to ship

The public example should contain four short, independently understandable
sections:

1. Create/read a Draw bitmap, import it inside `with-skia`, draw it at an
   explicit logical size, and export it back with the existing bitmap binding.
2. Show a loaded mask applied by default and ignored with `#:mask #f`; explain
   why literal monochrome copying differs from a DC stencil operation.
3. Copy a semitransparent Draw color to `rgba` and back without shared mutation.
4. Import a Draw path with an explicit fill style, export a representable path
   using `define-values`, and separately demonstrate opt-in conic approximation.

Examples must use `(prefix-in rd: racket/draw)` where names overlap with Skia,
manage owned Skia outputs explicitly, and avoid private helpers or test fixtures.
Place the topology restriction and two-value result alongside the path example.

## 11. Font interoperability: separate future design

Do not add `font%->font`, `font%->typeface`, or inverse procedures in this
release. A name/size copy would look convenient while dropping essential
meaning. The current DC text code already illustrates the difficulty:

- [`private/dc-text-spec.rkt`](../private/dc-text-spec.rkt) separates Draw font
  requests, screen-family resolution, fractional pixel size, and shaping data.
- [`private/dc-font-name.rkt`](../private/dc-font-name.rkt) handles constrained
  font-description parsing. Its internal records are not a ready-made public
  portable font identity.
- A Draw font can involve family lookup, platform mappings, features,
  fallback, and size units. A Skia typeface identifies a selected face; a
  Skia font adds metrics/rendering choices. These are different objects.
- Fallback depends on actual text and shaping, not merely a font object.
  Reverse conversion cannot generally reconstruct the original request.

A future proposal should distinguish copying a font request from resolving
that request to concrete resources. Require explicit size units, matching
policy, missing-face behavior, feature/variation handling, fallback scope,
and ownership. Return useful resolution/loss information rather than silently
substituting a family. Validate with the existing text consumer fixtures on
each platform; do not promise identical metrics from matching names.

Other deferred work: live bitmap views, GPU uploads, mutable surface imports,
zero-copy native sharing, pen/brush/region conversion, color-managed pixel
options, adaptive conic error tolerances, and multi-path export. A future
multi-path API must account for joint filling: drawing contours separately
can change holes and winding, so returning a list is not automatically an
equivalent drawing.

## 12. Implementation hand-off

Use the following as a starting prompt in a separate implementation chat:

> Implement the explicit `skia/racket-draw` bridge described in
> `plans/skia-racket-draw-interop.md`, after rechecking the current source and
> preserving unrelated work. Keep it opt-in: do not change `skia/main` exports
> or add implicit conversions. Add the five new procedures and re-export the
> two existing bitmap procedures as the same bindings. Implement eager copied
> bitmap ingress with the specified density, masks, alpha, color, and budget
> policies; detached color copies; and vector path conversions with explicit
> fill-style handling, strict topology checks, exact quadratic elevation, and
> only opt-in bounded conic approximation. Do not add fonts, GPU/zero-copy
> interop, private Cairo access, or new FFI. Register pure/native/consumer tests,
> add public examples and reference documentation, and update API inventories
> through the existing reviewed process. Run the relevant regressions and
> report commands, results, limitations, and unrun checks honestly. If the
> current implementation invalidates a substantive design assumption, explain
> the evidence before broadening the API or silently changing semantics.

Planning verification: the repository and public Draw documentation were
inspected. Small read-only probes with Racket 9.3.0.2 confirmed that a new
`move-to` closes the preceding open subpath, that fractional bitmap backing
scales retain separate logical dimensions, and that the proposed byte-alpha
mapping round-trips all 256 values. These probes are not implementation tests;
all acceptance work above remains to be done.
