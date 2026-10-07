# Changelog

## 0.75a — Native streams and buffered ports (package 0.75)

Owned native memory/file input and dynamic-memory output; safe duplicate
ownership for codec/typeface input; trusted stream picture loading with
opaque audit provenance; explicitly buffered ports with limits, cancellation
and ownership rules. Live port callbacks and streamed output remain 0.75b.
Includes focused acceptance and central regression integration.

## 0.74 — Advanced layers, drawables and specialized canvases

- Add immutable layer options and the pinned SaveLayerRec ABI, protected scoped layers, explicit clipping and discard hints.
- Add real native recorded drawables, picture snapshots, generation/size queries and retained/immediate drawing. No native Racket replay callbacks.
- Add callback-scoped NoDraw and exclusive same-backend NWay/Alpha8 Overdraw canvases with owner locks and exceptional state cleanup.
- Preserve GPU-affinity and document provenance through advanced layer backdrops and drawable graphs.
- Keep backdrop/initialization/LCD/float document requirements explicit, and reject diagnostic canvases as replacement output-raster authorities.
- Add pure/native/GPU and independent PDF/SVG acceptance under the existing three-workflow organization.

## 0.73 — GPU formats and surface properties

- Add immutable surface properties and checked native roundtrips, retaining unknown pixel geometry by default.
- Add reviewed integer/F16/F32 GPU requests with context-specific capability limits and no CPU/format fallback.
- Add transactional format-aware pixmap readback and independent raster buffers; preserve float formats through image staging and detachment.
- Retain legacy RGBA-only buffer transfer behavior, explicit quantization and native ownership rules.
- Include full staging configuration in reuse and preserve precision in DC alpha intermediates.
- Verify native backend descriptor scalars at scoped creation. Integrate source/native/GPU/SDR-document evidence into the existing Acceptance workflow.

## 0.72 — Direct image operations

- Add CPU and explicit same-context GPU filter application returning an owned image, valid backing subset and geometric offset. Require a finite clip and reject float precision narrowing.
- Add transactional format-aware reads/scales into leased pixmaps and independent raster-buffer conversion without an implicit eight-bit staging step.
- Add native identity, alpha-only, lazy, texture, validity and directly available pixel queries, plus independently owned non-texture/raster image references.
- Add raw image shaders with retained ownership, explicit color interpretation and conservative document policy.
- Preserve float provenance, padding, exclusive lease and GPU transfer contracts. Add native, document, GPU and canonical package-version acceptance.

## 0.71 — Floating-point pixels and colors

- Add F16/F32 raster storage and exact half-float sample encoding without changing seven integer-format APIs.
- Add finite extended Color4f values, explicit packed-color conversion, source-space paint/solid/gradient factories, by-value canvas clear and blend operations, and native float pixmap reads/fills.
- Preserve raw stored premultiplication and detached metadata; validate nonfinite/overflowing input before mutation and retain copied color-space ownership.
- Track float precision in paint/image/shader provenance. Document export requires an explicit raster/quantization boundary, not implicit eight-bit loss.
- Add ABI, precision, conversion, lifetime, policy and native-rendering tests with independent document/GPU pixel inspectors. HDR presentation and generalized GPU formats remain later stages.

## 0.70.0 — General image information and integer raster storage

- Add detached immutable image-info and named/copied-ICC color-space descriptions.
- Add RGBA8888, BGRA8888, RGBX8888, Alpha8, Gray8, RGB565 and RGBA1010102 storage with checked alpha semantics and exact integer samples.
- Preserve legacy RGBA constructor, byte-order and premultiplication behavior; add explicit raw storage, staged conversion, opacity and plain alpha extraction.
- Retain exclusive/expired pixmap leases, transactional validated writes, padding canaries, independent image copies and initialized raster targets.
- Guard legacy GPU readback against incompatible layouts; generalized GPU targets remain 0.73.
- Add pure/native tests, fourteen PDF/SVG documents and seven explicit-RGBA GPU captures with independent inspectors and required acceptance lanes.
- Reconcile six 0.70 families without treating source declarations as native execution evidence.

## 0.69.0 — Multi-run text blobs and shaped text-on-path

- Add single-use owned builders for default, horizontal, XY and RSXform runs, copied optional UTF-8/clusters, and retained per-run font snapshots.
- Add detached run inspection, independently owned run-font copies, geometric intercepts, and positioned glyph outlines.
- Reject intercepts on RSXform blobs rather than accepting m119's silently incomplete results.
- Place shaped glyph origins and normal offsets on an explicit contour without rekerning, character/glyph conflation or silent clamping.
- Preserve legacy positioned blobs; replay new transformed outlines with captured fonts and explicit missing-outline errors.
- Add original Unicode/GSUB fixtures, pure/native regressions, seven PDF/SVG documents, six GPU captures and independent geometric/pixel inspectors.
- Update the three 0.69 capability groups; execution evidence remains separate from source declarations.

## 0.68b — Font options and glyph queries (package version 0.68.2)

- Add embedded-bitmap, forced-auto-hinting and baseline-snap controls while preserving pinned defaults.
- Preserve the new flags in shaper, text-blob and fallback font snapshots.
- Add owned font-typeface queries and reference-retaining replacement without resetting font options.
- Add bounded immutable glyph widths/bounds/positions, copied transformed batch outlines, and simple UTF-8 prefix fitting returning Racket scalar counts.
- Keep callback failures inside Racket until the native call returns; pin callback input buffers and clean up partial results.
- Add pure/native tests, six PDF/SVG documents, GPU scene/transfer validation and a dedicated acceptance workflow.
- Reconcile the four remaining 0.68 capability families without inventing execution evidence.

## 0.68a — Typeface resources (package version 0.68.1)

- Add copied-byte/TTC typeface construction, manager-specific construction and
  owned style-set enumeration/matching with generic resource cleanup.
- Add detached style/metadata, checked table tags and bounded immutable table
  copies, optional design-unit kerning, and raw font bytes with their reload index.
- Preserve native pins, package minimums and SkFont/shaper state. Split the four
  remaining font option/glyph-query capabilities into 0.68b.
- Add original procedural font fixtures, pure/native ownership tests, six vector /
  native-text PDF/SVG documents, inspection tests and a dedicated acceptance gate.
- Reconcile the four capability groups and binding inventory without asserting
  execution evidence until host and CI validation run.

## 0.67.0 — Geometry completion

- Add checked endpoint/oval/tangent arcs, explicit shape starts, polygon and
  matrix append, detached recognition, conic conversion and bounded native
  path-operation batches. Preserve the existing raw/normal snapshot APIs.
- Add paint scalar queries, explicit SrcOver-fallback blend inspection,
  dithering, native reset and owned path expansion with a separate fillable flag.
- Clear paint provenance and GPU child slots only after a successful reset;
  independently retained children remain associated with their original context.
- Add sentinel-safe region clipping/spans and sufficient-test quick predicates;
  add detached native-normalized rounded rectangle operations.
- Reconcile nine capability groups, adding 55 native declarations. Four low-level
  iterator/empty-value declarations remain covered through Racket equivalents.
- Add native-free/native/GPU suites, 14 strictly vector PDF/SVG fixtures and
  independent document inspection. Add the Geometry completion workflow.
- Implementation candidate: host/CI Racket and native validation is required.

## 0.66.0 — Effects and shader composition

- Add native 1D/2D path effects, coverage lookup/gamma/clip masks, shader masks,
  Perlin noise, empty/filter-wrapped/composed shaders, arithmetic blenders,
  custom-blender image filters, and picture-filter target bounds.
- Preserve GPU affinity through shader masks and retained paint-mask getters;
  leave ordinary masks independent of ambient GPU resources.
- Integrate provenance and conservative bounded PDF/SVG fallback policies.
- Reconcile all eight 0.66 capability families and 15 additional native symbols.
- Add pure/native/GPU tests, 32-document acceptance, independent renderer checks,
  an example, and the selected Linux/Windows Effects workflow.
- Rebuilt delivery candidate; actual Racket/native host and CI validation required.

## 0.65.0 — Pinned capability inventory and API decisions

- Add reviewed capability-family/C-declaration dispositions, managed-source
  crosswalks, public anchors, test references and explicit future stages.
- Audit all nine CPU/GPU binding registries, including Metal/D3D interop;
  reconcile existing path iteration, rounded clipping and GPU image operations.
- Add deterministic report generation, strict complete-checkout drift checks,
  exact pinned-upstream source validation and isolated m119 symbol resolution.
- Preserve historical aggregate evidence without inventing feature-level
  rendering results or confusing m153 candidate probes with the m119 default.
- Decide additive image-info/color-space/float-color/lease/transfer contracts.
  These are future design decisions, not newly exported runtime APIs.
- Add source regressions and a separate API inventory CI workflow. Existing
  rendering semantics, package minimums and native pins remain unchanged.

## 0.64.0 — Bounded font and DC compatibility closure

