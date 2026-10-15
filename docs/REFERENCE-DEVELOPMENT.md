# Skia Reference development: R4d

## Presentation, GUI, and GPU output integration

Baseline: `efa1ae5e5b7f479ee2cd674fc7f620dfdb0af1fc`
(`Clarify Reference GPU handoffs`). R4d adds 36 bindings through 36 public
export paths and five chapters. The Reference has 1232 definitions, 1955
documented export paths, and 66 conceptual chapters. The checker accounts for
1978 export records including the retained source-verified one-shot renderer;
23 records remain for R4e DC integration.

The chapters separate presenter/frame lifetime, raw GPU GUI widgets, persistent
raster and frame-scoped GPU drawing canvases, unified render canvases, and
explicit GPU raster execution for bounded PDF/SVG fallbacks. GPU-output
executors always hand a CPU-owned image to the document layer after explicit
synchronous readback; they do not create a zero-copy document path.

Class and interface exports use Scribble's native `defclass` and `definterface`
forms. The source and runtime readers recognize those forms directly. Four
GUI-initializing modules remain explicitly listed in `runtime_deferred_modules`;
the ordinary headless binding worker parses their declarations but does not
`dynamic-require` them. The `skia/gpu-output` procedures remain eligible for
ordinary headless live binding validation. Fresh rendered xrefs still cover
every binding target.

`tools/reference-gpu-presentation-pure-test.rkt` exercises native-free presenter
policy without creating GUI windows or GPU contexts. The repository's existing
GPU presentation, raster-canvas, GPU-DC, render-canvas, and GPU-output validators
remain the platform/runtime evidence. This documentation batch does not turn a
source or policy test into evidence of visible screen pixels, performance, or
physical hardware acceleration.

R4d changes no library/API behavior. Renderer selection and the GPU-output
`#:on-unavailable` option remain explicit policies; neither is a general runtime
fallback that replays application callbacks after rendering has begun. R4e is
now exactly `skia/dc`, `skia/dc-output`, and `skia/gpu-dc`.

## Earlier R4c.1 development notes


## Editorial clarification after R4c

Baseline: `f05e7c9ca99da21d4e63a8f092c2ebe3bcc3da0a`
(`Expand Reference GPU interop coverage`). This revision changes no API coverage.
External-texture tokens now state their active-context and explicit-retirement
rules locally, including that they are not `skia-resource?` values and are not
managed by `with-skia` or `skia-close!`. The unsafe native-handoff chapter now
states the supported host platform beside each backend section.

The coverage manifest remains at R4c: 1196 bindings, 1919 documented export
paths, and 61 chapters. R4d-R4e remain deferred.

## External GPU interoperation

Baseline: `57f4b0e2a732a9a9c0ec27f05affe074fbf41518`
(`Expand Reference GPU surface coverage`). R4c adds 18 bindings through 20
public export paths and five chapters. The Reference has 1196 definitions,
1919 documented export paths, and 61 conceptual chapters. The checker accounts
for 1978 export records including the retained source-verified one-shot renderer;
59 records remain for R4d-R4e presentation/GUI and DC integration.

The chapters separate OpenGL host creation, diagnostics, explicit GL handoffs,
safe single-use external-resource tokens, and unsafe Metal/D3D12 native-pointer
construction. Safe token operations never expose a raw pointer. The unsafe
modules state that pointer validity is a caller precondition and that malformed
or freed native objects can crash the process.

The R4b editorial corrections are included: all four GPU displayed helpers now
show `(require skia skia/gpu)`, and the GPU-image introduction distinguishes
ordinary canvas image drawing from CPU-only image operations. The pure R4b
suite compiles each displayed helper in a fresh base namespace using only the
imports shown inside that block, so surrounding test-module imports cannot hide
an omitted dependency.

`tools/reference-gpu-interop-pure-test.rkt` contains native-free policy and
single-use-token cases. It uses explicit fake token backends and pure platform
validators; it is not native interop acceptance. Real external-resource
acceptance remains platform-specific: the repository's existing OpenGL/EGL,
Direct3D, and Metal validators exercise native objects, synchronization, pixels,
and cleanup on their supported hosts. This documentation batch does not invent
a cross-platform mock result or treat source validation as GPU execution.

Reference-only editing previews remain distinct from integrated publication
validation, as described below.

## GPU surfaces, images, transfers, and synchronization

Baseline: `6b474cc2cca76377fa220cb054eb5b8d7d6e5ced`
(`Expand Reference GPU context coverage`). R4b adds 36 definitions through 37
public export paths. The Reference has 1178 definitions, 1899 documented paths,
and 56 conceptual chapters. No library implementation or tutorial program changes.

The two R4a editorial corrections are local: provider host-identity enforcement
is attributed to the wrapper, and the Metal context-information example is
qualified by macOS and successful backend creation. Existing examples are retained.

The four new chapters separate offscreen surfaces, GPU image ownership, explicit
readback and one-shot rendering, and synchronization/cache controls. Native canvas
operations remain the drawing interface; no DC adapter is introduced. The typed
pixmap writer stages and validates pixels before committing them, whereas the
legacy RGBA8888 premultiplied buffer writer does not promise rollback. GPU image
readback uses a same-context GPU staging surface, not a raw texture-memory copy.

All 98 earlier displayed blocks and 25 evaluated blocks are preserved. Four new
blocks define helpers without invoking them, so ordinary documentation evaluation
and the retained CPU displayed-example runner do not create GPU contexts. The
new total is 102 displayed blocks and 25 evaluated blocks. The selected-backend
suite loads the actual three generic helper definitions from their Scribble files.

## Inventory evidence: old reflection and one source-verified addition

The two existing public-API JSON inventories remain byte-for-byte unchanged.
They contain 1977 reflected export records and precede `render-gpu->raster-image`.
The manifest records this later public export separately in
`source_verified_additions`, with evidence kind `source-signature`.

The complete `gpu.rkt` source at the baseline is stored, base64-wrapped to keep
source lines short, in `api/reference-source/gpu.rkt.b64`. Its decoded Git blob
hash is `d12815c3e504a1d056a66e08e85d550446884a3a`. The source checker verifies
that hash, the public module, the direct export, and the single procedure's
positional/keyword shape. In a complete checkout it also requires the source
copy to match the actual `gpu.rkt` bytes. This is pinned source evidence, not
runtime reflection, a second installed implementation, or native execution.

The full source report distinguishes 1977 reflected records from one source
addition. Thus 1978 records are accounted for, of which 1899 are documented
and 79 remain deferred. Fresh reflection and live binding-identity checks remain
runtime acceptance requirements. If a reviewed future inventory includes the
addition, remove the separate addition record; duplicate evidence is rejected.

Source-review archives include this evidence copy, all included chapters, pinned
inventories, and the ordinary checker dependencies. Their extracted source check
requires neither an older archive nor an adjacent checkout.

## R4b acceptance levels

The 18 cases in `tools/reference-gpu-surface-pure-test.rkt` use actual validation
helpers and the actual one-shot lifetime worker with injected fake operations.
They check request bounds and cleanup after failure without a native GPU. They
are not driver, graphics, or platform acceptance evidence.

The opt-in `tools/reference-gpu-surface-test.rkt` suite uses a real selected
backend, checks exact opaque pixel probes, ownership, snapshot and subset
contents, typed readback, padding, balanced state, cache controls, and cleanup.
It has 18 common cases and one extra public one-shot case on owned Metal or
Direct3D. The owned-EGL route does not provide the separately owned external
host required by the public one-shot OpenGL helper; that check is reported as
`not-run-external-host-required`, not as a passed case or an unavailable-backend
skip. The common OpenGL surface tests still require real OpenGL execution.

There are no unavailable-backend skips and no CPU rendering fallback. The
receipt must have the exact case inventory, successful pixel probes and readbacks,
and complete closure accounting for contexts created by the suite. Public
one-shot contexts have separate success accounting because their wrappers do
not escape the helper. Float-format capability queries do not claim actual
F16/F32 rendering acceptance. No GUI, presentation, performance, or physical
hardware-acceleration claim is made by this suite.

With `skia` resolving to the complete revised checkout, use fresh output paths:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" -l raco -- test tools/reference-gpu-surface-pure-test.rkt
python3 -B tools/check-reference.py --racket "$RACKET" \
  --gpu-surface-backend metal --output ../reference-r4b-metal-check
```

For Linux, select `--gpu-surface-backend opengl` (owned EGL). For Windows WARP,
select `--gpu-surface-backend direct3d --gpu-surface-adapter warp`. GPU flags are
not implied by `--native`, which retains its CPU meaning. Requested GPU failure
prevents a passing acceptance result and review-archive publication.

## Source handoff and rendering

Generate the independently checkable source archive through the existing packager:

```sh
python3 -B tools/check-reference.py --output ../reference-r4b-source-check \
  --source-zip ../skia-reference-r4b-source-review.zip
```

The existing Reference-only preview route remains appropriate during editing.
Integrated rendering and publication retain their companion-manual and binding
checks. For combined CPU and selected-backend GPU acceptance plus a review ZIP:

```sh
python3 -B tools/check-reference.py --racket "$RACKET" --render --quick --native \
  --gpu-context-backend metal --gpu-surface-backend metal \
  --output ../reference-r4b-review-check \
  --review-zip ../skia-reference-r4b-review.zip
