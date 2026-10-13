# Skia Reference development: R3c effects and filters

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