- Parse single-family comma/Pango descriptions using Racket's own Pango library:
  weight, slant and width are retained, with font% size/explicit overrides.
  The private parser owns/frees a description; it never lays out or draws text.
- Honour font-name-directory mappings for explicit face requests, and pass
  width to both primary and fallback typeface selection.
- Reject family cascades, non-normal variants, gravity/axes and future fields
  instead of dropping semantics. Complete the combined/grapheme separator guard
  with VT/FF; character-mode and NUL/offset behavior remain unchanged.
- Add skia-dc-compatibility declarations, 35 pure and 22 native acceptance cases,
  exact installed-interface/arity accounting, a headless example, and a strict
  wrapper around existing document and optional GPU/GUI validation.
- Run described-font pict content through all existing consumer paths. Preserve
  native pins, public raster/GPU lifetimes, document auditing and byte limits.
- Declare remaining compatibility exclusions for 1.0 rather than claiming full
  bitmap-dc%/Cairo/Pango equivalence. API/package stabilization is next.

## 0.63.0 — DC authoring for PDF and SVG

- Add `skia/dc-output`: scoped production DC command capture, closed before
  replay into PDF/SVG or an explicit CPU preview. User authoring runs once.
- Reuse native path, text and bitmap drawing callbacks. Preserve receiver
  units, margins and affine transforms through bounded output-group replay.
- Preserve supported vector geometry and native/outlined text. Use the
  existing conservative output policy for alpha groups and patterned paints.
  Native text/annotation loss is rejected rather than silently flattened.
- Add explicit isolated raster DC groups for `copy`/`erase`, and URL/named
  destination helpers that use the actual document annotation scope.
- Add 34 pure capture/lifetime cases, 22 native cases, 24 real document
  fixtures and strict structure/text/link/pixel inspection. A selected Linux
  workflow requires both Poppler and librsvg on Racket 8.18 and 9.3.
- Keep native pins, CPU/GPU canvas lifetimes and GPU staging reuse unchanged.
  Skip only an identity shader-map wrapper, avoiding needless SVG fallback.

## 0.62.0 — Per-presenter GPU staging reuse

- Retain at most one compatible staging-surface wrapper per presenter/context.
  Physical resize replaces it; rotating drawable identities and logical-only
  scale changes do not. Fresh DC state and full root clearing remain mandatory.
- Preserve the transactional GPU snapshot/copy and explicit readback semantics.
  Failed or escaped DC scopes discard staging. No new normal-frame GPU wait.
- Retire cache contents before adapter/context teardown, including the existing
  deferred/finalizer/custodian path. Expired frames drop their cache reference.
- Report detached constructor/reuse/retirement counts in presenter diagnostics.
  A private fresh-allocation reference supports comparative acceptance, not a
  public renderer switch or claim about driver allocations or frame latency.
- Add 32 pure cache cases and 14 selected native cases, including 32-frame
  constructor counts, real consumer pixel comparisons, resize and failure
  recovery. Require the prior 0.60/0.61 gates and ordinary GUI reuse ledgers.
- Extend the existing render-canvas workflow and source checks. Fix the 0.61
  Windows source test's path-separator assumption. Native pins and public
  canvas/DC APIs remain unchanged.

## 0.61.0 — Unified callback-oriented render canvases

- Add `skia/render-canvas` with `make-skia-render-canvas`, a common interface,
  renderer predicate and `skia-render-window%`. The factory returns a real
  `canvas%` subclass; the existing concrete raster and GPU classes are unchanged.
- Select raster or platform GPU explicitly, with reported `auto` selection and
  no runtime GPU-to-raster fallback. Load only the selected concrete class.
- Make `get-dc` callback-only in the common API, with explicit `get-raster-dc`
  access for persistent raster state. Preserve actual raster/GPU DC lifetimes.
- Share owner-thread, callback replacement, one-shot repaint, reentry, error and
  close contracts. Guard the toolkit's pre-callback raster DC handoff.
- Add 33 headless cases and 20 selected real-window cases per renderer. Validate
  raster, GPU and automatic selection with 72 backing captures, separate normal
  frame I/O ledgers and the existing 0.60 pict/plot/style/geometry pixel oracles.
- Require the prior raster GUI and GPU consumer gates before the expanded GUI
  acceptance. Add a separate Linux 8.18/9.3 and Windows WARP workflow; keep the
  existing required-CI aggregate and native ABI/library pins unchanged.

## 0.60.0 — GPU DC real-consumer acceptance

- Exercise actual pict, plot/no-gui, style and geometry workloads directly,
  through recorded procedures, and through serialized/read-back recorded datums.
- Add 144 CPU/GPU-surface/final-frame captures across ordinary, HiDPI,
  asymmetric and fractional extents, with independent semantic pixel probes.
- Bound same-path procedure/datum and GPU surface/final-frame differences;
  do not require universal CPU/GPU byte identity or font-metric parity.
- Verify retained DC expiration, state restoration and explicit capture I/O.
  Add 48 real-window/CPU captures at two sizes, with separate complete normal
  no-readback presentation frames and explicit inspection frames.
- Add a strict run-tagged inspector, review images, regression tests and an
  interactive consumer example. The new validator retains the selected 0.59 gate.
- Extend Linux Mesa/Xvfb CI and add native D3D12 WARP consumer validation.
  Preserve existing required CI aggregation, native pins and public ownership.
- See [GPU DC consumer acceptance](docs/GPU-DC-CONSUMERS.md) for the exact
  assertions, limitations and validation commands.

## 0.59.0 — Frame-scoped GPU DC and canvas facade

- Add `skia/gpu-dc`: callback-scoped `dc<%>` drawing over an owned frame GPU
  target or a borrowed same-context GPU surface. Every DC expires on every exit.
- Add `skia/gpu-canvas`: DC-oriented widgets using the existing OpenGL, Metal
  and Direct3D presenters, with no implicit CPU-frame rendering/readback.
- Share native DC drawing callbacks while using GPU snapshots for overlap copy
  and isolated alpha merges. Public output methods explicitly detach CPU pixels.
- Preserve logical coordinates and independently scale renderer-bound commands
  from actual physical/logical X/Y extents. Raster DC semantics are unchanged.
- Resolve OpenGL host initialization through the toolkit superclass DC rather
  than a frame-scoped subclass's virtual `get-dc`.
- Add 33 pure, 15 native offscreen/presenter and 10 required-when-selected GUI
  cases, a strict validator, an example, a contract and a separate Linux Mesa
  workflow for Racket 8.18/9.3. Native and GUI execution must be validated on the
  selected host; this release does not imply hardware or screen certification.

## 0.58.0 — Persistent raster GUI canvas

- Added explicit `skia/canvas` with `skia-canvas%` and `skia-canvas?`. The
  canvas owns one persistent CPU Skia DC, supports ordinary paint callbacks,
  exposure, coalesced refresh, synchronous refresh-now and explicit present.
- Preserved DC identity, selected drawing objects and transforms when resize
  or monitor backing scale replaces its transparent raster backing. Empty
  client extents defer allocation/painting; old pixels are not preserved.
- Added direct premultiplied RGBA-to-ARGB transfer into a reusable toolkit
  bitmap and byte buffer. The toolkit blits completed Skia pixels; repainting
  does not encode PNGs or route drawing through a Cairo renderer.
- Added owner-eventspace-thread, re-entry and explicit close boundaries.
  Unfinished alpha groups are discarded at paint entry/exit, including error
  paths. Synchronous errors propagate; hiding a canvas does not release it.
- Corrected Linux HarfBuzz loading after GTK/Pango initialization with local,
  deeply bound symbol resolution. This also fixes existing standalone Skia DC
  text in GUI processes. Restart Racket/DrRacket after upgrading to apply the
  loader policy to a fresh process; the pinned library versions are unchanged.
- Added headless lifecycle/transfer suites to run-tests.rkt and a separate
  actual-GUI validator. Required Linux Xvfb CI validates an independently
  installed source package and retains its reports; CPU/EGL lanes stay headless.
- Retained the existing 0.57 DC contract, its validator/oracles, Racket 8.18 /
  draw-lib 1.22, all GPU workloads and both native package pins. No new
  Skia/HarfBuzz symbols or layouts. The next stage is the 0.59 GPU-backed
  canvas/DC facade.
- Baseline: 6c7ad1ff8c6b108abce4fd6e35cc1152ff726bd6. Its 0.57 CI run
  37146060599 completed successfully; the new 0.58 GitHub Actions run and
  physical-display review remain separate acceptance gates.

## 0.57.0 — Styles and drawing-context compatibility

- Added public gradient/stipple shader sources, six repeating hatches, legacy
  aliases and native dash phases, with per-call mutable-source snapshots.
- Added affine alignment, native path/fill/stroke bounds, and a query-only Cairo
  bridge for upstream associated-region utilities. No Cairo output fallback.
- Added 24 pure/40 native cases and 45 standalone style-math checks; four new
  style captures are independently inspected inside the existing DC gate.