```

R4c-R4e retain external interoperability, the remaining GL diagnostics and GPU
output adapters, presenters/frames, GUI classes, and DC integration. R4b does
not claim a newly reflected complete API inventory or completion of those stages.

## Earlier development notes

# Skia Reference development: R4a

## GPU contexts, providers, and options

Baseline: `a24848222a29aff2981590f32c63c2f2d54e4a93`
(`Refine Reference raster evidence`). R4a adds 31 bindings through 40 public
export paths. The Reference has 1142 definitions, 1862 documented export paths,
and 52 conceptual chapters. The pinned inventories contain 1977 export records;
115 remain deferred to R4b-R4e. The nine context-option bindings are documented
through both `skia/gpu` and `skia/gpu-context-options`, not through `skia`.

The three new chapters separate backend/provider declarations, immutable
construction requests, and context execution/lifetime. They distinguish stored
identity from owner-thread reports, shutdown requests from closure, and lost-host
abandonment from healthy-host release-and-abandon. A failed native teardown is
not turned into successful cleanup. No library/API implementation changes.

All 97 earlier displayed blocks and 23 evaluated blocks are retained. One new
displayed block defines a scoped context helper without calling it. Two new
checked evaluators use native-free backend declarations and context-option
values. Thus the ordinary displayed-example runner still requires no GPU.
The totals are 98 displayed blocks and 25 evaluated blocks.

## R4a acceptance levels

The 22 cases in `tools/reference-gpu-context-pure-test.rkt` run with the existing
Racket acceptance checks. They use the actual public wrappers and private state
machine with explicitly fake driver operations. They never establish native GPU
availability, graphics correctness, or teardown behavior of a real driver.

The 10 cases in `tools/reference-gpu-context-test.rkt` require an explicitly
selected real backend. They create contexts and small child surfaces, but do not
validate pixel rendering, presentation, performance, or physical acceleration.
There is no unavailable-backend skip and no CPU fallback. The script writes a
JSON receipt with created/closed context counts. The runner validates its backend,
adapter, successful case count, and closure accounting before marking acceptance
passed. A requested GPU test failure prevents review-archive publication.

With `skia` resolving to the revised complete checkout, use fresh output paths:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" -l raco -- test tools/reference-gpu-context-pure-test.rkt
python3 -B tools/check-reference.py --racket "$RACKET" \
  --gpu-context-backend metal --output ../reference-r4a-metal-check
```

On Linux, select `--gpu-context-backend opengl`; this test route uses an actual
owned EGL host. On Windows, select `--gpu-context-backend direct3d`, optionally
with `--gpu-context-adapter warp` for explicit software execution. No result on
one backend certifies another. Omitting `--gpu-context-backend` creates no GPU
contexts in the Reference acceptance runner; `--native` still selects CPU tests.

Reference-only editing previews remain supported by the existing direct renderer
command below. Integrated rendering is a separate publication check. Add
`--render --quick --review-zip ../skia-reference-r4a-review.zip` to an acceptance
command to request matching HTML and sources. Request `--native` separately for
the retained CPU native examples and suites, which retain their font requirements.

## Independent R4a source review

```sh
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r4a-source-check \
  --source-zip ../skia-reference-r4a-source-review.zip
```

The generated archive includes every included chapter, the actual pinned API
inventories, and checker/test dependencies. It validates both staged and extracted
sources. It is a validation package, not a complete Skia installation or evidence
that Racket/Scribble/GPU execution occurred.

The inventories remain pinned, not freshly reflected. In particular, the current
`gpu.rkt` also exports the later `render-gpu->raster-image` convenience operation,
which is absent from those snapshots. R4b should document that operation and
reconcile the inventory separately. R4a neither invents its reflection data nor
claims that the pinned remaining count enumerates every newer live export.

## Earlier R3g-b.1 notes

# Skia Reference development: R3g-b.1

## Local editorial corrections

Baseline: `6e7584be8d46122168065f2af7e82431bc0a16c3`. The three pixel-format
inventory constants now specify `(and/c (vectorof symbol?) immutable?)`.
The font-cache count queries and setter describe entry counts and the previous
count limit, not byte quantities. Their signatures and behavior are unchanged.
Byte-valued cache operations retain their byte-specific descriptions.

The no-op cache-limit example is removed rather than replaced by a more invasive
process-global mutation. The Reference now has 97 displayed examples and
23 evaluated blocks. All other examples and all procedure signatures remain.
The coverage manifest stays at R3g-b: 1111 bindings, 1822 export paths, and
49 chapters. Its implementation baseline is unchanged; this is not an API revision.

Ten Python regressions check the refined contracts, separate count and byte
units, removal of the example, the constant readers, and the pure test wiring. The raster pure suite
now contains fourteen cases, including a contract test using the actual public
format inventories and rejecting mutable or nonsymbol vectors. The 28 native
raster cases are unchanged. Supplied Racket tests still require actual execution.

The Python and Racket constant readers now recognize the exact documented
immutable-symbol-vector contract. Other compound constant contracts still fail
until both readers and live validation support them. The runtime check verifies
immutability and every element instead of treating the expression as a predicate
name. Standard list, string, and vector predicates use racket/base bindings;
the public Skia module need not re-export those predicates. The shared runtime
helper is independently importable by the native-free suite without running the
worker's command-line entry point. No contract expression is evaluated by Python.

Produce the next editor handoff with fresh output paths outside the checkout:

```sh
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py \
  --output ../reference-r3gb1-source-check \
  --source-zip ../skia-reference-r3gb1-source-review.zip
```

This archive includes all chapter sources, pinned inventories, and checker
scripts. Its ordinary source checker runs in staging and after extraction.
It is not a complete installation for native execution or a rendered manual.
Reference-only previews remain suitable for editing. Neither tutorial links
nor the existing integrated publication checks are changed by this revision.
Regenerate the repository-wide `SOURCE-SHA256SUMS.txt` only in the full checkout.

## Earlier R3g-b implementation

## Raster, output policy, and diagnostics

The upstream baseline is `027022cffb19dd314f6a01445e6d3e35c8b1889e`
(`Expand Reference geometry coverage`). R3g-b adds 166 bindings and 342 public
export paths. The totals are 1111 bindings, 1822 documented export paths, and
49 conceptual chapters. The remaining 155 inventory records are GPU, GUI, and
DC integration work for R4. Every export of the principal `skia` module is now
mapped; that is inventory coverage, not runtime or platform certification.

The ten completed module families are `raster-buffers`, `image-operations`,
`image-info`, `bitmap`, `surface-properties`, `output-policy`, `output-audit`,
`output-groups`, `graphics`, and `native-capabilities`. The bitmap adapter is
limited to copying an image or surface into a Racket bitmap. DC and GUI APIs
are not folded into this batch. Existing authoritative definitions stay in
place rather than being duplicated in the new chapters.

Seven chapters document raster storage and borrowed pixmaps, CPU image
operations, surface properties, output auditing, bounded output groups, global
caches and memory statistics, and native preflight. Existing Pixel Descriptions
and Shaders gain the format inventories and raw image shader respectively.
The complete Reference has 98 displayed examples and 23 evaluated blocks:
all 90 earlier displayed blocks and twenty evaluated blocks are preserved.
The three new evaluated examples use pure public values, not native allocations.

## R3g-a editorial dispositions

The accepted eight geometry chapters remain unchanged, except for the requested
`with-canvas-layer` grammar. Its `options` nonterminal has exactly five
alternatives: no option, bounds, paint, or both orders of the two keywords.
It no longer uses unrestricted option repetition. A native-free expansion test
covers all five valid forms, duplicate keywords, and the nonempty-body rule.
No library macro is modified. The two-batch BMP acceptance case remains intact.

The corrected chapter archive is accepted; no further prose rewrite is needed.
Use the self-contained review packager below rather than manually selecting
Scribble files. It includes every chapter reached by `@include-section`, both
pinned inventories, registration, and all source-checker dependencies. Ordinary
source validation runs on the staged sources and again after ZIP extraction.
A missing include target prevents publication. The pinned inventory bytes are
not replaced by synthetic test fixtures or freshly inferred export lists.

## Acceptance and editor handoff

The added suites contain thirteen native-free Racket cases and 28 native CPU
cases. They exercise pixel leases, detached copies, validation before mutation,
float and integer sample distinctions, explicit conversions, filtered-image
placement, single-execution output, atomic file publication after audit checks,
cache-setting restoration, and bounded memory diagnostics. No new test requests
a GPU context or GUI window. The complete retained suite still needs its native
Skia and HarfBuzz libraries and fonts. Supplied tests are not execution evidence.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" -l raco -- test tools/reference-raster-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-raster-test.rkt
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py \
  --output ../reference-r3gb-source-check \
  --source-zip ../skia-reference-r3gb-source-review.zip
```

Use fresh paths outside the checkout. The source archive supports the ordinary
checker without a neighboring checkout or an earlier editor ZIP. It is not a
complete installation for native execution or tutorial rendering. Reference-only
editing previews and integrated publication remain separate. This revision does
not change their rendering, cross-reference, or archive-validation rules.

Regenerate `SOURCE-SHA256SUMS.txt` in the complete checkout and commit it with
the documentation changes. Do not generate the repository-wide manifest from
a partial source-review fixture. Neither library implementation nor tutorial
programs are changed by this documentation batch.

## Earlier R3g-a implementation

## Geometry and advanced drawing

The upstream baseline is `c1135778c7d29a0f0806768ab5f80b3477bc4680`.
This revision includes the R3f.1 corrections missing from that committed baseline.
R3g-a adds 193 bindings and 386 public export paths: totals are 945 bindings,
1480 documented export paths, and 42 conceptual chapters. It does not change
library implementations, tutorial programs, native dependencies, or public APIs.

The ten completed module families are `advanced-layers`, `canvas-matrix`,
`canvas-primitives`, `drawables`, `geometry-primitives`, `geometry`,
`layer-options`, `portable-drawing`, `projective-matrix`, and `specialized-canvases`.
Existing paint and atlas-transform definitions remain authoritative; the added
entries do not duplicate them. All public aliases are in the binding-link probe.
Each source-module declaration is scoped to the sections defining its bindings.

New chapters cover rounded rectangles, regions, structured drawing, portable
drawing, projective matrices, layers, recorded drawables, and specialized canvases.
Existing Paths, Drawing, and Canvas State chapters are extended locally.

The stream/codec chapters retain eight displayed examples, including the
self-contained bottom-up BMP. Its acceptance case reads two rows and then one,
checks first-row values 1 and 0, and checks reconstruction instead of concatenation.
The full Reference has 90 displayed examples (79 retained, eleven new) and twenty
evaluated examples (eighteen retained, two new). Native examples do not execute
while rendering documentation. Evaluated examples use detached public values.

The geometry tests are connected to the existing acceptance runner:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" -l raco -- test tools/reference-geometry-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-geometry-test.rkt
"$RACKET" -l raco -- test tools/reference-io-test.rkt
```

