# Skia Reference development: R3f streams and codecs

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