- Preserved all 0.56 consumers, old exact oracles, replay/alpha lifetime rules,
  native pins and GPU workloads. Native symbol inventory gains only the m119
  sk_paint_get_fill_path binding; no new layout or public native handle API.
- Incremental candidate for the locally applied 0.56 patch. Actual host and CI
  acceptance remain required. GUI stages remain 0.58 and 0.59.

## 0.56.0 — Real consumers on the existing DC subset

- Added direct public pict/plot/no-gui fixtures with text, geometry, bitmap,
  nested group opacity, a labeled function, point markers, axes and legend.
- Added 16 native cases covering direct consumers, both upstream replay forms,
  state/clip preservation, HiDPI and snapshots encoded after DC close.
- Required eight new consumer captures through the existing installed-package
  DC gate. Every capture has semantic probes; same-recording procedure/datum
  images have a two-channel-unit bound. Direct/reference differences are
  retained for review rather than represented as universal pixel identity.
- Added explicit pict-lib/plot-lib dependencies without importing them from
  skia/dc. Kept Racket 8.18 / draw-lib 1.22 and the production renderer unchanged.
- Retained all 0.55 suites/oracles, GPU demos, native pins and GPU workloads.
- Split the remaining roadmap into 0.57 styles/completeness, 0.58 raster canvas
  and 0.59 GPU-backed canvas. Deferred features remain explicit rejections.
- Source baseline: f1568cf68e57b0358ac27e4c5eeb1e0e33e6de8a. Host and complete CI
  execution are acceptance gates, not claims made by synthetic inspector tests.

## 0.55.0 — Recorded drawing and raster alpha groups

- Added direct upstream recorded-procedure and recorded-datum replay using the
  exact private pen/brush member identities in a dedicated adapter. Successful
  replay restores destination state; upstream exception rollback is not promised.
- Replaced immutable pen/brush copies with selected-object identity and locking,
  atomic validation/selection, shared-selection counts, and release on close.
- Added nested isolated CPU raster groups, saved/per-draw/group opacity semantics,
  target-local clipping and identity-coordinate merge without CPU pixel staging.
- Bounded root plus live layer storage; allocation failure preserves state,
  failed merges release/pop once, and close discards unfinished layers.
- Added 28 pure and 28 native replay/alpha cases and 24 standalone production
  controller cases. Kept all existing DC counts and exact pixel oracles.
- Added independently checked direct/procedure/datum alpha captures with a fixed
  two-channel-unit quantization tolerance; no pairwise-only pass or universal
  raster identity claim. Required installed-package DC CI uses the expanded gate.
- Preserved Racket 8.18 / draw-lib 1.22, native pins and all GPU jobs/workloads.
- Preserved the two GPU demos at f4dedd03d0f8d0fdb79fcb9f5706b218a78183c5 and
  repaired their missing source-manifest inventory entries on that exact baseline.
- Split the remaining roadmap: 0.56 consumers/styles, 0.57 raster skia-canvas%,
  0.58 GPU facade. This delivery does not implement those later stages.
- Host and full CI execution remain acceptance requirements.

## 0.54.0 — DC text, bitmaps and clipping regions

- Added Skia/HarfBuzz text drawing, shared extents, glyph queries, underline,
  font feature settings and separate character/grapheme/combined modes.
- Added public bitmap pixel input, explicit masks, physical backing resolution,
  cropped/scaled sections and immutable native snapshot copying for overlap.
- Added real region% clipping with path intersections/fill rules, construction
  versus installation transforms, and selected-region locking. Private Racket
  region dependencies are isolated in one checked adapter, not a Cairo renderer.
- Raised the minimum to Racket 8.18 and draw-lib 1.22: 8.17 has required alpha
  methods but lacks the defaults used by the current override declarations.
  Alpha-group rendering remains unsupported until the later compatibility stage.
- Retained 60 pure/31 native foundation cases and added 36 pure/34 native cases.
  The installed-package validator now checks two independent exact oracles;
  large geometry and colored text samples remain explicitly limited evidence.
- Retained all Ganesh behavior, native pins, required jobs and GPU workloads.
- Based on ad31074e2b3a9727a4e830290d0bf2efda031292. Host and full CI acceptance
  are required; no earlier minimum-version failure is waived by this release.

## 0.53.0 — Persistent CPU drawing-context foundation

- Added the opt-in `skia/dc` class implementing public `dc<%>` without inheriting
  Cairo drawing machinery. The native target is private, owned CPU Skia storage.
- Added owner-thread lifetime, independent post-close snapshots, RGBA/PNG output,
  logical/backing geometry, affine state, color/opacity, immutable pen/brush
  snapshots, ordinary primitives, and same-DC rectangle clipping restoration.
- Supported positive-axis alignment and general affine smoothed drawing;
  explicitly rejected deferred text/bitmap/region/style/alpha operations.
- Added 60 pure production-class tests and 31 native tests, including constrained
  bitmap-dc comparisons and a recorded-geometry smoke test. Full compatibility
  and universal pixel identity are not claimed by interface membership.
- Added an independent exact pixel oracle and side-by-side review PNGs, with
  required installed-package gates in existing CPU/minimum-Racket CI lanes.
- Raised the minimum supported Racket release from 8.7 to 8.17. Racket 8.17 is
  the first release whose `dc<%>` includes `start-alpha` and `end-alpha`; the
  required minimum-Racket CI lane now tests 8.17.
- Kept Ganesh APIs, native pins, GPU workloads and all required jobs unchanged.
- Based on accepted 0.52 commit bff9c172b84ecb353a5134ce42abd8d49256815a;
  0.53 is a host/CI validation candidate, not an already accepted baseline.

## 0.52.0 — Metal interop and Ganesh closeout

- Added lazy, explicitly unsafe same-device Metal texture construction and
  device-only access, using the existing generic single-use interop API.
- Added owned GPU image copies and scoped external-target canvases with exact
  context affinity, bounded producer/queue-tail completion and quarantine.
- Added native texture/usage/storage/alias/swizzle checks; separated declared
  producer coverage from verified command completion. No CPU staging or runtime
  helper dylib is introduced, and borrowed images cannot enter retained graphs.
- Consolidated the completion/retirement boundary shared with Direct3D;
  preserved its behavior and cleaned up SDK fixture enum-conversion warnings.
- Added 49 pure and 33 native Racket cases, independent Apple SDK texture
  production/consumption, 144 handoffs, 12 retained PNGs and an isolated timeout.
- Added Apple SDK compilation/ABI checks inside the existing macOS CPU CI lanes;
  actual Metal execution remains an explicit required local acceptance gate.
- Recorded Ganesh closeout boundaries and the agreed 0.53–0.57 skia-dc% /
  skia-canvas% roadmap. Vulkan, Graphite and native ABI migration are deferred.
- Source baseline: d6af412ba0fdf1b6ebbfb0bb5c9514cc4d6f5d5a. Its remaining
  pbuffer dependency-install stall is not waived or converted into a test pass.

## 0.51.0 — Direct3D external-resource handoffs

- Added safe generic single-handoff/copy/scoped-canvas operations and an
  explicitly unsafe Windows resource/device bridge. Existing GL APIs remain.
- Added native resource/heap queries, canonical device identity checks,
  retained COM references, mandatory producer fences and bounded completion.
- Isolated external image copies through a private D3D texture before producing
  a Skia-owned GPU image. Scoped target return uses a shader-filled normalization
  pass; no runtime state query, zero-copy, hardware or screen claim is made.
- Added owner/context/lease/re-entry guards, unused-descriptor retirement and
  process-lifetime quarantine for indeterminate native completion/release.
- Added independent SDK producer/consumer validation, 29 native cases, six
  stress contexts, 144 handoffs, 12 post-teardown PNG captures, and a separate
  expected-timeout child. No abort/Crash Reporter test is used for this stage.
- Added a required installed-package interop step after existing D3D12/parity
  checks; retained CPU, EGL, DXGI, native ABI and source gates unchanged.
- Source baseline is ae29c9ffa3556ec18a068f80d17f673a8cadb093. Its completed
  0.50 lanes passed, but the aggregate was pending at implementation start.
  This stage adds no exception for that pending dependency-install lane.
- Local authoring tests are not Racket/Windows execution. Accept only after
  host regressions and the new required Windows runtime checks are reviewed.

## 0.50.0 — GPU backend parity and consolidation

- Added a shared source-only backend/native-ID registry and immutable public
  wrapper capability queries. No declaration claims runtime or hardware probing.
- Enabled Direct3D in the existing bounded document executor and transfer audit;
  retained capture-once, explicit readback and CPU-owned document retention.
- Made GPU surface backend/generation/geometry metadata authoritative after
  actual native recording-context validation; added production-boundary tests.
- Extended common scene/image/document/performance hosts and inspectors to
  explicit hardware/WARP selection. Reused existing tests and pixel tolerances.
- Extended common redraw measurements to DXGI, accounting for the context pin,
  backend fence waits and occlusion callbacks without counting skipped presents.