The first suite contains fifteen native-free value/expansion cases. The second
contains nineteen native CPU cases; it does not request a GUI, GPU, or fonts.
The I/O suite retains the two-batch BMP case. A supplied test is not evidence
that it ran: record the actual executable, result, and any unexecuted suites.
The complete retained native acceptance suite still has its text dependencies.

## Independent source review

Use the existing source packager, with fresh paths outside the checkout:

```sh
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py \
  --output ../reference-r3ga-source-check \
  --source-zip ../skia-reference-r3ga-source-review.zip
```

The archive must include both pinned public-API inventories, all Reference
sources, registration, and all checker dependencies. Packaging runs the ordinary
checker in both the staged and extracted source trees. It must not use
`--documents-only` or reuse inputs from an older editor archive. Synthetic Python
fixtures validate the checking infrastructure, not native behavior or rendered links.

Keep Reference-only editing previews and integrated publication checks separate,
as described below. This revision does not change either rendering route or
suppress link diagnostics. The existing integrated render command remains:

```sh
python3 -B tools/check-reference.py \
  --render --quick --native --racket "$RACKET" \
  --output ../reference-r3ga-render-check \
  --review-zip ../skia-reference-r3ga-review.zip
```

## Deferred scope

R3g-b retains the raster-buffer/pixmap, image-operation, surface-property,
output-policy/audit/group, cache, and native-diagnostic work. R4 retains GPU and
GUI/DC integration. The pinned coverage manifest continues to account for every
remaining public export; documenting a shared CPU type does not count its GPU
or GUI operations as documented. This revision does not claim complete CPU
coverage or platform acceptance.

Regenerate `SOURCE-SHA256SUMS.txt` in the complete checkout after applying the
patch. A checksum file generated from a partial authoring fixture must not
replace the repository-wide source inventory.

## Earlier R3f.1 editorial cleanup

## R3f.1 scope

Baseline: `c1135778c7d29a0f0806768ab5f80b3477bc4680`
(`Expand Reference codec and stream coverage`). The totals remain 752 bindings,
1094 documented public export paths, and 34 chapters. No library behavior changes.

The result contracts of `codec-frame-info-rect` and `codec-supported-subset`
now include `immutable?`. The subset entry keeps its `#f` alternative and
positive dimensions. Five authored channel-width vector literals lose their
redundant quote; captured evaluator output is not rewritten. The opening page
states the manual's purpose, identifies `skia`, distinguishes the tutorials,
and links to API notes without repeating the table of contents.

The bottom-up scanline example contains its own two-by-three BMP generator.
The generator matches the existing test input. Successive reads of two rows
and one row report first-row values 1 and 0. A native test checks the placement
of both batches into the full image and distinguishes that result from simple
concatenation. Another native test checks a detached immutable frame rectangle
using a two-frame GIF. Existing native tests and their assertions remain.
There are now 79 displayed examples and eighteen evaluated examples. The new
scanline example is displayed only; native tests execute separately.

## Reference-only editing previews

During editing, render just the Reference. Its three outgoing tutorial links
may be unresolved when the companion manuals are absent. This is expected in
an editing preview and is deferred for this revision, not a reason to alter
those links or block source work. Binding-link failures within the Reference
are separate from these three known cross-manual references.

Use the render driver directly for a Reference-only preview, with `skia`
resolving to this checkout and an output directory outside it:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" tools/reference-render.rkt +m --htmls \
  --dest ../reference-r3f1-preview --dest-name skia-reference \
  --redirect-main https://docs.racket-lang.org/ \
  --lib skia/scribblings/reference/reference.scrbl
```

Label such output as an editing preview. The integrated `--render` and
`--review-zip` commands remain publication checks: they include companion
manuals and retain their strict link validation. No renderer, checker,
cross-reference declaration, or archive-publication rule is changed here.
The publication checks are not required for this editorial handoff.

## Earlier R3f implementation

R3f extends the committed R3e.1 Reference at
`5a2d7d410161758f9a589024eb87259691523c7b` (Expand Reference output documentation).
It adds 141 bindings and 249 public export paths. The totals are 752 bindings,
1094 documented export paths, and 34 conceptual chapters. Existing signatures,
examples, binding-source declarations, and publication checks are preserved.
No library implementation or tutorial program changes.

## R3f scope

| Chapter | New bindings | Subject |
|---|---:|---|
| Native Streams and Buffered Ports | 32 | Native cursors, memory/file output, buffering, consumers. |
| Live Port Input and Output | 11 | Synchronous chunk I/O and failure-aware image/document writing. |
| Image Codecs and Frames | 35 | Metadata, frames, ownership, orientation, size/subset negotiation. |
| Pixel Descriptions and Decoded Buffers | 18 | Descriptions, layout, and detached decode results. |
| Scanline Decoding | 25 | Native row sessions, consumption order, short reads, copied batches. |
| Incremental Image Decoding | 20 | Explicit feeds, retained destinations, progress and snapshots. |

The complete public export families of `skia/streams`, `skia/file-streams`,
`skia/stream-inputs`, `skia/live-streams`, `skia/codec-queries`,
`skia/codec-scanlines`, and `skia/codec-incremental` are covered. Public aliases
have one canonical definition and corresponding binding-probe references.
Three core codec/metadata groups use `skia` rather than private import paths.

The pixel-description chapter is a bounded prerequisite, not the complete R3g
raster-buffer expansion. It documents fifteen `skia/image-info` procedures;
`color-space-descriptor?` retains its existing Color Management entry. The three
format-inventory constants remain deferred, as do other raster-buffer/pixmap
operations. Only `raster-buffer?`, `raster-buffer-image-info`, and
`raster-buffer->image` are added here, so callers can interpret and use scanline
batches and incremental snapshots without undocumented result types.

## Semantics that must remain distinct

Native duplicate starts at byte zero; fork starts at the current cursor. Both
have independent cursors and resource ownership, but file-backed duplicates do
not guarantee immutable file contents. Resource-from-stream constructors use a
private duplicate from zero and preserve the caller's cursor. Buffered ports
consume the unread suffix, whereas live ports exchange chunks synchronously.
The buffered limit probe can consume one byte past the quota before failing.

Live image writers validate every format option and require integer quality,
including for PNG and WebP. This intentionally differs from the existing
byte dispatcher, which ignores inactive options and accepts real WebP quality.
Native file-stream construction can create or truncate immediately. It must not
be described as exclusive atomic creation or rollback-safe publication. Live
publication can leave partial bytes; native-output stream failures invalidate
further use after pinning, while simple failed native byte writes close their
wrapper. Their failure protocols must not be conflated.

A still image has one selectable frame even when its animation-metadata count
is zero. Metadata does not certify complete decode success. One-shot frame
output is an independent premultiplied RGBA8888 image; frame rectangles remain
in encoded coordinates even when output orientation is normalized. Negotiation
queries do not apply scaling/subsets to a later one-shot call.

Scanline cursors count requested rows, not just decoded rows. Short bottom-up
reads exclude native fill rows and return actual decoded rows in increasing
output-row order. Batch completion concerns one request, not the whole image.
Incremental decoding has a retained destination and explicit feeds: progressive
PNG input becomes visible at complete chunk boundaries, and other formats wait
for final input. A final feed is not proof of a complete image. Terminal native
failure may leave initialized storage available for a snapshot; cancellation
releases it. Progress with an unknown row count is not a claim of zero valid
rows, and interlaced rows are not promised final on first visit.

## Examples and tests

Seven displayed examples are added, for a total of 78. The one new evaluated
example checks a 3-by-2 RGBA description with 16-byte stride: stride, minimum
length, and full allocation are 16, 28, and 32. Eighteen evaluated examples now
appear in the manual. Native examples remain displayed code; the existing
native example runner reads those actual blocks and runs each twice.

`tools/reference_io_cases.py` contains independent call-shape expectations for
all 141 additions. It is not a captured native inventory or a replacement for
the two hash-pinned public API JSON files. The Python suite gains 33 source,
contract, alias, semantic, and test-integration regressions. Existing full
inventory and archive tests continue to use explicitly synthetic fixtures.

`tools/reference-io-pure-test.rkt` supplies fourteen native-free cases for public
pixel descriptions and private buffering/decoder-state helpers. The latter are
explicitly implementation-level tests, not public exports. The file requires a
full source checkout even though it performs no native work.
`tools/reference-io-test.rkt` supplies nineteen CPU/managed-stream cases. It uses
self-generated PNG and BMP data, not bundled external fonts or image fixtures.
The BMP rows expose bottom-up batch placement. Required native support must
fail normally rather than being silently skipped. Neither suite needs fonts,
GUI, or GPU; the retained full native suite still needs its text dependencies.

## Acceptance and editor handoff

Keep generated output outside the full checkout and use fresh output paths:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3f-source-check \
  --source-zip ../skia-reference-r3f-source-review.zip
"$RACKET" -l raco -- test tools/reference-io-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-io-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3f-render-check --review-zip ../skia-reference-r3f-review.zip
```

