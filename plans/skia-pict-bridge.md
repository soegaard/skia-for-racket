# Implementation plan: an explicit `skia/pict` bridge

Status: proposal; this document does not implement the bridge.

Date: October 15, 2026.

Source inspection baseline: `938a109c36865420d4a12904dfe1184f1cdc2f24` and the
working checkout on that date. Recheck the relevant modules before implementing;
the checkout contains other work in progress. No release number is assigned here.

## 1. Objective and first-release decision

Add an opt-in `skia/pict` module that converts Skia images, raster surfaces, and
recorded pictures into ordinary Racket picts. The returned values must work with
normal pict composition, transformations, opacity, recording, and rendering.

The first release performs an **eager raster conversion**. Construction copies
or renders pixels once and returns a pict containing an independent Racket
bitmap. Later drawing does not consult the Skia source or replay its commands.

This makes the ownership and output representation predictable:

- Closing or changing the source after successful conversion does not change
  the pict.
- The pict's logical size is fixed when constructed.
- Drawing into a PDF or SVG target embeds raster content for the converted
  element. Surrounding ordinary pict content can still remain vector content.
- Drawing back into `skia-dc%` uses its normal bitmap drawing path; it does not
  recover the original Skia picture.

The public module exports explicit constructors. It does not attach
`prop:pict-convertible` to existing Skia structures and does not change the
meaning of requiring `skia`.