- Added required shared parity hooks after the existing WARP/DXGI CI checks,
  with isolated installed sources, full workloads and failure artifacts.
- Kept native pins, CPU defaults, GUI auto selection, existing ABI checks and
  required matrix unchanged. No new backend or external D3D interop is added.
- Starts at maintainer-accepted 0.49 da0444bb28a9e8a50c26eb8b2df8049c94a1e9da;
  that acceptance explicitly excepted an external Linux Racket download failure.
  New 0.50 execution/acceptance must be established by its own host/CI results.

## 0.49.0 — DXGI / D3D12 window presentation

- Added an explicit Windows x64 Direct3D presenter to the existing GPU GUI and
  frame API. Hardware/WARP selection and sync interval are explicit; `auto`
  and OpenGL/Metal behavior remain unchanged.
- Added two-buffer flip-discard swap chains, exact-queue submission, explicit
  PRESENT transitions, per-buffer allocator/fence reuse, bounded waits, resize
  retirement, owner-thread cleanup and failure quarantine. Public frames expose
  only a borrowed draw-only canvas, never a closeable/native back buffer.
- Counted DXGI occlusion as a skip rather than a successful present. Added
  cancellation cleanup for exceptions, unbalanced layers, resize and close.
- Added 34 pure Racket cases and a required installed-package Windows DXGI/WARP
  lane with SDK layout/GUID/vtable checks, all 28 shared presenter native cases,
  six contexts/windows, 1,080 normal stress frames and 18 actual back-buffer
  captures checked against an independent asymmetric pixel oracle.
- Kept the existing offscreen WARP, CPU, EGL, ABI-candidate and SIGKILL fixture
  checks. No native dependency migration, screen certification, hardware
  performance claim, external D3D resource borrowing, HDR or fullscreen mode.
- Host C mirrors and synthetic Python tests are not Windows/Racket execution;
  accept this stage only after the new required DXGI lane actually passes.

## 0.48.0 — Direct3D 12 offscreen and required Windows WARP CI

- Added explicit Windows x64 D3D12 hardware/WARP selection with owned COM
  adapter, device and direct queue, staged cleanup, device-loss checks and
  completion before ordinary teardown. No fallback or implicit GUI is added.
- Added the pinned m119 by-value Ganesh context binding; retained the checked
  shared library handle and the 3.119.1 native pin. CPU imports remain lazy.
- Reused ordinary GPU surfaces/images/transfers/affinity and cache controls.
  Added 32 pure source cases and a dedicated live validator reusing all 95
  existing surface/image/cache cases, six contexts and 540 retained frames.
- Added Windows SDK GUID/vtable/layout checks, a Racket by-value C call fixture,
  independent PNG/transfer/lifecycle inspection and required installed-package
  WARP CI. Existing CPU/EGL lanes and native-candidate rejection remain intact.
- DXGI presentation, external D3D resources, GPU document executors, Graphite
  and hardware/performance certification are not part of this release.
- Authoring C/Python tests are not Windows/Racket/GPU acceptance. The new
  required WARP lane must pass before this stage becomes an accepted baseline.

## 0.47.0 — native ABI policy and isolated candidate investigation

- Centralized the default Skia package pin and m119 ABI policy. One lazy loader
  now supplies the exact checked library handle to CPU and optional GPU groups.
- Added typed unsupported-ABI rejection, 26 Racket layout-size checks, and
  explicit identity/symbol diagnostics that do not certify GPU availability.
- Added a pinned 4.153.1 NuGet investigation with bounded fixed-member extraction,
  subprocess isolation, actual export inventory, reviewed Graphite build-flag
  queries and a required real-Racket negative loading test on Linux CI.
- Documented the same-name path/path-builder semantic incompatibility and a
  migration checklist. The default remains 3.119.1; no m153 renderer is enabled.
- Added 30 pure and 10 live Racket source cases plus Python/C-fixture regressions;
  retained existing installed-package, CPU, EGL and full GPU stress requirements.
- Investigated Graphite's C API, recorder/recording ownership and async readback
  boundary without implementing Graphite or Direct3D in this release.
- Authoring fixture checks are not a new real-Skia/Racket/CI pass. See the
  delivery validation record and NATIVE-ABI.md for the remaining host gates.

## 0.46.0 — GitHub Actions CI and portability matrix

- Added required source, clean installed-package CPU, and Mesa EGL lanes with
  explicit Racket/OS/architecture identities and an aggregate required check.
- Added source-only deterministic packaging, isolated collection resolution,
  native-free import/pure checks, fresh native installs, package dependency
  checking, and portable CMake/CTest ABI mirror execution, including MSVC.
- Added required surfaceless/pbuffer EGL runs with no display environment,
  software-renderer verification, retained failure artifacts and command logs.
- Added read-only manifest verification for Git and installed source copies,
  LF checkout rules, CI regression tests and a current evidence matrix.
- Preserved local full GPU validation and all default stress sizes. No native
  dependency migration, hosted hardware-performance claim or implicit GPU skip.

## 0.45.0 — measurements, cache management and release stress

- Added lazy per-context cache queries, budgets, unlocked/byte/age purges and
  explicit cleanup, preserving owner/domain checks and live resource ownership.
- Added raw monotonic host timing for recording, first/warm replay, completion,
  SkSL construction, fresh-image uploads, readback and presenter calls.
- Added sustained retained graphs, finalizer/GC and cache-pressure checkpoints,
  recreated contexts, coalesced redraws, resize and independent-window closure.
- Added 30 cache pure, 16 timing pure and 20 cache native source cases/backend;
  strict timing/trace/PNG/resource inspectors and independent runner tests.
- Reports distinguish budgeted cache from total memory, host latency from GPU
  timestamps/display latency, and measured data from unexecuted authoring gates.
- Preserved earlier validators, last-step source sums and deferred Linux CI gate.

## 0.44.0 — GPU-assisted bounded document fallbacks

- Added optional borrowed and lazily owned GPU raster executors. CPU defaults
  and the existing native/raster/reject policy are unchanged.
- Added explicit GPU replay/readback and CPU-image embedding at identical
  padded, ceil-rounded raster dimensions, with scoped resource cleanup.
- Preserved strict text/link/unknown-provenance restrictions and exact-recorder
  nested executor inheritance; unrelated canvases cannot inherit a context.
- Added execution/transfer reports and exact-target raster audit scopes without
  changing GPU lifetime/affinity checks or public drawing operations.
- Added 35 pure and 42 live source cases per backend, 16 PDF/SVG documents per
  backend, actual vector/image/link/placement inspection and SVG PNG comparison.
- Extended selected-Racket desktop/headless runners; source sums update last.
  Linux EGL acceptance stays deferred to future CI by the maintainer.

## 0.43.0 — EGL headless contexts and explicit external GL boundaries

- Added lazy Linux desktop-GL EGL construction with explicit platform/device
  and surfaceless/pbuffer choices; no hidden GUI, GLX or fallback selection.
- Added owned-display initialization accounting, API/current-binding restoration,
  serialized activations, owner-side teardown and a borrowed-current EGL provider.
- Added scoped, queried RGBA8/stencil8 framebuffer borrowing; external GL handoff;
  and GPU-side texture copies that do not expose borrowed images to retained graphs.
- Preserved external ownership, explicit origins, bounded binding restoration,
  safe default completion at external-return boundaries and opt-in ordered reuse.
- Added 37 pure, 10 EGL-native and 32 GL-interop source cases. A separate Linux
  no-display runner reuses all 33 surface and 42 image cases and ten workflows.
- Added raw-report/PNG headless/interop inspection, runner regression tests,
  examples and ownership/validation guides. Racket/Ganesh host acceptance remains
  separate from authoring source checks and native ctypes EGL/GL probes.
- Preserved the accepted GL/Metal presenters and final source-sum sequencing.

## 0.42.0 — unified window presentation

- Added explicitly imported GPU GUI widgets and shared presenter/frame APIs,
  frame/canvas expiration, actual pixel/logical sizes and target generations.
- Added coalesced redraw scheduling, bounded geometry/scale monitoring,
  hidden/zero/minimized skips, callback-time resize/close cancellation and
  owner/eventspace-safe deferred cleanup for independent windows.
- Reused actual GL host-framebuffer wrapping; added CAMetalLayer drawable
  wrapping and presentation on the same Ganesh command queue after submission.
  Normal frames do not request a CPU wait or readback. Aborted Metal frames
  complete pending work before returning a drawable; uncertain cleanup is
  quarantined rather than retried. Offscreen reference contracts are unchanged.
- Added 53 pure and 28 live presenter source cases per backend, two-window
  diagnostics, strict submission/lifetime inspection, SDK geometry mirrors,
  examples and reference/validation guides. Host execution remains required.
- Kept physical display inspection separate from automated submission evidence,
  all preceding CPU/GPU parity gates and final source-sum sequencing intact.

## 0.41.0 — offscreen Metal parity

