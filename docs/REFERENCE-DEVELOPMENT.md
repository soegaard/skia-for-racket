# Skia Reference development: R2.1 core corrections

The Reference is one registered multi-page manual assembled from
`scribblings/reference/reference.scrbl`. R2.1 refines the R2 core reference.
It documents 214 bindings through 257 public export paths in twelve conceptual
chapters. The five additions are standard color-space constructors and queries.
The work does not change library behavior.

## Scope and chapter ownership

| Chapter | Bindings | Scope |
|---|---:|---|
| Notation and Conventions | 0 | Signatures, numeric and coordinate conventions. |
| Resources and Lifetimes | 6 | Existing lifetime protocol and byte limit. |
| Surfaces and Canvases | 11 | Construction, backing, dimensions, snapshots, pixel copies. |
| Canvas State | 19 | Save/restore, affine transforms, clipping and backend queries. |
| Color Specifications | 17 | Byte colors and standard color-space construction and queries. |
| Paints | 37 | Construction, copy, getters/setters, reset, blending and stroke expansion. |
| Shaders and Gradients | 9 | Basic gradients, image and composite shaders, local matrices. |
| Drawing | 8 | Paint, line, rectangle, rounded rectangle, oval, circle, path and polygon. |
| Paths | 64 | Commands, geometry, iteration, filled-region operations and measurement. |
| Affine Matrices | 21 | Detached six-coefficient transforms, composition, inversion and mapping. |
| Images | 15 | Encoded/raw construction, metadata, pixel copies, subsets and drawing. |
| Image Encoding | 7 | PNG/JPEG/WebP byte encoders and file writing. |

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
text, filters, recorded pictures, documents, streams, caches, GPU and GUI/DC
integration. The subsequent stages must add their own semantic entries. No
unwritten entries are hidden behind artificial anchors or counted as complete.

## Authoritative source checks

R2.1 repository baseline: `f20b68d866f6c1b92de94c19c62754978a8e9a0d`.
The upstream `for-label` and module-declaration corrections are preserved.
The following implementation blobs supplied the R2 specifications. The public paths,
not private implementation modules, are the documented import paths.

| Implementation file | Git blob |
|---|---|
| `private/core.rkt` | `9861b7cf96ea6002c71e7eb904780d2fddff808e` |
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
full-snapshot checks.

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

## Running the checks

Keep generated output outside the repository so it does not enter the source
manifest. The `skia` collection must resolve to the revised checkout.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 -B tools/test-reference.py
python3 -B tools/check-reference.py --output ../reference-r2.1-source
"$RACKET" -l raco -- test tools/reference-matrix-test.rkt
python3 -B tools/check-reference.py --render --quick --native --racket "$RACKET" \
  --output ../reference-r2.1-check --review-zip ../skia-reference-r2.1-review.zip
```

Use fresh output paths. The matrix test needs only the public `skia/matrix`
module, not native Skia. It checks coefficient order, detached inputs, rounding,
composition, inversion, point/vector differences and transformed bounds.
The Reference itself evaluates only pure color and affine-matrix examples.
Native examples are displayed as code and run only by explicit acceptance tests.

The render driver retains Revision 2.1's module-based root prefixes and `top`
tags. It builds a Reference seed, the three linked companion manuals, and then
the final Reference with their cross-reference information. The final Reference,
not the seed, must pass. The probe covers all 257 export paths, including matrix
constants and geometry aliases. The Quick check still targets its six original
foundation identifiers; it is not full tutorial-site acceptance.

Companion tutorials use native Skia for their diagrams. Native acceptance adds
`reference-native-test.rkt` and `reference-core-test.rkt`; neither opens a GUI or
creates a GPU context. The first reads every displayed `racketblock` example from
the actual chapters and runs each twice in a fresh namespace and temporary
working directory. The second checks state restoration, clipping, paint copies,
retained getters, native paint defaults, path snapshots, curve bounds, conic
reductions, path measurement, independent images, standard color spaces and encoder options.

The review ZIP gate checks the final HTML, sources and resources, then checks
an extracted copy. It refuses bad links, stale source hashes, missing assets or
incorrect definition destinations. A passing Python fixture test or source-only
check is not a successful Racket build. The deliberately limited
`--documents-only` mode cannot establish export coverage, runtime correctness,
or rendered-link success.

## Installed documentation and publication

Use the actual installed package name. With the existing repository convention:

```sh
"$RACKET" -l raco -- setup --no-zo --pkgs skia-for-racket
python3 -B tools/check-reference.py --installed "$PWD/doc" --racket "$RACKET" \
  --output ../reference-r2.1-installed
python3 -B tools/check-reference.py --site ../site --site-source "$PWD/doc" \
  --targets ../reference-r2.1-installed/runtime.json --output ../reference-r2.1-site
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