The registered `skia` collection must resolve to the revised checkout. The
existing seed/companion/final rendering sequence, all-alias binding probe,
strict Reference HTML gate, and extracted-archive checks are retained. A source
check does not establish rendered links or native execution. The three outgoing
Reference tutorial links remain a publication gate until the actual integrated
render and complete review archive pass. No plain-text replacement, fabricated
anchor, or unresolved-reference suppression is introduced here.

The editor should receive the complete generated archive, including `html/`,
`sources/`, and `evidence/`, not a manually selected Reference-only folder.
Source-review ZIPs include pinned inventories and are checked after extraction.
Their non-native checker is self-contained; native execution still needs the
full installed library and native dependencies.

R3g remains the next CPU coverage stage: extended geometry and projective
matrices, broader pixel/raster operations, image-operation extensions, layers,
specialized canvases, drawables, output policies/groups/audits, caches, and any
other CPU exports still enumerated as deferred. GPU and GUI/DC integration
remain R4. No placeholder definitions are counted as documentation.

## Earlier revisions

### R3e.1 page grammar and annotation behavior

The current Reference documents 611 bindings through 845 public export paths in
28 conceptual chapters. R3e adds 73 bindings and five chapters: Pictures and
Recording, PDF Documents, SVG Documents, Output Pages and Raster Fallback, and
Links and Named Destinations. The existing Image Filters chapter gains the
previously deferred `make-picture-image-filter` definition.

## R3e.1 correction and acceptance status

This correction applies after the delivered R3e sources. Its upstream baseline
is `eadcff7fce37fc9c1e64e5a4a48fb4835c9fcaa2`, which precedes R3e. The incremental
patch needs R3e already applied; the cumulative alternative includes R3e. The
611 bindings, 845 mapped export paths, and 28 chapters are unchanged.

The `with-document-page` grammar uses `canvas-id` for its binding position,
`document-expr`, `width-expr`, and `height-expr` for its arguments, and `body ...+`
for the nonempty body. Its description notes the required final expression.
The implementation already rejects an empty body through the generated `lambda`;
no macro implementation is changed. Four added expansion-only cases use the
actual public macro, not a reconstructed transformer. They accept one expression
and internal definitions with multiple results, and reject an empty body, a
body containing only definitions, and a non-identifier canvas binding. Deliberately
raising document, dimension, and body expressions must not run during expansion.
The existing output-pure acceptance step runs these cases without allocating a PDF.

The annotation entry explicitly classifies GPU-surface canvases as `raster` for
annotation behavior and links to `canvas-execution-backend` for CPU/GPU execution.
The unsupported-specialized-canvas qualification remains. No GPU test is implied
by a source check of that explanation.

The three tutorial links remain an integrated-render acceptance requirement.
The existing renderer, cross-reference declarations, and publication gate are
unchanged. A successful source check is not successful HTML publication. Keep
the exact command log, `validation.json`, and ZIP checksum together when handing
the generated review archive to an editor. The complete archive must contain
its required companion manuals; do not replace it with a Reference-only ZIP.

Use fresh paths outside the full checkout, with `skia` resolving to that checkout:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
"$RACKET" -l raco -- test tools/reference-output-pure-test.rkt
python3 -B tools/check-reference.py --output ../reference-r3e1-source-check \
  --source-zip ../skia-reference-r3e1-source-review.zip
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3e1-render-check --review-zip ../skia-reference-r3e1-review.zip
```

Inspect the actual validation result before delivering the ZIP. Source, Racket
expansion, native behavior, Reference HTML, and extracted-archive checks are
separate results. An unexecuted check or a stopped run must not be reported as
passed. In particular, the expansion tests below are supplied for execution in
a working Racket installation; Python inspection alone does not execute them.

## R3e baseline and scope

The baseline is `eadcff7fce37fc9c1e64e5a4a48fb4835c9fcaa2`, "Refine Reference
color management documentation". This is an incremental revision after the
committed R3d.1 correction, not a cumulative patch against an older baseline.
Existing API entries, examples, tags, `for-label` imports, and the two repaired
sibling-section export declarations are preserved. There are no library or
tutorial implementation changes.

All nine exports of `skia/pictures`, all fifteen exports of `skia/output`, and
all six exports of `skia/annotations` have canonical entries and alias probes.
Root-level `declare-exporting` declarations cover every subsection in these
chapters; the private implementation modules are not public import paths.

The core document APIs cover low-level lifecycles and scoped convenience calls.
Closing storage, finishing a document, and publishing a completed file remain
distinct. Failed protected PDF pages abort their whole document. SVG can finish
without any drawing, unlike PDF's completed-page requirement. SKP loading is an
explicit trust decision, not sandboxed parsing. Serialized cull bounds do not
replace the nominal dimensions used by scaled playback. Recorded pictures and
output-page callbacks have deliberately different replay semantics.

The PDF/A option documents its sRGB output intent without promising arbitrary
profile selection, sample conversion, reproducible UUIDs, or conformance
validation. Metadata's literal creator and producer defaults are preserved.
URI links and named destinations have separate validation and recording rules;
zero-size named references are still checked at finalization.

The scope does not claim completion of output auditing, output-policy records,
bounded output groups, drawables, or specialized canvas/layer protocols. Those
remain explicit deferred records for CPU completion (R3g). Streams and codecs
remain R3f. GPU/GUI/DC interfaces remain R4. The source inventories, not filename
similarity or these chapter titles, determine the remaining export coverage.

## R3e authoritative implementation sources

The following blobs were inspected at the baseline. Public names and signatures
were transcribed from these sources; regression fixtures are not live captures.

| Source | Git blob |
|---|---|
| `private/core.rkt` | `9861b7cf96ea6002c71e7eb904780d2fddff808e` |
| `pictures.rkt` | `20b06532c5973f8bb73b36acefa6ca75b8b9332f` |
| `private/picture-util.rkt` | `f2ff7ea1f4c807ddb6efeca71f84977c991b0bab` |
| `output.rkt` | `ababf6f8f8094115d8895f1a190db83b6ae96a88` |
| `annotations.rkt` | `faa9caf1f019a005129846e37e0578558481d6ce` |
| `private/pdf-util.rkt` | `50dff5e92620862d5bc8b5a93efc4c6db8ef5a21` |
| `private/svg-util.rkt` | `664003a5279f0b41b58633828689efb4700cc0c2` |
| `private/output-util.rkt` | `49566348dd6827e285b0f18aaa794b6732e0796d` |
| `private/annotation-util.rkt` | `00f049958054e27976a8ae6e784a9f08287cbc30` |
| `private/filter-graph.rkt` | `a1d92c57ecd72e96369b9bbe4c073a1eb2625676` |

Additional upstream references consulted:

- https://api.skia.org/classSkPictureRecorder.html
- https://api.skia.org/structSkPDF_1_1Metadata.html
- https://docs.racket-lang.org/scribble/doc-modules.html
- https://docs.racket-lang.org/scribble/doc-forms.html

## Examples and validation gates

The manual contains 71 displayed native blocks and 17 evaluated blocks. Eight
native examples and two pure evaluated blocks are new. The old 63 displayed and
15 evaluated examples remain unchanged. Native examples are displayed during
rendering, then executed separately by `reference-native-test.rkt`, twice in
fresh namespaces. No font files are included in source or review bundles.

`reference-output-pure-test.rkt` supplies nine native-free public API cases.
`reference-output-test.rkt` supplies eighteen opt-in CPU cases covering picture
retention and storage, document lifecycles, page aborts, copied bytes, annotations,
callback reinvocation, raster fallback, publication failure, and PDF/A metadata.
Its PDF header/output-intent checks are not a PDF/A validator or visual review.
These new native cases need Skia but no font lookup, HarfBuzz, GUI, or GPU. The
complete retained acceptance suite still needs its text fonts and HarfBuzz.

The Python runner now requires `check_review_html` for every standalone render
and staged-site check, even without `--review-zip`. A `badlink` in any Reference
page, including the identifier index, prevents an overall passing result. The
report distinguishes `scribble_rendered` from `reference_html_checked`; ordinary
source-only success leaves both false. Existing binding/xref checks still cover
all declared export paths, and the archive gate rechecks the extracted output.
Installed checks retain their existing collection-xref rules because valid
installed links can leave the package directory for other local manuals.
Portable review archives made from installed output still pass the strict
HTML check after relocation. Companion-page limitations are reported separately
and do not certify a full site.

The seed/companion/final build sequence is unchanged. This stronger required gate
is not a claim that any current rendered archive has passed it. Never substitute
a manually zipped Reference directory for an archive that failed validation.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3e-source \
  --source-zip ../skia-reference-r3e-source-review.zip
"$RACKET" -l raco -- test tools/reference-output-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-output-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3e-render --review-zip ../skia-reference-r3e-review.zip
```

Use fresh output paths and ensure the `skia` collection resolves to the revised
checkout. Source review requires the two original hash-pinned API inventories.
Synthetic Python inventories are explicitly not substitutes for those files.
Regenerate `SOURCE-SHA256SUMS.txt` only in the full checkout and commit it with
the source changes. Keep downloaded patches and output directories outside it.

## Earlier R3d development