- Added explicit owned Metal context construction without an OpenGL/GUI host,
  retaining the same surface, image, drawing and transfer interfaces.
- Reused the pinned device/queue reference contract, with failure cleanup and
  short native-call autorelease scopes captured by deferred destruction jobs.
- Made native target/backend checks and shared surface/image suites select the
  actual backend rather than assume OpenGL.
- Added 34 pure, 8 Metal-specific and 9 cross-backend source cases, three
  Metal rendering/teardown smoke cycles, and ten GL/Metal visual comparisons.
- Added raw-diagnostic/PNG parity inspection, run identity, required/optional
  orchestration checks, headless examples and API/validation documentation.
- Added patch-hunk count/context and ordinary Git application regression tests.
- Preserved CPU defaults, explicit transfers, retained affinity, GL window
  behavior and final source-sum sequencing. Metal presentation, external
  interop and performance conclusions remain outside this release.

## 0.40.0 — GPU images and transitive context affinity

- Added explicit texture uploads, GPU surface snapshots/subsets, ownership
  residency/context queries, texture validity diagnostics, and CPU detachment.
- Added retained graph affinity through shaders, filter graphs, runtime children,
  paint slots/copies/getters, recorders, nested pictures and picture shaders.
  Native reference ownership survives original-wrapper mutation/closure.
- Added owner-side queued destruction and public-context keepalive for retained
  parents. Clearing the last native GPU paint slot restores CPU independence;
  successful picture finish transfers affinity from the emptied recorder.
- Reject cross-context use, implicit CPU/PDF/SVG rendering, CPU image conversion
  and encoding, and GPU-dependent SKP serialization. Explicit image readback
  stages through a same-context GPU surface; no zero-copy promise is made.
- Added 33 pure + 42 live source cases, two retained-graph comparison workflows,
  a post-teardown detached image, PNG/ledger inspection and validator regressions.
- Preserved the 0.39 window-import and nested-activation fixes, CPU constructors,
  separate lazy GPU symbols and all preceding selected validation steps.
  Authoring checks do not establish a new Racket/native GPU pass.

## 0.39.0 — offscreen OpenGL surfaces and explicit transfers

- Added GPU-backed `surface?` values and ordinary `canvas?` drawing with
  activation-bound leases, creator/domain checks and deferred native release.
- Added explicit flush/submit/wait and synchronous RGBA, detached CPU-image and
  direct strided raster-buffer readback. CPU snapshot/encoding entry points
  reject GPU targets; no public GPU images are produced in this revision.
- Added surface/execution backend queries without changing CPU constructors,
  document representation policies or CPU-only import behavior.
- Added a diagnostic host-framebuffer renderer with actual pixel dimensions,
  format/origin/stencil/sample queries, GPU-only blit, asynchronous submission
  and swapping. The automatic report does not certify visible window pixels.
- Added 35 pure and 33 live-GPU source cases, eight direct CPU/GPU scene pairs,
  full PNG pixel inspection, explicit comparison bounds and transfer traces.
- Extended the selected-Racket validator; inspector reports publish on success
  and source sums update last. The 0.38 GC-test correction is preserved.
- This authoring delivery did not execute Racket or native GPU rendering.
  Hardware/platform support and performance remain established only by host runs.

## 0.38.0 — GPU foundation and explicit backend probes

- Added optional backend-neutral context/provider/domain APIs with serialized
  owner scopes, native identity checks, unique generations and deferred releases.
- Added GC/custodian shutdown requests with owner-side draining, explicit
  abandonment, live-child close guards and quarantined indeterminate releases.
- Added a Racket GL adapter, separate lazy GPU symbol group, and a private
  Ganesh target/draw/submit/readback probe with exact RGBA and context checks.
- Added early Metal device/queue/Ganesh construction and teardown diagnostics;
  audited the actual pinned retain behavior instead of relying on the legacy
  transfer comment. No Metal rendering or presentation claim is made.
- Added Windows x64 native selection, pinned archive/PE validation and explicit
  installer/validator PowerShell entry points, without changing CPU constructors.
- Added 64 pure source test cases, protected-flag-aware GPU ABI mirrors,
  diagnostic/PNG inspection, synthetic Python tests, docs and a selected-Racket
  runner that regenerates source sums only after selected validation succeeds.
- No public GPU surface/image API yet. Authoring checks did not execute Racket,
  live Skia/GL/Metal, Windows installation, or full-checkout native validation.

## 0.37.0 — owned raster buffers

- Added native-owned strided RGBA storage, exclusive pixmap/direct-canvas scopes
  and copied immutable image snapshots.

## 0.36.0 — CPU color filters

- Added HSLA, gamma, lookup-table, luma, contrast, lerp and lighting factories,
  including the explicit all-omitted ARGB identity-filter fix.

## 0.35.0 — portable drawing

- Added marker geometry, inspectable grid plans and cropped nine/lattice/atlas
  placements that lower before recording and avoid whole-panel fallback.

## 0.34.0 — bounded output groups

- Added capture-once backend-aware native/raster decisions with retained nested
  reports and explicit rejection of unknown or discarded semantics.

## 0.33.0 — persistent pictures and picture shaders

- Added copied native SKP bytes, explicitly trusted file/byte loading, and atomic
  file publication. Cheap bounded header checks do not validate native payloads.
- Added native cull-bound snapshots, process-local IDs, approximate operation
  counts (optionally nested), and native byte estimates. Loaders accept nominal extents.
- Added optional `#:spatial-index 'rtree` to both recording entry points. The
  temporary factory is released after synchronous creation of the hierarchy.
- Added retained picture shaders with tile modes, filtering, tile rectangles,
  and the existing affine local-matrix API.
- Preserved opaque-import provenance, including through shaders and recordings;
  rasterization does not certify unknown semantics. Sampled links are discarded.
- Added 31 pure and 40 native tests, doctor, combined document/reference probes,
  metadata and audit checks, and a fresh-process raw-pixel replay comparison.
- Native requirements are 377 Skia / 27 HarfBuzz symbols; no new layouts.

## 0.32.0 — perspective and general canvas matrices

- Added separate immutable row-major 3x3 and 4x4 matrix values, checked native
  float coefficients, composition, transpose, inversion, and explicit conversions.
- Added homogeneous mapping, projected points, and rectangle bounds that return
  false when W reaches or crosses zero rather than returning misleading bounds.
- Added retained-depth translation/scale/rotation and an explicit camera-distance
  projection convention; the six-coefficient affine API remains unchanged.
- Added full canvas matrix readback, replacement, concatenation, and scoped
  matrix application with protected restoration and multiple-value results.
- Reused the existing column-major SkM44 callouts; no symbols or layouts added.
- Audited general matrix operations and retained their provenance in pictures.
  Strict PDF/SVG output requires explicit raster groups around those transforms.
- Added 59 pure and 36 native cases, a doctor, an eighth C mirror, and one combined
  PDF/SVG/reference/audit/matrix-trace registry with a structural inspector.
- Preserved the 0.31 region-seam fix from the current repository baseline.
- Authoring validation did not execute Racket or native Skia.

## 0.31.0 — structured geometry and advanced image drawing

- Added owned integer regions, nonmutating Boolean operations, path conversion,
  copied rectangle sequences, drawing, and explicit device-coordinate clipping.
- Added immutable native triangle meshes with copied positions, texture
  coordinates, colors, optional uint16 indices, and detached inspection data.
- Added nine-patch/lattice images, anchored atlas sprites, and cubic Coons patches.
  Lattice cell-kind storage matches the C++ uint8 ABI despite the C enum pointer.
- Extended output policies and recording provenance; fixed PDF point-sprite
  explanatory text that had described SVG instead.
- Reused existing rounded-rectangle values; no competing native public type.
- Added 38 pure and 42 native tests, a doctor probe, a seventh C layout mirror,
  and a combined PDF/SVG/reference/audit registry with a structural inspector.
- This authoring run did not execute Racket or native Skia tests.


## 0.30.0 — canvas primitives and scoped layers

- Added point sets, arcs, pure immutable four-corner rounded-rectangle
  specifications, rounded frames and clips, and clip-aware draw-color.
- Normalized rounded clips are rebuilt as ordinary paths so unequal corners
  survive SVG serialization and recorded-picture replay.
- Added detached local/device clip bounds, empty/rect predicates, and
  conservative quick rejection; no automatic culling is installed.
- Added native low-level and scoped save layers with paint snapshots, protected
  save-stack floors, multiple-value preservation, and exception cleanup.
- Documented the pinned m119 content-bounds restriction rather than promising
  that native layer bounds are merely an ignorable allocation hint.
- Device-clip color fills reset/restore the local matrix to avoid SVG's transformed
  drawPaint rectangle. Unbounded recorded color fills are conservatively audited.
- Extended output auditing and recorded-picture provenance for points and layers;
  corrected PDF native-text explanations that previously described SVG behavior.