Racket's `pict/convert` protocol accepts actual picts as well as structures
implementing its property, so returning a `pict?` is sufficient for composition
throughout the pict API. [Racket: Conversion to Picts](https://docs.racket-lang.org/pict/Conversion_to_Picts.html)

## 2. Existing implementation and implications

| Existing component | What to reuse or account for |
|---|---|
| [`bitmap.rkt`](../bitmap.rkt) | `image->bitmap` and `surface->bitmap` already copy premultiplied RGBA into a Racket bitmap by rearranging channels to ARGB. Use the same transfer technique; no PNG encode/decode round trip is needed. |
| [`private/core.rkt`](../private/core.rkt) | Owns image/surface/picture lifetimes, pixel readers, drawing, `picture->image`, and the recording helpers. Preserve its CPU/GPU restrictions. |
| [`pictures.rkt`](../pictures.rkt) | Exposes nominal picture dimensions separately from native cull bounds. A nonzero cull origin is not automatically translated to zero. |
| [`private/dc-bitmap.rkt`](../private/dc-bitmap.rkt) | Implements the existing Racket bitmap-to-Skia direction, including alpha and backing geometry. Reuse its established consumer expectations in tests. |
| [`docs/DC-CONSUMERS.md`](../docs/DC-CONSUMERS.md) and [`tests/dc-consumer-fixtures.rkt`](../tests/dc-consumer-fixtures.rkt) | Provide real pict/plot composition, state, clipping, alpha, and replay fixtures. Extend the acceptance workflow without replacing its existing cases. |
| [`dc-output.rkt`](../dc-output.rkt) | Supplies actual PDF/SVG consumers through `make-dc-output-page`; useful for verifying the declared raster representation. |
| [`info.rkt`](../info.rkt) | Already depends on `pict-lib` and `draw-lib`; the supported minimum remains Racket 8.18 / draw-lib 1.22. |
| [`docs/API-CONTRACTS.md`](../docs/API-CONTRACTS.md) and [`api/public-api-policy.json`](../api/public-api-policy.json) | New public modules and signatures need deliberate inventory and policy updates. |

The inspected checkout already has `file/convertible` properties on images,
surfaces, documents, and output pages. That allows conveniences such as
`pict:bitmap` using PNG conversion. The proposed module supplies additional
guarantees: explicit snapshot ownership, direct pixel transfer, picture
viewports, and controlled logical size and raster density. It need not depend
on the new `file/convertible` implementation.

`picture->image` is useful for understanding existing playback, but is not a
complete implementation of this plan: it scales nominal dimensions, does not
subtract a nonzero origin, and does not expose a target color-space option.

## 3. Proposed public API

```racket
(require skia/pict)

(image->pict image
             #:backing-scale [backing-scale 1])
  ; -> pict?

(surface->pict surface
               #:backing-scale [backing-scale 1])
  ; -> pict?

(picture->pict picture
               #:bounds [bounds #f]
               #:raster-scale [raster-scale 1])
  ; -> pict?
```

Use ordinary procedures with contracts consistent with the repository. Export
only these three names in the first release. Do not re-export `pict` or add
these functions to `main.rkt`.

Both scale keywords accept finite positive real values whose resulting logical
geometry and native transforms are representable. Reject zero, negative,
non-real, NaN, infinite, overflowing, and underflow-to-zero results. Check
derived physical sizes against existing Skia limits before allocating pixels.

`#:bounds` accepts `#f` or a four-element vector containing finite
`x`, `y`, `width`, and `height`, with strictly positive extents. Validate and
copy the supplied values immediately; mutation of the argument must not affect
the result. Check right/bottom and derived transforms as well as individual
components. A vector-only contract keeps this new option small and matches
the result of `picture-cull-bounds`.

Do not add width, height, DPI, background, smoothing, or representation-policy
keywords in this release. Pict combinators already provide layout resizing and
background composition; the options above address information that cannot be
recovered after conversion.

### 3.1 `image->pict`

Read the live CPU image into an independent bitmap immediately. For physical
image dimensions `Pw` by `Ph` and declared backing scale `b`:

```text
logical width  = Pw / b
logical height = Ph / b
stored pixels  = Pw × Ph
```

The default maps one image pixel to one pict unit. A 200×100 image with
`#:backing-scale 2` becomes a 100×50 pict without discarding pixels or creating
new ones. This keyword describes the density of existing samples; it is not
an upsampling request.

Do not infer density from the current display, a GUI canvas, PNG metadata, or
the eventual drawing context. Skia images do not currently carry the necessary
logical-size contract.

### 3.2 `surface->pict`

Take one CPU surface snapshot and convert it through the image path. Release
that temporary image on both success and failure. Retain no surface, canvas,
or native image in the returned pict.

Dimensions and `#:backing-scale` have the same meaning as for `image->pict`.
Further drawing to the source changes only future conversions. A canvas's
current transform and clip are drawing state, not instructions to crop or
transform the complete surface snapshot.

Existing exclusive-borrow and owner-thread restrictions continue to apply.
The constructor must not weaken them to obtain a snapshot.

### 3.3 `picture->pict`

Render the CPU-compatible recorded picture once into a transparent raster
surface. The viewport determines both the pict's logical dimensions and the
portion of picture coordinates retained.

When `#:bounds` is `#f`, use:

```text
(x, y, W, H) = (0, 0, picture-width, picture-height)
```

This follows existing nominal playback conventions. Do not automatically
substitute or union the cull rectangle: R-tree recordings can tighten it, and
cull bounds are not exact ink bounds.

An explicit viewport `(x, y, W, H)` translates that origin to the pict's top
left. The result has logical size `W` by `H`. For raster scale `s`:

```text
Pw = ceiling(W × s)
Ph = ceiling(H × s)

pixel-x = (picture-x - x) × Pw / W
pixel-y = (picture-y - y) × Ph / H
```

Use the actual independent X/Y ratios after rounding. Apply scaling and
translation in the order that realizes these equations, and clip to the
viewport. Do not stretch using nominal picture dimensions when an explicit
viewport was supplied. Drawing outside the selected viewport is excluded;
callers wanting stroke/filter bleed must enlarge the viewport themselves.

An explicit cull viewport is available through:

```racket
(picture->pict pic
               #:bounds (picture-cull-bounds pic)
               #:raster-scale 2)
```

This requests that rectangle, not a guarantee that it contains every visible
effect. Commands previously omitted through recording/culling cannot be
reconstructed by selecting a larger viewport.

Reject a zero-width or zero-height default viewport with an error explaining
that positive `#:bounds` can be supplied. Do not manufacture a 1×1 pict or
change the recording's dimensions silently. An empty recording with positive
dimensions legitimately produces a transparent pict.

`#:raster-scale` changes sampling resolution, not logical size. A 100×50
picture at scale 2 produces a 200×100 bitmap displayed as a 100×50 pict.
Magnifying the completed pict later does not rerender the recording.

### 3.4 Pict geometry and baseline

All three constructors return picts with ascent equal to logical height and
descent zero. They represent rectangular graphics without text-baseline
metadata. Callers can use ordinary pict baseline/bounding-box adjusters.

Keep fractional logical dimensions. In particular, a 101×51 image at backing
scale 2 must be 50.5×25.5 pict units, not 51×26. Do not let integer dimensions
reported by `bitmap%` become the public logical-size oracle.

Use exact arithmetic where available and avoid unnecessary inexact coercion
before validation. Tests should allow justified floating-point error for
inexact geometry rather than claiming exact binary equality for every input.

## 4. Snapshot ownership, failures, and repeatability

Construction is the only operation that accesses Skia input resources. The
caller must keep inputs live and use their owning thread for construction.
After success, drawing and composition use only the retained Racket bitmap and
pict data.

The bridge never closes a caller-owned input. It deterministically closes its
own snapshots, raster surfaces, and color-space wrappers using existing
resource scopes. Failed conversion returns no partial pict. Preserve cleanup
under exceptions, non-exception raises, breaks, and supported continuation
escapes; do not substitute a blank pict or swallow the original failure.

The returned bitmap is private implementation state and is never mutated by
the bridge after construction. Do not add a global cache or public bitmap
accessor. This is a stable snapshot guarantee, not a new claim that all Racket
pict internals are deeply immutable.

Repeated `draw-pict`, composition, and recording must not access the source,
allocate Skia resources on behalf of the bridge, or execute a user drawing
callback. Destination drawing libraries can still allocate their own resources.

The source's native thread affinity ends at the snapshot boundary. Subsequent
use follows the destination DC and Racket bitmap rules; do not promise
unrestricted concurrent use of an individual DC or bitmap.

Propagate closed-resource, wrong-thread, expired-borrow, missing-native-library,
and native rendering/read failures. Invalid arguments should identify the
bridge entry point where practical; do not change existing exception classes
or rely on exact error-message strings in tests.

## 5. Pixels, color, alpha, and resource limits

### 5.1 Display representation

Define the bridge as an explicit conversion to an 8-bit RGBA display snapshot.
It does not retain ICC metadata, extended-range samples, higher channel
precision, vector paths, font objects, searchable text, links, or annotations.

Use the following fixed color policy for the new constructors:

- For a tagged image, request sRGB pixels from the existing Skia pixel reader
  using an owned sRGB destination color space.
- For an untagged image, retain its numerical channel interpretation and
  document that the resulting display bitmap treats those channels as sRGB.
  Do not guess a source profile.
- For picture rasterization, create the transparent destination surface with
  an sRGB color space, so existing Skia drawing rules perform conversions for
  tagged content.
- Integer and float source formats use the existing supported RGBA8888 read
  path. Float conversion is explicitly a lossy display conversion; it is not
  HDR preservation or tone mapping. Users needing controlled tone mapping or
  quantization must prepare the source before calling the bridge.

Preserve native failures for unsupported conversions. If a tested source
format cannot supply the promised display representation, document and reject
that case rather than relabeling its channels.

This is a policy for the new module, not permission to change the existing
`skia/bitmap` functions' color semantics. The final appearance remains subject
to the destination toolkit/display; no cross-platform color-management or
pixel-identity guarantee is implied.

### 5.2 Alpha transfer

Read premultiplied RGBA bytes, permute channels to premultiplied ARGB, and call
the Racket bitmap pixel setter with its premultiplied flag enabled. Maintain
alpha-channel storage rather than inventing a separate mask. Never
premultiply a second time.

Use transparent raster backgrounds. Test opaque, partially transparent,
fully transparent, and antialiased-edge samples over contrasting backgrounds.
Hidden RGB behind zero alpha need not survive this display conversion.

### 5.3 Allocation checks

Validate pixel dimensions with the existing `1..32768` per-axis limits and
`current-skia-byte-limit` before native raster allocation or copied buffers.
Use exact checked arithmetic for `N = 4 × Pw × Ph` after validating finite
scaled extents.

The new bridge must also preflight its two simultaneous Racket byte buffers:
the RGBA readback and ARGB permutation require `2 × N` bytes. Charge that
scratch requirement against `current-skia-byte-limit`; add any further
explicit byte buffers to that calculation. Keep the old `skia/bitmap` limit
behavior unchanged if factoring out a helper.

The byte limit is not a total process-memory cap. Racket bitmap storage,
native source/decode storage, picture raster backing, Skia caches, and toolkit
allocations consume additional memory. Document this boundary and avoid
advertising zero-copy transfer. Prefer releasing temporary native raster
storage as early as its last use permits.

## 6. CPU/GPU and destination boundaries

CPU images, CPU surfaces, and pictures that can replay to a CPU surface are
the initial supported inputs. Preserve existing GPU affinity checks, including
GPU dependencies retained transitively by a picture. Importing this module
must not create a context or perform GPU readback.

Users can first call the existing explicit GPU-to-raster conversion APIs.
A GPU-dependent picture can be rendered to an explicitly managed GPU surface
and then downloaded before calling `image->pict`.

| Eventual destination | First-release behavior |
|---|---|
| `bitmap-dc%` | Ordinary bitmap drawing, with the destination's transform, clip, smoothing, and alpha. |
| CPU `skia-dc%` | Existing Racket bitmap ingress; no special access to the source recording. |
| `record-dc%` | Standard pict/bitmap commands record and replay; both procedure and datum routes require tests. |
| Racket `pdf-dc%` / `svg-dc%` | The converted element remains raster content in the document. |
| `skia/dc-output` | Existing bitmap command handling and output policy apply, including truthful raster representation/audit. |
| Other DC implementations | Ordinary pict/bitmap compatibility applies; untested backends are not certified by this feature. |

Do not override destination smoothing or alpha to make comparisons pass. Do
not introduce a direct-to-Skia replay optimization that changes representation
or quality depending on the receiving DC.

Keep representation distinct from native command replay in output reports.
An existing strict output policy may permit native placement of an explicit
bitmap while rejecting an implicit raster fallback. Follow that policy's
actual contract; do not require every image to be rejected, or describe a
successful native image placement as preservation of the source's vector
geometry. The embedded image is the evidence for this bridge's raster promise.

## 7. Module structure and implementation sequence

### Step 1: establish the API and geometry helpers

Add `pict.rkt` as the public `skia/pict` module, importing selected bindings
from `pict`, `racket/draw`, and existing Skia modules with explicit prefixes.
Keep it out of `main.rkt` and preserve import order independence.

Put scale, viewport, and allocation calculations in a small private helper,
such as `private/pict-util.rkt`, that does not load native libraries. Test its
arithmetic independently of rendering. Avoid a new generic conversion registry
or broad refactoring of `private/core.rkt`.

Exit condition: signatures and all geometry/error rules in sections 3 and 5
are executable pure tests; requiring `skia/pict` remains headless and does not
initialize native Skia or a GPU.

### Step 2: share only the pixel-transfer primitive

Factor the RGBA-to-Racket-bitmap channel-copy code from `bitmap.rkt` into a
small private helper, for example `private/bitmap-transfer.rkt`. Preserve the
old functions' public signatures, color policy, and ownership behavior.

The new pict module supplies its own checked, sRGB-oriented pixel readback
to that helper. This avoids duplicating alpha/channel conversion while making
the new display policy explicit. Do not import `skia/pict` from `bitmap.rkt`.

A bitmap at backing scale 1 can hold all physical pixels. Wrap it with
`pict:bitmap`, then apply `pict:scale` with the X/Y ratios needed to obtain the
specified logical dimensions. For fractional picture extents, use `W/Pw` and
`H/Ph`, not just `1/raster-scale`.

Check bitmap validity before constructing the pict. Parameterize
`pict:bitmap-draft-mode` to `#f` for this internal construction: these APIs
promise a snapshot, not a text placeholder selected by ambient draft mode.
Do not change the caller's parameter value.

Use public pict combinators instead of a custom drawing closure unless a
specific limitation is demonstrated. Racket's checked `dc` constructor can
invoke a drawing procedure during construction, so it is unsuitable for a
closure that would unexpectedly consume a source or run application code.
[Racket: Basic Pict Constructors](https://docs.racket-lang.org/pict/Basic_Pict_Constructors.html)

Exit condition: physical pixels are retained, fractional logical dimensions
and baseline metrics are correct, and the old bitmap bridge still passes.

### Step 3: implement image and surface constructors

Implement the image readback, owned color-space cleanup, and detached pict
construction. Then implement the surface constructor through a scoped snapshot
and the same image path. Perform argument and allocation validation before
expensive conversion.

Exit condition: construction succeeds for supported CPU sources, later source
mutation/closure has no effect, and all native resource failures remain visible.

### Step 4: implement picture rasterization

Resolve the viewport and physical dimensions; allocate an sRGB raster surface;
establish the exact viewport transform and clip; replay the picture once; copy
the resulting pixels through the same bitmap transfer; and close all temporary
resources. Use existing canvas-state and resource scopes.

Do not use `draw-picture`'s width/height scaling for the explicit-viewport
path: that scales nominal picture size, which is a different operation.
Unscaled `draw-picture` under the established transform is the intended route.

Exit condition: nonzero/negative origins, fractional bounds, nominal-versus-cull
differences, density changes, empty content, and CPU/GPU restrictions have
tests with actual output.

### Step 5: exercise real consumers and exported documents

Create a deterministic fixture containing colored quadrants, transparent
areas, translucent overlap, a diagonal edge, and a nonzero-origin recording.
Keep fonts out of pixel-exact fixtures; text can be a separate semantic test.

Run that fixture through actual pict composition and the destinations listed
in section 8. Reuse the existing DC consumer and document-inspection machinery
where possible. Do not replace old fixtures or weaken their tolerances.

Exit condition: both composition behavior and the promised raster representation
are verified, including after all original Skia resources have been closed.

### Step 6: document, inventory, and integrate

Add a reference chapter for `skia/pict`, one executable example, API policy and
inventory entries, and the appropriate changelog/API contract notes. Classify
the new module as headless and initially experimental, consistently with other
opt-in DC integration modules. This classification does not waive compatibility
checks.

Review the expected API delta: one new public module and exactly three new
constructor bindings there; no accidental exports or changes in existing
modules. Refresh approved generated inventories and source sums through the
repository's existing tools after implementation checks. Do not blindly
regenerate snapshots to conceal unexpected drift.

## 8. Acceptance tests

### 8.1 Pure geometry and import checks

- Check default scales, positive rational/inexact scales, finite derived
  transforms, and all rejected scale/bounds forms.
- Verify image dimensions `101/2` by `51/2` for a 101×51 input at density 2.
- Verify picture logical size is invariant under raster-scale changes; test
  `W=101/2`, `H=71/3`, and scales `1`, `3/2`, and `2`.
- Verify ceiling, per-axis limits, scratch-buffer limits, and oversized products
  without attempting enormous allocations.
- Check that `#:bounds` input mutation cannot change resolved geometry.
- In fresh subprocesses, require `skia`, `skia/pict`, `pict`, and `skia/bitmap`
  in both relevant orders. No GUI initialization, native Skia load, or GPU
  context creation should occur merely from importing the new module.
- Verify raw Skia types have not acquired `prop:pict-convertible`; account for
  their separate existing `file/convertible` support.

### 8.2 Native snapshots and pixel transfer

- Assert actual `pict?` and `pict-convertible?` results, logical width/height,
  ascent, and descent.
- Test opaque primaries, half-alpha samples, transparent pixels, and edges;
  detect swapped channels and double premultiplication.
- Compare against independently constructed Racket bitmap fixtures, not only
  against the helper shared by the implementation.
- Convert a surface; change and close it; render the old pict and verify that
  its original pixels remain. A second conversion before closure must reflect
  the change.
- Convert an image and picture, close their source wrappers, and render the
  pict repeatedly. Retain no Skia resources merely to make these tests pass.
- Verify source inputs remain open immediately after conversion.
- Test tagged sRGB and linear-sRGB midtone samples, untagged samples, and at
  least one supported float source. Include an independently specified color
  oracle; do not compare two calls to the same conversion helper as the sole
  color proof. Exercise an existing wide-gamut fixture where available.
- Test closed/wrong-thread inputs and exclusive surface-borrow failures.
- Use existing GPU affinity fixtures to prove rejection before readback;
  retain existing hardware-backed GPU gates without claiming new GPU support.
- Test native/read failure cleanup and the bridge's byte-limit boundary.

### 8.3 Picture viewport and resolution

- Use a picture recorded at `(100, 200, 40, 20)` with asymmetric marks. Show
  that explicit bounds select the intended content without translation errors.
- Test negative viewport origins, intentional cropping, transparent margins,
  content outside the viewport, and thick strokes/filter bleed near edges.
- Exercise R-tree recordings whose native cull bounds differ from nominal
  dimensions. Default logical size must continue to use the nominal extent.
- Test zero extents (rejection), positive-size empty pictures (transparent
  success), and invalid/overflowing viewports before raster allocation.
- Verify 1x and 2x physical samples with unchanged logical dimensions. Render
  the 2x pict into a 2x target and check resolved fine features; a 1x bitmap
  enlarged by interpolation must not satisfy the resolution test.
- Confirm the original Racket recording callback is not run by conversion or
  later pict drawing. The native recording, rather than that callback, replays.

### 8.4 Composition and destination behavior

Exercise `hc-append`/`vc-append`, superimposition, inset, baseline alignment,
uniform/nonuniform scaling, rotation, clipping, and both `cellophane` modes.
Use a second ordinary pict to ensure interoperability, not just a collection
of bridge-produced values.

`cellophane` defaults to applying opacity to the composed pict as a whole;
include overlapping elements that distinguish group opacity from fading each
element separately. [Racket: Pict Drawing Adjusters](https://docs.racket-lang.org/pict/Pict_Drawing_Adjusters.html)

| Test destination | Required evidence |
|---|---|
| `bitmap-dc%`, at 1x and 2x backing | Correct logical placement, alpha, pixels, transforms, clipping, and preservation of caller state. |
| CPU `skia-dc%`, at 1x and 2x backing | Same semantic checks plus the complete Skia → pict → Skia round trip. |
| `record-dc%` procedure and datum replay | Nonblank output with the expected bounds/alpha after source closure; agreement within the existing justified replay tolerance. |
| Racket PDF and SVG DCs | Valid document assets containing raster content for the converted element and independently recognizable content. |
| `make-dc-output-page` into Skia PDF/SVG | Visible converted element, image representation, correct placement, and no false vector-only claim or bypass of existing strict output policies. |

Snapshot destination state before and after drawing: transformation, clip,
alpha, smoothing, pen, brush, font, and relevant colors/text settings. Use
the repository's existing consumer-state helpers where suitable. Include
nonidentity initial transforms and a nontrivial clip, not only default DCs.

For documents, inspect embedded image dimensions and placement as well as
rendered appearance. Search for a PDF image object or SVG image element with
an established parser; a PDF/SVG header alone does not establish raster
representation or visible content. Include a neighboring vector rectangle to
show that only the converted element is necessarily rasterized.

Use exact assertions for geometry and analytical solid interiors when the
operation supports them. Use existing small channel tolerances for alpha
rounding and semantic/region checks for rotated or antialiased edges. Do not
require whole-image equality across Cairo and Skia, or universal byte equality
for generated documents.

### 8.5 Consumer protocols and rendering environment

Check ordinary `file/convertible` requests on the *returned pict*, and include
small Scribble HTML and LaTeX-renderer fixtures. The pict should use normal
upstream export behavior; no additional conversion property is needed on a
Skia object. Its PDF/SVG export remains an image-containing document.

Scribble assets can be tested without invoking TeX. If final PDF compilation
or external document rendering is not run, report that separately from asset
generation. Alt text/captions belong to the consuming document; they are not
invented from picture names or pixel contents.

No GUI window is required for the CPU bridge tests. Keep minimum-version and
current-version runs, and exercise the installed package outside the source
checkout so a relative-path import cannot hide a packaging error.

## 9. Proposed files and integration points

| File or area | Planned change |
|---|---|
| `pict.rkt` | New public opt-in module with three constructors. |
| `private/pict-util.rkt` | Pure scale, viewport, and allocation validation. |
| `private/bitmap-transfer.rkt` | Shared internal premultiplied channel-transfer helper, if extraction is the smallest implementation. |
| `bitmap.rkt` | Internal helper reuse only; retain public behavior and exports. |
| `tests/pict-pure-test.rkt` | Pure geometry/contracts and import behavior. |
| `tests/pict-native-test.rkt` | Source lifetime, transfer, color, picture viewport, and resolution. |
| `tests/pict-consumer-fixtures.rkt` and `tests/pict-consumer-native-test.rkt` | Real pict composition, DC state, replay, and output corpus. |
| `run-tests.rkt` | Register pure and focused native bridge tests following existing conventions. |
| Existing DC consumer doctor/validator | Add the new consumer corpus and evidence to the installed-package gate without duplicating every case in the aggregate runner. |
| Existing document inspectors | Extend selected fixtures to verify embedded raster content and placement. |
| `examples/pict-bridge.rkt` | Explicit conversion, source closure, composition, and 1x/2x picture example. |
| `scribblings/reference/pict.scrbl` | New reference chapter with contracts and raster/ownership guarantees. |
| Reference include/coverage files | Register the chapter and real binding targets. |
| API policy, public inventories, API contracts, changelog | Declare the small additive module and its behavior. |

These file names are the intended organization, not a requirement to create
one more validation framework. Reuse existing fixture/report infrastructure
when it provides the required coverage clearly.

## 10. Documentation examples to deliver

Show the normal snapshot lifetime explicitly:

```racket
#lang racket/base
(require skia skia/pict
         (prefix-in p: pict))

(define icon
  (with-skia ([surface (make-surface 48 48)]
              [paint (make-paint #:color 'steelblue)])
    (draw-circle (surface-canvas surface) 24 24 18 paint)
    (surface->pict surface)))

;; The surface and paint are closed. icon is still usable.
(define composed
  (p:hc-append 12 icon
               (p:cellophane (p:rotate icon 0.2) 0.5)))
```

The implementation must run the example and verify its output; it is
illustrative API usage at this planning stage.

Also show a 100×50 recording converted at raster scale 2, with assertions that
its pict dimensions remain 100×50, and a nonzero-origin recording converted
using explicit bounds. Explain that enlarging an existing raster pict does not
replay its source at a new resolution.

Put the sentence “All three constructors return raster snapshots” near the
start of the reference chapter and each constructor's documentation. Explain
how to obtain native vector PDF/SVG through existing Skia exporters when that
is the actual output requirement.

## 11. Validation and completion criteria

Use the repository's supported Racket installation explicitly. The current
shell's first `racket` can be older than the project's declared minimum.

Run checks in this order:

1. Pure helper, import, and API contract tests.
2. Focused native bridge and existing bitmap regressions.
3. Real pict composition/replay and the existing DC consumer gate.
4. Selected PDF/SVG representation and independently rendered output checks.
5. Aggregate pure/native regression checks appropriate to touched modules.
6. Public API inventory/signature review and reference rendering/link checks.

Use existing tools such as `run-tests.rkt`, `tools/validate-dc.py`,
`tools/validate-public-api.py`, `tools/check-reference.py`, and
consumer tests must actually be reached by the installed-package gate; adding
test files or updating a case count is not execution evidence.

The milestone is complete when:

- The three constructors return ordinary picts with the specified geometry.
- Snapshots remain correct after all source resources are closed.
- No source callbacks or Skia reads occur on subsequent pict draws.
- Bounds, density, alpha, color conversion, and allocation limits have direct
  tests rather than only visual examples.
- Bitmap, Skia DC, recorded replay, and document consumers pass their selected
  semantic checks, with raster representation correctly identified.
- Existing Skia objects remain unchanged with respect to pict convertibility.
- Core imports, existing bitmap semantics, and old consumer cases remain valid.
- New public API, documentation, package contents, and generated inventories
  agree, and any unrun environment-dependent checks are explicitly reported.

## 12. Follow-up milestone: `skia-pict`

Once the three constructors are accepted, add a separately scoped convenience:

```racket
(skia-pict width height draw
           #:raster-scale [raster-scale 1])
  ; draw : canvas? -> any
  ; result : pict?
```

Prefer the same eager model: validate everything, allocate a transparent sRGB
CPU target, establish logical coordinates, call `draw` exactly once, copy its
pixels, and release the target before returning. Accept and discard arbitrary
callback result values. Reject callbacks with incompatible arity or required
keywords before allocation.

The canvas is borrowed for that construction call and expires afterward.
Subsequent composition/drawing never invokes `draw`. Propagate exceptions and
escapes with complete temporary-resource cleanup; no partial result escapes.

Use the same density/rounding rules as `picture->pict`. This future constructor
does not need to record an intermediate Skia picture solely to rasterize it.
Add callback-count, escaped-canvas, failure-cleanup, and post-construction
resource-closure tests. Do not implement a lazy callback mode under the same
name or make its callback execution depend on the destination DC.

An `output-page->pict` convenience can be assessed alongside this milestone,
but must explicitly resolve page units and raster DPI. It is not required to
complete the first release.

## 13. Later vector work requires a separate design

An arbitrary Skia recording does not expose a ready-made portable sequence of
Racket `dc<%>` commands. Replaying it directly into a known Skia canvas does
not establish that it can render equivalently into another implementation's
DC, and a recording can contain raster content and backend-specific effects.

Evaluate a future vector-capable bridge only with:

- An explicit representation policy that states when raster fallback is
  allowed and provides an error when a stricter promise cannot be met.
- A defined receiver/capability contract covering bitmap, PDF/SVG, recording,
  transforms, clipping, opacity groups, and resource lifetime.
- Evidence that original paths/text or other claimed vector content survive
  in actual exported documents; a vector file extension is insufficient.
- A retention or copying model that is safe after user resource scopes end.
- A clear account of how an embedded value behaves inside an arbitrary pict
  composition, including intermediate compositing surfaces.

Do not quietly optimize `picture->pict` into native replay for selected DCs:
that would change the fixed snapshot guarantee and make output depend on the
consumer. If automatic pict conversion is considered later, a dedicated
explicitly constructed wrapper is a better starting point than changing all
existing Skia image/picture structures globally.

## 14. Planning evidence and limits

This plan is based on source inspection of the modules linked above and
official Racket documentation. A small Racket 9.3.0.2 probe confirmed that
`pict:scale` over a 101×51 bitmap pict can retain logical dimensions `101/2`
and `51/2`, ascent `51/2`, descent `0`, and `pict-convertible?` acceptance
without initializing `racket/gui/base`.

That probe is evidence for the suggested public-pict construction technique,
not a native Skia test, minimum-version result, or acceptance of this proposed
bridge. No bridge implementation or rendering acceptance run accompanies this
planning document.

Racket bitmap backing scale and pixel access have distinct logical/physical
semantics; that is why this plan retains physical pixels separately from the
reported pict dimensions. [Racket: bitmap%](https://docs.racket-lang.org/draw/bitmap_.html)

Rendering should continue through ordinary pict APIs, including `draw-pict`
and `pict->bitmap`, once the value is constructed.
[Racket: Rendering](https://docs.racket-lang.org/pict/Rendering.html)