# Skia Reference development: R3d color management

The current Reference declares 538 bindings through 742 public export paths in
23 conceptual chapters. R3d adds 39 bindings to the delivered R3c sources, moves
six standard color-space definitions into their conceptual chapter, and retains
the legacy `skia-color-spaces` subsection target. No library behavior changes.

## R3d.1 binding-resolution correction (post-R3d)

Patch baseline: `0418c5a69bfe424ad85849b124f5e75181d55f36`
(`Expand Reference color management coverage`). There are no API or behavior
changes. The totals remain 538 bindings, 742 export paths, and 23 chapters.

`declare-exporting` applies to its enclosing Scribble section and descendants,
not later sibling sections. R3d selected `skia/color-space` as a binding source
within Transfer Functions, but not its sibling RGB Gamuts and XYZ-D50 Matrices.
Likewise, Floating-Point Paints and Canvas Colors selected `skia/float-colors`,
but its sibling Floating-Point Shaders and Gradients did not. Twelve definitions
therefore used the enclosing `skia` declaration rather than explicitly
selecting their public source modules. This matches the twelve binding identities
reported in the editor's additional 40 `badlink` occurrences; a real render is
still required to confirm the correction.

R3d.1 adds the same `#:use-sources` declarations in those two sibling sections.
Their seven RGB/XYZ and five shader entries, result contracts, examples,
section tags, and `for-label` imports remain intact. Source tests guard the
section-scoped declarations and check all twelve source-module aliases against
both the coverage manifest and link probe. A regression ensures that a `badlink`
in `doc-index.html` prevents review-archive publication.

**Source inspection cannot certify rendered binding resolution.** Acceptance
requires a real Racket/Scribble build with `skia` resolving to this checkout:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py \
  --output ../reference-r3d1-source-check \
  --source-zip ../skia-reference-r3d1-source-review.zip
python3 -B tools/check-reference.py \
  --render --quick --native --racket "$RACKET" \
  --output ../reference-r3d1-render-check \
  --review-zip ../skia-reference-r3d1-review.zip
```

The render driver checks every documented alias in its binding probe and all
Reference HTML, including `doc-index.html`. The review packager requires linked
companion tutorial manuals, refuses unresolved Reference markup, and checks the
extracted archive before publication. A manually zipped Reference-only HTML
folder is **not** an accepted review artifact. A source-only pass or synthetic
HTML fixture is also not a substitute for a completed native/render check.

## R3d scope and baselines

The incremental patch applies after delivered R3c. The cumulative alternative
includes R3c and applies to `efc279080b375c376fd27793a748bd9e618110d0`, the
verified repository baseline. Apply only the matching alternative.

| Chapter | Current bindings | R3d work |
|---|---:|---|
| Color Specifications | 11 | Byte-color definitions retained; old color-space section links onward. |
| Color Management | 26 | Six moved definitions plus twenty new definitions. |
| Floating-Point Colors | 19 | Nine detached color operations and ten drawing operations. |

All thirteen exports of `skia/color-space`, nine of `skia/color4f`, and ten of
`skia/float-colors` are documented. The descriptor predicate also has its public
`skia/image-info` alias. The remaining new entries come from `skia` only.
Definitions are not repeated for re-exports. The coverage manifest retains the
exact pinned headless and GUI snapshots, rather than inventing new inventories.

The new chapter separates descriptions from samples. Creating a space or changing
its transfer function does not convert an image. ICC export constructs a new
matrix/TRC profile with fixed-point quantization, not a byte-preserving copy of an
imported profile. Its byte string is mutable. Encoder profile overrides retain
stricter requirements than general native profile import.

The detached descriptor predicate recognizes names or an immutable ICC header;
it neither parses a profile nor applies the byte limit. Floating-point paint and
shader factories instead accept copied, possibly mutable ICC input, require an
explicit description, and reject a live color-space wrapper. Their signatures
must not use the narrower descriptor predicate as their entire input contract.

Floating RGB values are inexact Racket numbers within the full finite binary32
magnitude, but construction does not round them to binary32. Alpha is checked
after conversion to an inexact Racket number. Drawing converts to native floats.
Gradient stops must be strictly increasing after binary32 rounding, unlike the
nondecreasing positions of the byte-color gradient interface. Sample conversion
through `image-convert-color-space` is the existing eight-bit CPU path; it rejects
floating-point images rather than silently reducing their precision.

### R3c editorial corrections carried forward

The image-filter crop introduction now specifies the output region rather than
a bound on internal processing. Convolution-specific input-crop semantics stay
in its own entry. The common Lighting from Alpha section contains shared numeric
and light-geometry restrictions once, including their pre/post-rounding distinctions.
All six lighting signatures and defaults remain unchanged. The runtime source and
uniform-byte results now explicitly include `immutable?` in their contracts.

### Source evidence and execution boundaries

All implementations below were read at the verified repository baseline. Blob
identities are source evidence, not evidence of native execution.

| Source | Git blob |
|---|---|
| `private/core.rkt` | `9861b7cf96ea6002c71e7eb904780d2fddff808e` |
| `color-space.rkt` | `60f69ce1f8ffc5a682258294aa5c3f731e87767a` |
| `color4f.rkt` | `0795fed3e8a999465560f3cd7d32f8c48a9713db` |
| `float-colors.rkt` | `9c29a0cf3f6e6c8b3d948f6990c8f68987fa636e` |
| `image-info.rkt` | `052e4384c0c3f9e7b2197a011990a74043cc0aae` |
| `private/color-output-util.rkt` | `9f065abe406042dc2de32f32c0865befa961ce0a` |
| `private/float-color-native.rkt` | `b1840a229874b7b94dc51813e0e9b43a6591e31f` |
| `private/check.rkt` | `2f39bb2aaaddf06bd30ee9a914e9ee0fa7ea142d` |

R3d adds six displayed blocks and three evaluated pure color-value blocks.
The totals are 63 displayed examples and fifteen evaluated blocks. The two
standard-space examples moved with their definitions and are not new examples.
Native color-space factories are not evaluated while rendering the Reference.

`reference-color-management-pure-test.rkt` has seven native-free cases for
floating values, quantization, transfer formulas and descriptor recognition.
`reference-color-management-test.rkt` has eleven CPU cases for gamma/gamut
separation, native matrix operations, ICC copying, sample conversion, source
interpretations, strict stops, clipping, and immutable runtime reflection.
The latter requires native Skia but no fonts, GUI, or GPU. The full existing
native acceptance suite still includes text cases and their font/HarfBuzz needs.

`reference_color_cases.py` provides independent call-shape expectations for the
39 additions; it is not a captured API inventory. Python tests inspect real
Scribble headers and use explicitly synthetic inventories/HTML for infrastructure
regressions. A source-only success is not Racket or rendering acceptance.

### Reproduce source and HTML review packages

Use the full checkout, with `skia` resolving to it. Keep outputs outside the
checkout and select fresh names:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3d-source \
  --source-zip ../skia-reference-r3d-source-review.zip
"$RACKET" -l raco -- test tools/reference-color-management-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-color-management-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3d-render --review-zip ../skia-reference-r3d-review.zip
```

The review command retains the seed/companion/final Reference rendering sequence.
It checks the actual archive after extraction. No Reference-only ZIP with the
three unresolved tutorial links is an accepted review handoff. Send the complete
generated `html/`, `sources/`, and `evidence/` tree, with its archive checksum.
There is no new workaround or suppression of unresolved references in R3d.
Only an actual successful run establishes rendered-link acceptance.

A source-level mismatch in the binding probe was also corrected. Its abbreviated
`blobs:`, `primitives:`, `filters:`, and `runtime:` prefixes did not match the
module-name prefixes required by `check_targets`. The probe now uses the same
module-derived prefixes for every public alias, including the new color aliases.
A regression compares all declared exports with the actual probe's imports and
references. This removes one concrete obstacle to the normal integrated render;
it is not evidence that the three tutorial links passed a fresh rendering.

Further work includes picture and document output (R3e), streams and codecs
(R3f), and remaining CPU operations (R3g), including image-info, integer/float
raster buffers and their conversions, additional image operations, and extended
geometry. PDF output-intent entries belong with document output. HDR transfer
functions and tone mapping are not implied by the SDR transfer representation.
GPU and GUI/DC integration remain R4. These are explicit remaining scopes, not
placeholder definitions counted as documented.

## Earlier R3c delivery

The Reference is one registered multi-page manual assembled from
`scribblings/reference/reference.scrbl`. R3c adds 90 bindings to the committed
R3b.1 baseline. It documents 499 bindings through 670 public export paths in
21 conceptual chapters. No library implementation or tutorial program changes.
The existing contracts, examples, `for-label` fixes, and review gates are retained.

## R3c scope and implementation baseline

Patch baseline: `efc279080b375c376fd27793a748bd9e618110d0`.

| New chapter | Bindings | Scope |
|---|---:|---|
| Path Effects and Mask Filters | 16 | Dashes, corners, trim, composition, stamps, and coverage. |
| Color Filters | 13 | RGBA/HSLA matrices, blending, gamma, tables, and lighting. |
| Image Filters | 27 | Dynamic-source graphs, sampling, morphology, convolution, and lighting. |
| Runtime Effects and Blenders | 33 | SkSL compilation, metadata, uniforms, children, and blenders. |

The first three chapters include the four predicates moved out of Paints.
Those moves do not add bindings. Five new shader operations extend Shaders and
Gradients. All fourteen exports of `skia/effects`, all nine exports of
`skia/color-filters`, and all thirty-two exports of `skia/runtime-effects` have
canonical entries and public-alias links. Core effects and graph constructors
are documented through `skia`, not through private implementation modules.