- Added a picture-recorder finish guard for protected state/layer scopes.
- Added 28 pure and 40 native cases, doctor, a combined three-page registry,
  SVG/report/query inspector, and single-interpreter host validation.
- Adds 17 Skia symbols (336 total); no new structs. HarfBuzz remains 27.

## 0.29.0 — output capability and fallback auditing

- Added pure, conservative PDF/SVG/raster capability queries and immutable
  operation reports, named scopes, and JSON conversion.
- Added dynamic preflight and single-execution audited byte/file exporters with
  report, error, and vector-only publication policies.
- Resource provenance follows paint attachments/copies/getters, shader/filter
  children, path fill types, and recorded pictures, including recorder reuse.
- Explicit raster groups record padded bounds and actual pixel dimensions;
  known rendering features are resolved inside the group while lost document
  annotations remain a blocking semantic-loss event.
- Added 30 pure and 28 native tests, doctor, a three-page probe/report registry,
  structural inspector, and single-interpreter validation script.
- No new native symbols/layouts. Existing ICC/PNG fixes and annotations remain.

## 0.28.0 — runtime effects / SkSL

- Added owned compiled runtime effects and ordinary shader, color-filter, and
  blender instances with immutable uniform/child snapshots.
- Copied reflection exposes names, types, counts, offsets, precision/color flags,
  and child kinds without retaining borrowed C++ string views.
- Added checked, tightly packed float/int/vector/matrix/array uniforms, structured
  compilation errors, affine shader local matrices, and typed child binding.
- Added preset blender objects, paint setter/getter integration, and common
  lifetime/thread validation for runtime-effect and blender resources.
- Added 38 pure and 39 native cases, a doctor, reflection ABI mirror, and one
  twelve-panel PDF/SVG/reference runner with explicit bounded raster fallback.
- Adds 18 Skia symbols (319 total); HarfBuzz remains 27. Expected suite: 670 cases.
  Native/Racket execution is not claimed by the authoring checks.

## 0.27.0 — PDF/SVG links and document annotations

- Added canvas URL rectangles, named destinations, internal links, backend
  queries, and deterministic PDF/SVG destination-ID helpers.
- PDF references resolve across pages. SVG references resolve to predefined
  views; duplicate or missing names cannot silently enter completed exports.
- Native URL annotations retain copied data through picture recording/replay.
  Named annotations on recorders reject; raster annotations are validated no-ops.
- SVG finalization relocates native annotation rectangles to a root overlay to
  avoid stale graphics clips, preserves URI text, and emits href plus xlink:href.
- Added 25 pure and 27 native cases, doctor, a single three-page PDF/SVG registry,
  interactive object-based review HTML, and a structural inspector.
- Three additional native symbols (301 total); no new structs or encoder changes.

## 0.26.0 — color-managed encoded and document output

- Added immutable SDR transfer values, named transfer/gamut queries, custom RGB
  construction, chromaticity-to-XYZ-D50 conversion, and detached inspection.
- Added explicit image sample conversion. Untagged input requires a source
  declaration; tagged input cannot have its source silently overridden.
- Extended PNG/JPEG/WebP and surface PNG encoders with destination conversion,
  matrix/TRC ICC overrides and descriptions. Native profile buffers remain live
  throughout encoding; metadata overrides alone never convert pixel samples.
- Exposed the existing Skia PDF/A metadata flag through low-level and shared
  PDF exports. It requests XMP/UUID/sRGB output intent, not certified conformance.
- Added a unified PDF/SVG/encoded-image color probe and semantic ICC inspector.
  The guide documents 8-bit SDR limitations, profile regeneration, and the
  pinned PDF image-color limitation requiring explicit sRGB normalization.
- Added 34 pure and 35 native tests (541 total), doctor coverage, color ABI
  mirror and a one-interpreter validation script compiling every test module.
- Based on 0.25 commit `7372d061ff2e1cf0c85c44a48d8ce5b994538027` after the
  maintainer reported its successful run. New native validation awaits the host.

## 0.25.0 — advanced filter graphs and crop semantics

- Added merge, blend/arithmetic, offset, morphology, displacement, convolution,
  affine image transforms, tile, magnifier, image/picture/shader source nodes,
  and six diffuse/specular lighting constructors: 21 new public constructors.
- Added #:crop to blur, both shadow constructors, color-filter image nodes, and
  composition, plus an explicit standalone output-crop node. Rectangles use xywh.
- Preserved dynamic-source semantics for #f; private identity nodes keep valid
  native Src/Dst and identity optimizations owned instead of treating them as
  allocation failures. Parent graphs and paints retain their inputs natively.
- Copied input arrays and kernels with byte limits, strict geometry/enum checks,
  and explicit convolution pixel-unit and crop/tile semantics. No claimed
  blanket SVG filter support: the new SVG probes rasterize panels explicitly.
- Added 30 pure + 44 native tests (472 total), doctor coverage, three C structure
  mirrors (8/8/12 bytes), ten Python inspector tests, and one 18-panel registry
  for native PDF, SVG raster groups, and independent native raster references.