The picture-source constructor `make-picture-image-filter` is explicitly deferred
to R3e with the picture-resource interface. No placeholder picture definition or
unresolved picture binding is added. Richer color management, pictures/documents,
streams/codecs, remaining CPU coverage, and GPU/GUI remain later batches.

The descriptions distinguish shape coverage from colors, composition from parallel
combination, and a missing filter input from transparent content. A `#f` image-filter
input denotes the dynamic source. Filters attached to a paint do not automatically
process unrelated pixels already on the canvas. Crops are local output bounds,
not a request to change the current canvas clip.

Specific exceptions are local to the relevant entries: full normal trim and the
identity destination-only blend-color filter are rejected; mirror blur/convolution
tiling is unsupported; non-decal convolution tiling requires a crop. Native-float
rounding rules are distinguished from restrictions applied before rounding.

Runtime effects require complete uniform and child dictionaries. Symbol and string
keys share a normalized spelling; duplicate, missing, and unknown names fail.
Reflection and uniform packing use detached snapshots and remain available after
effect closure, while instance creation requires an open effect. Child resources
are explicitly supplied and retained. Four-byte uniform components, flat matrix
and array input, integer ranges, and premultiplied shader colors are documented.

### Implementation evidence

The wrapper sources were read at the baseline above. The following blob IDs
record their exact versions, not results of native execution.

| Source | Git blob |
|---|---|
| `private/core.rkt` | `9861b7cf96ea6002c71e7eb904780d2fddff808e` |
| `effects.rkt` | `83d38861b363f4ce67ac334ed2e5d8a9c37093ce` |
| `color-filters.rkt` | `066c59e2c3ea345efd321fe09d53696b04906aca` |
| `runtime-effects.rkt` | `6b4f0411ee3a69e062fe8980592006d5fc157af8` |
| `private/filter-graph.rkt` | `a1d92c57ecd72e96369b9bbe4c073a1eb2625676` |
| `private/runtime-util.rkt` | `ee89e93cfa911ec093a060952b1f6f429502a268` |
| `private/effects-util.rkt` | `b75e0562194d1ead9a604840fd5d99e7db0059cf` |
| `private/color-filter-util.rkt` | `9644e2d48e8fcd949468aaa3588830d8a12b272c` |
| `private/filter-util.rkt` | `78f1906eeb21e77a131b76d012bbc58469a13dba` |

The upstream SkSL guide and Skia image-filter documentation supply additional
terminology and pipeline semantics:

- https://skia.org/docs/user/sksl/
- https://api.skia.org/classSkImageFilters.html
- https://api.skia.org/classSkColorFilters.html

The m119 convolution source confirms that the public bias is divided by 255,
that non-convolved RGB uses unpremultiplied samples, and that non-decal tiling
requires a crop. Its Git blob is `0408d8e538165b26baea48712b4256d2389f784a`
in `google/skia`, `src/effects/imagefilters/SkMatrixConvolutionImageFilter.cpp`.

### Examples and acceptance

Seven new displayed examples bring the native example count to 57. The twelve
previously evaluated color/matrix/atlas examples are unchanged. No new effect
is compiled or rendered by the manual's example evaluator.

`reference-effects-pure-test.rkt` contains six validation-only test cases.
`reference-effects-test.rkt` contains seventeen native CPU cases for retained
resources, color matrices and composition, copied tables, dynamic-source graphs,
runtime metadata, uniform/child validation, compilation errors, and blenders.
The new cases do not require fonts, a GUI, or a GPU context. The complete existing
native suite still includes text tests and therefore has its own font requirements.
These are test descriptions, not claims that the tests ran in a delivery environment.

`reference_effect_cases.py` supplies independent signature expectations for the
ninety additions. Python regressions inspect the real definitions and compare
them with those expectations; synthetic export/HTML fixtures remain explicitly
separate from the full pinned-inventory and native acceptance checks.

Run from the full revised checkout, keeping all output outside the repository:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3c-source \
  --source-zip ../skia-reference-r3c-source-review.zip
"$RACKET" -l raco -- test tools/reference-effects-pure-test.rkt
"$RACKET" -l raco -- test tools/reference-effects-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3c-render --review-zip ../skia-reference-r3c-review.zip
```

Use fresh output paths and ensure `skia` resolves to this checkout. The generated
review archives include pinned inventories and validate extracted copies. A patch
bundle containing changed sources is not a substitute for that accepted review
archive. Companion-manual diagnostics remain separate from Reference acceptance.

## R3b.1 editorial cleanup and review handoff

Patch baseline: `c0192da1a0ae0b717e5ab9a51b495a2706b0d1e9`.
The binding and export-path counts remain 409 and 525. Existing definition
headers, native examples, and `for-label` imports are unchanged.

The atlas-transform subsection is now titled **Atlas Transforms**, with the
existing `skia-atlas-transforms` tag retained. Its constructor example computes
`#(2.0 0.0 4.0 12.0)` and uses Scribble's `eval:check` to reject a different result.
A separate evaluator imports only the two needed public geometry bindings and
is closed after the subsection. This adds one pure evaluated block, bringing
the current total to twelve; the fifty displayed native blocks are unchanged.
The existing native-free atlas-value test also checks the coefficients and the
mapping of the local anchor `(3, 4)` to `(10, 20)`. The intercept description is
shortened without changing its rejection of blobs containing transformed runs.

A Reference-only HTML ZIP with the three unresolved cross-manual links is not
an accepted review archive. The existing render driver exchanges the companion
manuals' cross-reference information before rendering the final Reference.
The existing packager requires those manuals and checks the extracted archive.
Neither mechanism is replaced in this editorial revision. Regressions now
exercise both the reported Reference-only badlink case and resolved links whose
companion files were omitted. Neither case may publish a ZIP.

Generate the handoff in the full checkout, with fresh output paths:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3b.1-check --review-zip ../skia-reference-r3b.1-review.zip
```

Send that complete generated archive, not a manually reduced Reference folder.
It includes `html/`, matching `sources/`, and `evidence/`. Inspect
`evidence/review.json` for extracted-source checks and separate Reference and
companion link diagnostics. Source consistency is not rendered-link or native
acceptance. When rendering or native tests have not run, report them as
unexecuted rather than creating a purportedly accepted HTML archive.

## R3a.1 editorial cleanup

R3a.1 revises the delivered R3a sources without changing any documented binding,
signature, example, or library behavior. The `layout-text` entry repeats the
explicit-script justification restriction where readers look up the keyword.
The `font-break-text` and `typeface-from-bytes` entries describe observable
results rather than native loading steps. The technical term `shaping` is
lowercase; its introductory sentence begins with an ordinary word.

The font-data loading mechanism remains an implementation detail. On macOS,
`typeface-from-bytes` rewraps the requested TrueType collection member as a
standalone SFNT before native loading. Other platforms submit the collection
index to the native loader. The public guarantee is selection of the requested
member without silently substituting another face, not a prescribed mechanism.

Use `--source-zip` or `--review-zip` from a full checkout for the next editorial
handoff. An incremental patch bundle is not the self-contained source-review
archive. The generated archive must include both pinned API snapshots and pass
the ordinary checker after extraction; `--documents-only` is not a substitute.

## Scope and chapter ownership

| Chapter | Bindings | Scope |
|---|---:|---|
| Notation and Conventions | 0 | Signatures, numeric and coordinate conventions. |
| Resources and Lifetimes | 6 | Existing lifetime protocol and byte limit. |
| Surfaces and Canvases | 11 | Construction, backing, dimensions, snapshots, pixel copies. |
| Canvas State | 19 | Save/restore, affine transforms, clipping and backend queries. |
| Color Specifications | 17 | Byte colors and standard color-space construction and queries. |
| Paints | 33 | Construction, copy, getters/setters, reset, blending and stroke expansion. |
| Shaders and Gradients | 14 | Basic gradients, image and composite shaders, local matrices. |
| Path Effects and Mask Filters | 16 | Geometric effects, repeated stamps, and coverage. |
| Color Filters | 13 | Color matrices, composition, gamma, tables, and contrast. |
| Image Filters | 27 | Dynamic-source graphs, resampling, convolution, and lighting. |
| Runtime Effects and Blenders | 33 | Compilation, binding dictionaries, metadata, and blenders. |
| Drawing | 8 | Paint, line, rectangle, rounded rectangle, oval, circle, path and polygon. |
| Paths | 64 | Commands, geometry, iteration, filled-region operations and measurement. |
| Affine Matrices | 24 | Affine operations and detached scaled-rotation/translation values. |
| Images | 15 | Encoded/raw construction, metadata, pixel copies, subsets and drawing. |
| Image Encoding | 7 | PNG/JPEG/WebP byte encoders and file writing. |
| Font Managers and Typefaces | 48 | Lookup, styles, owned faces/sets and copied font data. |
| Fonts and Text Measurement | 58 | Font controls, metrics, simple text and glyph queries. |
| Shaped Text | 14 | Captured shapers, glyph clusters, drawing and outline conversion. |
| Text Blobs | 29 | Basic blobs, multi-run builders, metadata, intercepts and text on paths. |
| Text Layout | 43 | Wrapping, alignment, providers, bidi/fallback and line/run metadata. |

Resources and byte-color coverage is retained from the foundation. Image
Encoding declares both `skia-png` and `skia-encoding`, keeping `skia-png` first
to preserve the published `skia-png.html` filename. Both section targets are
resolved through real Scribble xrefs and checked in the link probe and review ZIP.

The dispatcher procedures `image->encoded-bytes` and `save-image` now use `any/c`
for five format-dependent keywords. The selected format's restrictions are
specified in one options table. Inactive options are ignored; common color
options remain checked for every format. The individual encoders keep precise
contracts. Defaults and accepted keyword spellings are unchanged.
The `shader?` entry is colocated with shader construction and operations.

This is a bounded core reference, not complete coverage of every export in a
module whose file name mentions geometry, images, or surfaces. The remaining
scope includes extended geometry (arcs, rounded-rectangle records, regions,
shape recognition and batch operations), projective matrices, specialized
canvases and layer protocols, raster buffers and additional pixel formats,
image-operation extensions, codecs and incremental sessions, further color management,
picture-source filters, recorded pictures, documents, streams, caches, and GPU/GUI integration.
The subsequent stages must add their own semantic entries. No
unwritten entries are hidden behind artificial anchors or counted as complete.

## Authoritative source checks

R3a and R3b implementation baseline: `1003a8ca6481b1c98a1240e215853713bb7a1ee3`.
R3b's incremental patch starts from the delivered R3a.1 source state. When the
upstream branch still lacks R3a, use the cumulative alternative against that
verified commit. Neither partial fixture is represented as a full clone.
The preparatory cleanup was based on `3a9c69c3dc71e29f008d577f45de5a926133535f`.
R2.1 was based on `f20b68d866f6c1b92de94c19c62754978a8e9a0d`.
The upstream `for-label` and module-declaration corrections are preserved.
The following implementation blobs supplied the core and text specifications. The public paths,
not private implementation modules, are the documented import paths.

| Implementation file | Git blob |
|---|---|
| `private/core.rkt` | `9861b7cf96ea6002c71e7eb904780d2fddff808e` |
| `typefaces.rkt` | `fef5ba345c0b9470e566af1e9a28049f409ef9b1` |
| `text-blobs.rkt` | `d96474626f74cbddd130ce2a66f5ed2c4d470b57` |
| `private/text-run-util.rkt` | `20e60899f5f2f5ae7fe3ccb45be5d5a18ff8c295` |
| `geometry-primitives.rkt` | `6f8c6d310281131b5e7ae802d615b0d9804de898` |
| `fonts.rkt` | `5f54ddc7defd245b40072e3ba5df8c8106e0cb49` |
| `private/typeface-util.rkt` | `4346d4d9993a0c1e0f60fad03203f4d5e0cb2575` |
| `private/path-matrix.rkt` | `3abcea67c6c0f8a33f96fefec7dced8bbc4fe965` |
| `matrix.rkt` | `6660a7bf2aa04978787d12f7f47cf7f21338c85a` |
| `geometry.rkt` | `aed94b5150562bd9d9b2eca6faa8806a4562fd49` |
| `private/filter-util.rkt` | `78f1906eeb21e77a131b76d012bbc58469a13dba` |
| `private/geometry-completion-util.rkt` | `cd7ad2cacb690b7d0775e8f817b0686788d18ef0` |

Native distinctions were also checked against Skia's public API documentation
and the `chrome/m119` source. In particular, `src/core/SkPath.cpp`, blob
`15f4bbf3e94b38619a52c3861ac2437588c9a72a`, specifies implicit moves after close
and conic reduction: nonpositive weight becomes a line; weight one becomes a
quadratic. SkPathMeasure documents clamping, while the Racket wrapper separately
rejects excessive position/tangent distances. Preserve that distinction.

Source locations:

- https://github.com/soegaard/skia-for-racket/tree/1003a8ca6481b1c98a1240e215853713bb7a1ee3

- https://github.com/soegaard/skia-for-racket/tree/ba19990ce41cbddd326598ef8d69b3b7495967c7
- https://github.com/google/skia/blob/chrome/m119/src/core/SkPath.cpp
- https://api.skia.org/classSkPathMeasure.html
- https://api.skia.org/classSkPaint.html
- https://docs.racket-lang.org/scribble/doc-forms.html
- https://docs.racket-lang.org/style/reference-style.html

## Coverage and canonical bindings

`api/reference-coverage.json` assigns a canonical chapter and import paths to
each binding. Eleven color bindings have aliases in `skia/color`, all twenty-one
affine bindings in `skia/matrix`, and eleven paint operations in `skia/geometry`.
R3a covers all 32 exports of `skia/typefaces` and all 15 exports of `skia/fonts`,
with one definition per binding and probe links for both public import paths.
Each alias is intended to resolve to the same native Scribble definition target
as its canonical binding. Equal names alone are not evidence of identity.

The Python checker reads actual `defproc`, `defform`, `defparam`, `defstruct*`,
and `defthing` headers. A separate Racket checker reads the same source with
Racket's Scribble reader, compares live signatures, and checks label identity
for every declared alias. Unsupported forms still fail closed. The supported
constant declaration uses a literal predicate, checked against the public value
at runtime. Procedure headers can now use a trailing `...` or `...+` positional
argument group; their unbounded arity uses Racket's negative bit-mask convention.

Structure support remains restricted to immutable transparent declarations with
no superclass, automatic fields, or renamed constructor. The constructor,
predicate, accessors and descriptor are derived from the real declaration.
Homonyms will require qualified definition IDs before they can be documented;
phase-zero/default-space restrictions are not silently relaxed.

Full source checks use the pinned headless and GUI snapshots, verified by Git
blob hash. Every remaining export gets an explicit deferred record in the
report. The `--require-complete` option rejects any deferral. Defaults, result
contracts, macro grammar, ownership and rendering semantics are not inferred
from arity reflection. The test-only inventories in `test-reference.py` are
synthetic regression fixtures, not live API captures or substitutes for those
full-snapshot checks. The R3a expectations are in `tools/reference_text_cases.py`;
they independently specify call shapes and aliases without parsing the prose.

## R2.1 semantic and compatibility checks

The native core test includes a format/option matrix for both dispatcher
procedures. It covers all five format-specific keywords in all three formats,
fractional JPEG/WebP quality, the three common color options, and valid active
settings. Invalid active options must fail without truncating an existing file.
Python checks inspect the dispatcher declarations and unchanged individual
encoder contracts; they do not simulate or certify native encoder behavior.

The three focused examples compare normal/raw path iteration, independently
extracted paths with and without an initial move, and constructor/native-reset
paint settings. Separate native cases assert their results. Two displayed
color-space examples exercise standard spaces, equivalence and conversion.
None of the added examples is evaluated by the documentation build.

The section-link manifest covers both encoding tags. Source checks reject an
omitted alias or a tag reorder that changes the legacy page name. Runtime checks
resolve the actual tags through Scribble. HTML checks validate those destinations,
their anchors when present, and both links from the probe. Review packaging
rechecks the extracted alias destinations. No replacement HTML anchors are invented.

The path extraction example was also checked against `chrome/m119`
`src/core/SkContourMeasure.cpp`, Git blob
`f34840069df89814e4effc171ff16aee19628ba3`: `getSegment` omits the initial move
when requested, and line extraction then calls `lineTo` with the segment endpoint.
The previously inspected `SkPath.cpp` supplies the implicit move for an empty path.

## Blend-mode and clipping regressions

The contracts of `make-paint`, `paint-set-blend-mode!`, and `make-blend-shader`
list the same 29 accepted blend modes. The Python regression compares their
actual parsed contracts against one independent expected enumeration, including
cardinality and ordering. It is not enough merely to find `or/c` in each header.
The native suite checks rejection of an unsupported symbol and preservation of
the paint's previous mode after rejection.

The clipping example starts from the same initial clip in each iteration, then
intersects with or subtracts a second rectangle. Independent canvas-state scopes
prevent the first clip from affecting the second. Interior sample points show
that difference clipping does not add pixels outside the original clip. The
native regression also checks restoration of the save count and the full clip.
The preparatory cleanup had 26 displayed native example blocks; acceptance executes them
separately from documentation rendering. Eleven pure evaluated examples remain.

## R3a semantic scope and acceptance

Typeface entries distinguish design metadata, owned faces/style sets, and
copied font data. Native font lookup is platform-dependent. No family, glyph ID,
exact metric, ligature count, or complete Unicode coverage is assumed portable.
The table-tag conversions have intentionally different domains: `font-table-tag`
accepts integers, four bytes, or four Latin-1 characters; `font-table-tag->bytes`
accepts only an unsigned 32-bit integer. Symbols are not table-tag inputs.

Font entries distinguish simple advances from ink bounds, direct glyph mapping
from shaping, and character counts from UTF-8 byte offsets. Shapers snapshot
font state, positioned blobs capture their font state, and layouts retain live
shaper/manager dependencies rather than owning every fallback font permanently.
The constructors of the internal layout/metrics records are not documented as
public structure constructors; their exported predicates and accessors are.

Two existing limitations are specified rather than changed. Vertical shaping
preserves the native signed y advance; it is not automatically converted into
downward-positive vertical paragraph layout. In single-font `layout-text`, an
explicit script is normalized to a string for shaping, while the justification
opportunity checks compare inferred symbol tags. Thus explicit script selection
does not enable the CJK/Arabic-specific opportunities that script inference can
supply. These descriptions follow the pinned source; they are not new native
acceptance results or reasons to change the library in a documentation patch.

The five chapters add 18 displayed blocks, for 44 total. All eleven existing
pure evaluated blocks are unchanged. Documentation-time evaluation does not
load fonts or HarfBuzz to run the new examples. The existing native example
runner reads the real blocks and runs each twice in fresh namespaces.

`tools/reference-text-pure-test.rkt` adds three native-free test cases for style
normalization, table-tag conversion and break opportunities. It imports the
public Skia module but does not construct a font or initialize native libraries.
`tools/reference-text-test.rkt` adds twelve opt-in native CPU/HarfBuzz cases for
retained and copied ownership, glyph metadata, UTF-8 boundaries, shaper/blob
snapshots, wrapping, provider validation, and live layout dependencies. The tests
require a default font with basic Latin characters. Set `SKIA_REFERENCE_TEST_FONT`
to a local font file to select another face for those semantic tests. Displayed
examples still use the default face. No font binaries are distributed here.

The Python regressions check 169 independent call shapes, 47 re-export aliases,
selected full contracts and defaults, rejection of documentation drift, probe
coverage, and separation of displayed examples from native execution. Their
small Racket-like reader checks delimiter nesting, not compilation. The two
Racket suites and rendered examples remain separate acceptance steps.

## R3b scope and semantic checks

The Text Blobs chapter now owns all 23 exports of `skia/text-blobs`, in addition
to its six core entries. The Affine Matrices chapter owns the three supporting
atlas-transform values from `skia/geometry-primitives`. Those helpers make the
transformed-run contracts usable without an undocumented predicate. The rest of
`skia/geometry-primitives` is still deferred. Existing chapter tags, signatures,
examples, and `for-label` corrections are preserved.

The canonical export mapping checks each new binding through both `skia` and
its narrower public module. The binding-link probe includes both import paths.
The R3b Python regression expectations are independent transcriptions of the
pinned public implementations, not live captures or replacements for the complete
API snapshots. Full inventory validation still requires both pinned JSON files.

The entries specify the builder's single-use lifecycle and failure boundary,
validation of empty appends, captured fonts, logical runs versus native merging,
and the exact representations of detached run descriptions. Metadata uses
UTF-8 scalar-start byte offsets, permits repetitions and descending offsets,
and is not a proof of correspondence between text and glyphs. A transformed
run uses four scaled-rotation/translation coefficients, not a general affine
matrix. Intercept queries reject such runs instead of silently ignoring them.

Text-on-path placement checks glyph origins against one selected measured
contour. It neither fits nor wraps text, even when measurement forces closure.
The tangent determines both rotation and the signed normal. Glyph extents may
cross a contour endpoint even when every checked origin is in range.

R3b added six focused displayed examples. With the R3b.1 atlas example, the manual
contains 50 displayed native blocks and twelve pure evaluated blocks. Native examples
are not added to documentation-time evaluation. `reference-native-test.rkt` reads the
actual blocks and is configured to execute each twice in fresh namespaces.

`reference-blob-values-test.rkt` contains four native-free cases for atlas values,
anchors, rotation, zero scale and validation. `reference-blobs-test.rkt` contains
seventeen native CPU/HarfBuzz cases for empty builders and appends, preallocation
errors, captured fonts, positioning and copied inputs, metadata, run inspection,
intercepts, outlines, contour selection, normal orientation, range failures,
empty drawing, and equivalence of direct versus retained path drawing. Native
font tests require a face with Latin A/B outlines. `SKIA_REFERENCE_TEST_FONT`
may select a local font; no font binary is packaged.

A public, deterministic allocation-failure injection hook is not available.
The post-allocation builder-failure guarantee is checked against the source;
its out-of-memory path is not claimed to have been exercised by these tests.
GUI, GPU, screen-reader, installed-site and hosted-site acceptance are separate.

Pinned implementation and native API sources:

- `text-blobs.rkt` at the pinned repository commit above.
- `private/text-run-util.rkt` at the pinned repository commit above.
- `geometry-primitives.rkt` at the pinned repository commit above.
- https://api.skia.org/classSkTextBlob.html
- https://api.skia.org/classSkTextBlobBuilder.html

Use the R3b checks from the full revised checkout, with fresh output paths:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3b-source \
  --source-zip ../skia-reference-r3b-source-review.zip
"$RACKET" -l raco -- test tools/reference-blob-values-test.rkt
"$RACKET" -l raco -- test tools/reference-blobs-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3b-render --review-zip ../skia-reference-r3b-review.zip
```