- Added 20 native symbols: 285 Skia / 27 HarfBuzz. The single-interpreter
  validation script continues to compile all tests/*.rkt before running them.
- Based on cd046ac6eb92d7c0534b70900a341b1014cd6fbe. Authoring checks are not
  Racket compilation or native execution; see docs/FILTER-TESTING.md.

## 0.24.0 — path inspection and affine matrices

- Added immutable six-coefficient affine matrix values, composition/inversion,
  point/vector/bounds mapping, and canvas transform get/set/concat operations.
- Added eager detached raw/normal path snapshots, reusable sequences, conic
  weights, generated closing-line flags, contour groups and raw reconstruction.
- Added copied/in-place path transforms, path-measure placement matrices, and
  independently owned shader-local-matrix wrappers.
- Audited the distinct m119 matrix boundaries: 36-byte M33 for paths/shaders,
  64-byte column-major SkM44 storage for canvas functions. Added an independent
  native-translate/readback test, not just a self-consistent get/set round trip.
- Added 24 pure and 30 native tests: 398 total cases (136 pure, 6 lifetime,
  256 native). Adds 16 Skia symbols (265 total); HarfBuzz remains 27.
- Added one PDF/SVG/raster-reference probe runner and an eight-test structural
  inspector. Local shader examples explicitly rasterize only the shader panel.
- Validation now compiles all tests/*.rkt through the selected Racket's raco
  module, avoiding stale dynamically loaded test bytecode from another version.
- Starts from 36b4b44dae46e30bb07dcdb569a254c8fdd4d982. Source/context-patch,
  host-C and synthetic inspector checks are not Racket/native execution.

## 0.23.0 — vector-output refinement

- Added reusable output-page specifications and shared PDF/SVG byte/file exports,
  explicit physical units, margins, content clipping, and page backgrounds.
  PDF accepts multiple pages; SVG rejects extra pages instead of dropping them.
- Shared SVG exports now use physical pt root dimensions matching PDF media boxes;
  the low-level SVG interface retains its existing user-unit sizing.
- Added scoped native/outline text policy across simple, shaped, paragraph,
  mixed-run, and prebuilt-blob drawing. Auto export chooses native PDF / outlined
  SVG. Already-recorded native pictures are intentionally not rewritten.
- Added independent text-blob outline conversion using private font snapshots
  and copied glyph/position metadata, including source-mutation/closure tests.
- Extended explicit raster groups with density inheritance, four-sided padding,
  and optional color-space tags, while preserving their local content origin.
- Added 20 pure and 29 native cases (344 expected total), doctor coverage, one
  PDF/SVG/raster visual registry, and a structural inspector with eight synthetic
  tests plus optional pypdf-backed size/text/font inspection.
- Adds no native bindings or layouts: 249 Skia and 27 HarfBuzz remain required.
  Based on `fa7d04e881df9f80a99e62e5f51aaa5ec30b02dc`. Authoring validation is
  source/context-patch and synthetic-parser validation, not a Racket/native run.

## 0.22.0 — SVG document output

- Added owned single-viewport SVG documents with borrowed canvases, explicit
  finish/abort, copied bytes/strings, and safe file publication. Canvas deletion
  completes the XML before stream detachment; closed canvas aliases stay invalid.
- Added fractional dimensions/viewBox, escaped UTF-8 title/description, and
  deterministic resource-ID canonicalization with a caller-selected prefix.
- Added backend-independent `shaped-run->path` and `draw-rasterized` helpers:
  explicit glyph geometry or local pixel groups, not hidden whole-page fallback.
- Documented the pinned C shim's missing SVG flags, native glyph/text mapping,
  unsupported shader/filter/clip/blend cases, and lack of font embedding.
- Added 16 pure and 27 native cases (295 expected total), a doctor probe, three
  SVG examples with raster references/browser comparison, and a standard-library
  Python structural inspector with six synthetic self-tests.
- Adds two Skia symbols (249 total), no HarfBuzz symbols (27 total), and no
  native struct layouts. Existing PDF, ICC/color, and codec code is retained.
- Based on pushed PDF commit `246f70cd80e26bc5d8da126e86ff7e520225a5f7` after
  the maintainer reported its tests passing. New Racket/native SVG execution
  awaits host validation; see `docs/SVG-TESTING.md` for the verification boundary.

## 0.21.0 — PDF document output

- Added owned PDF documents and per-page borrowed canvases using the existing
  drawing API. Ended page canvases stay invalid when later pages begin.
- Added explicit begin/end/finish/abort operations, copied PDF bytes, safe file
  publication, scoped page helpers, and multi-page convenience functions.
- Added UTF-8 metadata, optional explicit dates, raster-fallback DPI, and native
  lossless/JPEG image-quality policy. Page dimensions are fractional PDF points.
- Document/stream/data lifetimes are released in order; unfinished documents are
  aborted. Exceptions, breaks, and continuation escapes cannot publish partial
  file output. PDF does not introduce native-to-Racket callbacks.
- Added 12 pure and 21 native cases (252 total source cases), doctor coverage,
  a C ABI mirror, a three-page visual probe with raster reference PNGs, and an
  optional parser-based PDF inspector. Adds seven Skia symbols (247 total),
  no HarfBuzz symbols (27 total), and two C layouts (metadata/timestamp).
- Based on pushed 0.20 commit `ccabb4741edc227a1dbeba91a47adf5082d7417f`.
  The user's 0.20 native suite and visual probe are green. This stage has source
  and host-C checks only in the authoring environment; Racket/native/PDF visual
  validation is still required. See `docs/PDF-TESTING.md`.

## 0.20.0 — advanced codecs

- Added owned, thread-confined codecs with copied byte/file inputs, native
  metadata snapshots, owned color-space queries, frame counts, and repeat counts.
- Added eager, independently decoded full-canvas frames. Skia reconstructs
  dependencies and applies animation disposal/blending; no previous-output
  buffer is assumed. GIF and animated WebP have deterministic pixel fixtures.
- Added exact normalization for all eight encoded origins, with an explicit
  opt-out, display-dimension queries, and one-shot byte/file frame constructors.
- Exposed frame duration, required frame, completeness, alpha, disposal, blend,
  and encoded-coordinate frame rectangles. Preserved the legacy zero-count
  still-image metadata convention while exposing one selectable still frame.
- Added strict decode-result handling, 10 pure and 17 native test cases,
  doctor coverage, a host-C ABI mirror, and a self-contained visual example.
- Adds three Skia C-ABI symbols (240 total), no HarfBuzz symbols (27 total),
  and two complete native struct layouts. Expected suite: 219 source cases.
- Based on `257517a5c9f561b075c2fff23dd3ccad3be39d9a`; the corrected 0.19 ICC
  implementation and the previous image-decoding entry points are unchanged.
- Source/fixture/C-layout checks were performed. Racket compilation, the new
  native suite, native symbol audits, doctor, and visual rendering await the
  host run described in `docs/CODEC-TESTING.md`.

## 0.19.0 — color spaces and ICC color management

- Added owned `color-space?` wrappers with sRGB and linear-sRGB constructors, gamma queries, equality, and transfer-function conversion helpers.
- Added ICC profile import/export through byte strings, with native profile lifetime retained safely by ICC-created color spaces.
- `make-surface` and `rgba-bytes->image` now accept `#:color-space`; snapshots preserve the tag and `surface-color-space` / `image-color-space` expose owned references.
- `surface->rgba-bytes` and `image->rgba-bytes` accept a destination `#:color-space`, allowing Skia to perform CPU color conversion during readback.
- Added doctor/native coverage and `examples/color-spaces.rkt`. Encoded-output ICC injection and custom RGB transfer/matrix constructors remain future work.
- Adds 16 Skia C-ABI symbols and no HarfBuzz symbols or new native struct layouts.

## 0.18.0 — script-aware justification

- Extended `justify` / `justify-all` from U+0020-only expansion to automatic script-aware opportunities.
- Added CJK inter-character expansion for Han, Hiragana, Katakana, and Hangul, including compatible boundaries between separately shaped visual runs while excluding common punctuation.
- Added Unicode 15.1 Joining_Type data and Arabic kashida shaping: eligible cursive connections receive display-only U+0640 TATWEEL material, are reshaped by HarfBuzz, and preserve logical line/run text.
- Mixed lines distribute slack across inter-word, CJK, and Arabic opportunities; paragraph bidi resolution, fallback selection, break-provider indices, and Unicode conformance behavior remain unchanged.
- Added joining-data pure tests, CJK/Arabic/mixed native tests, doctor coverage, and `examples/script-justification.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.17.0 — external segmentation and hyphenation hooks

- Added public `layout-break-opportunity?` values and `make-layout-break-opportunity` for discretionary breaks with optional display-only suffix text such as `"-"`.
- Added `#:break-provider` to `layout-text` and `layout-mixed-text`. Providers receive each hard-break-delimited paragraph and normalized language hint and return supplemental string-index break boundaries.
- Provider boundaries supplement rather than replace Unicode 15.1 UAX #14 opportunities, allowing application-supplied Thai/Lao/Khmer dictionary segmentation or language-specific hyphenation without embedding a dictionary in the core package.
- Provider indices must be interior Racket default-grapheme boundaries. A suffix is shaped only when its boundary is selected; mixed layout preserves paragraph-wide UAX #9 resolution and gives the suffix the resolved level immediately preceding the break.
- Added pure/native tests, doctor coverage, and `examples/break-providers.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.16.0 — explicit Unicode bidi controls

- `layout-mixed-text` now interprets UAX #9 explicit embeddings, overrides, and isolates: `LRE/RLE/LRO/RLO/PDF/LRI/RLI/FSI/PDI`.
- Added the directional-status-stack rules, overflow handling through level 125, matching isolates, FSI direction selection, isolating run sequences, scoped bracket resolution, and line-specific L1 resets.
- Explicit formatting controls remain zero-width and are removed before HarfBuzz shaping; their resolved paragraph levels are retained across UAX #14 wrapping so a directional scope may span visual lines.
- Added pure resolver tests, native wrapped-scope/isolate tests, doctor coverage, and `examples/bidi-controls.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.15.0 — Unicode conformance hardening

- Added a pure-Racket conformance harness for Unicode 15.1 `LineBreakTest.txt` and `BidiCharacterTest.txt`, including the library's documented default-grapheme-cluster line-break tailoring.
- Added `tools/unicode-conformance.rkt` plus `tools/run-unicode-conformance.sh`, which can use an offline Unicode-data directory or fetch the pinned 15.1 test files from unicode.org.
- Added parser/smoke-vector regression tests and a reproducible source-checksum updater.
- The multi-megabyte Unicode test corpora are development inputs and are not vendored in the package.
- No new native symbols or ABI structs are required.

## 0.14.0 — paragraph justification

- Added `#:align 'justify` and `#:align 'justify-all` to `layout-text` and `layout-mixed-text`.
- `justify` expands wrapped non-final lines and leaves each paragraph's final line at logical start; `justify-all` also expands final/single lines.
- Justification adjusts positioned HarfBuzz glyph origins without reshaping, preserving glyph IDs, clusters, bidi run order, script segmentation, and font fallback.
- Expansion is deliberately inter-word only: U+0020 SPACE absorbs the extra width; NBSP/NNBSP, CJK inter-character spacing, letter spacing, and Arabic kashida are unchanged.
- Added LTR/RTL/mixed-bidi tests, doctor coverage, and `examples/justification.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.13.0 — Unicode line breaking

- Added a private Unicode 15.1 `Line_Break` property table and UAX #14 revision 51 resolver.
- `layout-text` and `layout-mixed-text` now fit lines greedily at Unicode line-break opportunities instead of whitespace runs only, including unspaced CJK and punctuation-aware breaks.
- Preserved default grapheme clusters as an explicit UAX #14 tailoring and retained non-tailorable ZWJ behavior at grapheme boundaries.
- Added Unicode hard-break handling for BK/CR/LF/NL separators, while retaining blank and trailing lines.
- Added line-break property/opportunity tests, native CJK/punctuation layout tests, doctor coverage, and `examples/line-breaking.rkt`.
- Southeast Asian dictionary segmentation, language-specific hyphenation/emergency breaking, and explicit UAX #9 embedding/override/isolate controls remain outside this stage; basic inter-word justification arrives in 0.14.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.12.0 — mixed-script and bidirectional text layout

- Added `layout-mixed-text` / `draw-mixed-text-layout` with multiple shaped runs per visual line.
- Added ordinary Unicode bidi resolution for paragraph direction, weak/neutral types, paired brackets, implicit levels, and visual run reordering.
- Added HarfBuzz Unicode-script classification and script-aware run segmentation.
- Added grapheme-preserving font fallback through `font-manager-match-character`, with fallback family/style metadata retained in pure layout runs.
- Added mixed-run wrapping/alignment, run inspection APIs, doctor coverage, tests, and `examples/mixed-text.rkt`.
- Explicit Unicode embedding/override/isolate controls are intentionally not interpreted in this stage; they are omitted from shaping. Full explicit-control UAX #9 support remains future work; UAX #14 line breaking arrives in 0.13 and inter-word justification in 0.14.

## 0.11.0 — paragraph text layout

- Added pure `text-layout?` and `text-layout-line?` values above shaped runs.
- Added `layout-text` with explicit newlines, greedy Unicode-whitespace wrapping, start/center/end/left/right alignment, horizontal LTR/RTL direction, and configurable line height.
- Added `draw-text-layout` using font-metric-derived baselines.
- Added `examples/layout.rkt`, doctor coverage, and layout tests.
- No new native symbols or ABI structs are required by this stage.

## 0.10.1 — HarfBuzz feature-struct compile fix

- Renamed the Racket-side `hb_feature_t.tag` field binding to `feature-tag` to avoid colliding with the `hb-feature-tag` identifier that `define-cstruct` generates for the cstruct pointer tag. The native ABI layout is unchanged.

## 0.10.0 — HarfBuzz shaping

- Added lazy loading of pinned HarfBuzzSharp 8.3.1.2 / HarfBuzz 8.3.1.
- Added owned `shaper?` resources that snapshot an Skia font/typeface for deterministic shaping and later TextBlob rendering.
- Added immutable `shaped-run?` values with glyph IDs, UTF-8 clusters, explicit glyph positions, and x/y advances.
- Added `shape-text`, OpenType feature strings, direction/script/language overrides, `shaped-run->text-blob`, `draw-shaped-run`, and `draw-shaped-text`.
- Added `tools/install-harfbuzz.sh` and `tools/audit-harfbuzz-symbols.sh`.
- Added `examples/shaping.rkt`, doctor coverage, ABI checks, and shaping tests.

## 0.9.0 — font managers and positioned text blobs

- Added owned `font-manager?` resources, default/fresh manager constructors, family enumeration, family-style matching, and character fallback with BCP-47 language hints.
- Added immutable `text-blob?` resources built from explicit glyph IDs and positions, blob bounds/unique IDs, and `draw-text-blob`.
- Added the native `sk_textblob_builder_runbuffer_t` layout mirror and host-C layout assertions.
- Added `examples/text-blobs.rkt`, doctor coverage, and font-manager/text-blob tests.


## 0.8.1 — path ABI symbol hotfix

- Corrected `sk_path_add_round_rect` to the actual m119 export `sk_path_add_rounded_rect`.
- Corrected translated path composition to call `sk_path_add_path_offset`; `sk_path_add_path` has only `(path, other, mode)`.
- Corrected `sk_path_reverse_add_path` to the actual export `sk_path_add_path_reverse`.
- Added `tools/audit-symbols.sh` to compare every `define-native` declaration with the selected native library in one pass.

## 0.8.0 — expanded paths and SVG geometry

- Added relative path commands, conic segments, rounded-rect insertion, path composition, point queries, and SVG path-data conversion.
- Added `examples/svg-paths.rkt`, doctor coverage, and native tests for path/SVG geometry.


## 0.7.1 — picture recorder symbol hotfix

- Corrected the pinned m119 FFI symbol for finishing picture recording from the nonexistent `sk_picture_recorder_finish_recording_as_picture` to the exported `sk_picture_recorder_end_recording`.

## 0.7.0 — pictures and recording

- Added immutable `picture?` resources with `picture-width` and `picture-height`.
- Added `picture-recorder?` resources plus `make-picture-recorder`, `picture-recorder-begin-recording!`, and `picture-recorder-finish-recording!`.
- Added `call-with-picture` convenience recording.
- Added `draw-picture` replay and `picture->image` rasterization.
- Added `examples/pictures.rkt`, doctor coverage, and picture tests.

# Changelog

## 0.6.0 — 2026-09-23

Adds the first standalone filter/effects layer: owned color, mask, and image
filter resources; 4×5 color-matrix, blend, and composed color filters; Gaussian
mask blur; image blur; drop-shadow and shadow-only filters; color-filter image
nodes; composed image-filter graphs; and paint constructor/getter/setter support
for all three filter families. Paints and filter graphs retain their inputs with
native reference counting, while getters expose independently owned wrappers.

The pinned m119 C shim and Skia implementations were audited for constructor,
attachment, getter, and release ownership. The m119 image-blur documentation
marks mirror tiling unsupported, so the Racket constructor rejects that mode.
The 0.6 source contains 105 test cases (23 pure, 6 lifetime, 76 native) plus a
six-panel `examples/filters.rkt` visual probe. These new filter paths were
source/ABI checked in the authoring environment but still require the included
local doctor, suite, and visual probe for live validation.

## 0.5.0 — 2026-09-23

Adds the first path-effects and path-measurement layer: dash, corner, discrete,
trim, compose, and sum path effects; paint attachment/getters; snapshot-safe
path measurement with contour traversal, position/tangent sampling, and segment
extraction; and boolean path operations including union, intersection,
difference, xor, reverse difference, simplify, and conversion to winding fill.

This version also corrects `paint-shader` ownership. The pinned m119 C shim's
`sk_paint_get_shader` already returns an owned reference via
`refShader().release()`. Versions 0.3/0.4 added another `sk_shader_ref`, which
kept rendering correct but leaked one native shader reference per getter call.
0.5 wraps the returned owned reference directly and documents the actual shim
semantics.

The completed 0.5 tree was subsequently live-validated on macOS/aarch64 with
Racket 9.3.0.2 and SkiaSharp 3.119.1: doctor passed, all 95 test cases passed
(21 pure, 6 lifetime, 68 native), and the path-effects visual probe rendered
correctly. See `TESTING.md`.

## 0.4.0 — 2026-09-23

Adds high-level encoded image support through the pinned SkiaSharp codec and
encoder C ABI: decode from byte strings or files; metadata probing without a
public image object; PNG/JPEG/WebP encoding; access to retained original encoded
data; image color/alpha metadata; raster subsets; and source-rectangle image
drawing. JPEG exposes quality, 4:2:0/4:2:2/4:4:4 downsampling, and alpha
handling; WebP exposes quality and lossy/lossless mode.

The ABI layer adds integer rectangles plus the JPEG and WebP encoder option
layouts, temporary codec/data/raster-image ownership, and explicit release of
the color-space reference returned through codec image info. A new
`examples/codecs.rkt` performs an in-memory render/encode/decode/crop round
trip. The 0.4 source contains 85 test cases (19 pure, 6 lifetime, 60 native).
The completed 0.4 tree was subsequently live-validated on macOS/aarch64 with
Racket 9.3.0.2 and the pinned native asset: doctor passed, all 85 test cases
passed (19 pure, 6 lifetime, 60 native), and the codec visual probe rendered
correctly.

## 0.3.0 — 2026-09-23

Adds the first standalone shader layer: owned `shader?` resources, color
shaders, linear/radial/sweep/two-point-conical gradients, tiled image shaders,
blend shaders, and shader attachment/querying on paints. Gradient stops accept
lists or vectors with optional explicit positions and all four Skia tile modes.
The implementation keeps the unsafe C ABI private and exposes paint shaders as
owned Racket wrappers. Version 0.5 corrects the exact native getter refcount
handling after auditing the m119 C shim.

The doctor, ABI checks, native regression suite, API reference, and a new
`examples/gradients.rkt` visual smoke test are extended for the feature. The
completed 0.3 tree was subsequently live-validated on macOS/aarch64 with Racket
9.3.0.2 and the pinned native asset: doctor passed, all 77 test cases passed
(17 pure, 6 lifetime, 54 native), and the gradients visual probe rendered
correctly.

## 0.2.0 — 2026-09-23

Adds the first standalone font and text layer: default, family, and file-backed
`typeface?` resources; configurable `font?` resources; font metrics; UTF-8
simple-text drawing and measurement; character/text-to-glyph mapping; and glyph
or simple-text outline paths. The ABI layer now includes the pinned SkiaSharp
font/typeface/string calls and the 64-byte `SKFontMetrics` layout. The doctor,
tests, example set, API reference, and ABI notes are extended accordingly.

The 0.2.0 source changes were initially checked statically in the authoring
environment. Its font/text paths were later exercised successfully as part of
the user's subsequent 0.3 doctor and complete 77-case regression run on
macOS/aarch64.

## 0.1.0 — 2026-09-23

Initial standalone CPU Skia binding using the SkiaSharp 3.119.1 native C ABI.
Adds resource ownership, drawing primitives, paths, clipping/transforms, image
snapshots and copied pixel input, native PNG output, a bitmap bridge, a native
installer/doctor, documentation, and tests.

The 0.1.0 baseline was subsequently validated on macOS/aarch64 with Racket
9.3.0.2 and the pinned native asset: doctor passed, all 57 source test cases
passed, and the circle, gallery, and bitmap-bridge examples rendered correctly.