An incremental delivery is not the independently checkable source-review ZIP.
That archive must be generated with the ordinary checker, including the pinned
inventories, and rechecked after extraction. Do not substitute synthetic test
inventories or describe a documents-only pass as full export validation.

## Running the checks

Keep generated output outside the repository so it does not enter the source
manifest. The `skia` collection must resolve to the revised checkout.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r3a-source
"$RACKET" -l raco -- test tools/reference-matrix-test.rkt tools/reference-text-pure-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r3a-check --review-zip ../skia-reference-r3a-review.zip
```

Use fresh output paths. The matrix test needs only the public `skia/matrix`
module, not native Skia. It checks coefficient order, detached inputs, rounding,
composition, inversion, point/vector differences and transformed bounds.
The Reference itself evaluates only pure color, affine-matrix, and atlas-transform examples.
Native examples are displayed as code and run only by explicit acceptance tests.

The render driver retains Revision 2.1's module-based root prefixes and `top`
tags. It builds a Reference seed, the three linked companion manuals, and then
the final Reference with their cross-reference information. The final Reference,
not the seed, must pass. The probe covers all 670 export paths, including matrix
constants and geometry aliases. The Quick check still targets its six original
foundation identifiers; it is not full tutorial-site acceptance.

Companion tutorials use native Skia for their diagrams. Text acceptance also needs HarfBuzz.
Native acceptance adds
`reference-native-test.rkt`, `reference-core-test.rkt`, and `reference-text-test.rkt`;
none opens a GUI or
creates a GPU context. The first reads every displayed `racketblock` example from
the actual chapters and runs each twice in a fresh namespace and temporary
working directory. The second checks state restoration, clipping, paint copies,
retained getters, native paint defaults, path snapshots, curve bounds, conic
reductions, path measurement, independent images, standard color spaces and encoder options.

The review ZIP gate checks the final HTML, sources and resources, then checks
an extracted copy. It refuses unresolved Reference links, stale source hashes, missing Reference
assets or incorrect definition destinations. A passing Python fixture test or source-only
check is not a successful Racket build. The deliberately limited
`--documents-only` mode cannot establish export coverage, runtime correctness,
or rendered-link success.

## Independently checkable source review

A source-only review ZIP does not need Racket or native libraries:

```sh
python3 -B tools/check-reference.py --output ../reference-source-check \
  --source-zip ../skia-reference-source-review.zip
```

The command requires the full pinned inventories; `--documents-only` cannot be
combined with `--source-zip`. It includes the Reference sources and manifest,
`info.rkt`, the ordinary checker and its imports, these development notes, and
the three tutorial source files declared by the manifest. It copies
`api/public-api-headless.json` and `api/public-api-gui.json` verbatim and verifies
their pinned Git blob hashes. Missing inputs fail rather than produce a limited
archive mislabeled as independently checkable.

Both the source-only ZIP and `--review-zip` contain this same source input set.
The packager runs the ordinary checker in the staging copy and again in the
extracted ZIP. Each check starts a new Python process in an unrelated directory,
with environment and user-site imports disabled. Neither process uses
`--documents-only` or a neighboring checkout. Its complete source result must
match the original, including inventory comparison and explicit deferrals.
Only then is the archive published without replacing an existing file.

For independent review, extract the ZIP, enter `sources/`, and run:

```sh
python3 -B tools/check-reference.py --output ../independent-source-check
```

The archive is self-contained for this non-native check, not for running Skia or
rendering every tutorial. It does not include the native libraries, the complete
implementation, or all tutorial dependencies. The regression suite exercises
isolated subprocess checks with explicitly synthetic inventories; those results
are not a claim that the repository's pinned inventory or native build was run.

## Partial HTML scope

The `html_link_scopes` field in the validation report separates Reference pages
from packaged companion tutorials. The review ZIP records the same diagnostic
under `link_scopes` in `evidence/review.json` and rechecks it after extraction.
Each scope reports existing local hyperlinks and broken targets independently
of `badlink` markup and `RktErr` identifiers. Counts of verified hyperlinks never
hide text that Scribble failed to turn into a link.

A companion tutorial may refer to tutorials or APIs outside a partial review
bundle. Those unresolved references are reported, not suppressed, and do not
by themselves reject an otherwise valid Reference review. Reference failures
still reject publication. Remote hyperlinks are counted but not fetched by this
inspector; machine-local links are reported separately from portable targets.
The report always states `complete_site_checked: false`: neither a partial
bundle nor this scoped inspection certifies the full installed or hosted site.

## Installed documentation and publication

Use the actual installed package name. With the existing repository convention:

```sh
"$RACKET" -l raco -- setup --no-zo --pkgs skia-for-racket
python3 -B tools/check-reference.py --installed "$PWD/doc" --racket "$RACKET" \
  --output ../reference-r3a-installed
python3 -B tools/check-reference.py --site ../site --site-source "$PWD/doc" \
  --targets ../reference-r3a-installed/runtime.json --output ../reference-r3a-site
```

The installed check uses the real collection xref and requires the resolved
binding and tutorial targets to belong to the expected output. The Pages check
relocates only known package links in an already copied staging tree. Neither
adds fabricated targets or suppresses unresolved references. The existing Pages
workflow invokes these checkers; the new pure and native tests are included in
those invocations without changing library modules or tutorial programs.

Visual review, screen-reader acceptance, the user's macOS/Racket combination,
and GPU/GUI behavior remain separate checks. A Linux CPU build is not Metal or
screen-reader evidence.

## Source inventory

Run `python3 tools/update-source-sums.py` and then its `--check` mode in the full
checkout after applying a patch. Never regenerate `SOURCE-SHA256SUMS.txt` from a
partial fixture. Commit the updated manifest together with the source changes.