# Current inventory: 0.74

Advanced layers, native recorded drawables, and scoped diagnostic canvases have explicit restrictions. Source coverage is not execution evidence.

# Current inventory: 0.73

GPU surfaces/properties and checked backend descriptors are implemented with explicit limits. Source declarations are not native execution receipts.

# Current inventory: 0.72

Seven image capability families are reconciled against direct image operations. Source declarations remain separate from runtime/CI evidence. Historical outstanding non-image work is not silently reclassified.

# Current inventory: 0.71

Four float-color/pixmap families are now public. F16/F32 storage extends the reviewed pixel model; native/document execution remains separate evidence.

## 0.70 inventory update

Six integer-storage families now have reviewed public routes and explicit limits.
Counts come from `docs/SKIASHARP-GAPS.md`; historical execution evidence remains
unchanged. See `docs/INTEGER-PIXELS.md` for raw storage, alpha and GPU restrictions.

## 0.69 inventory update

The three planned text/glyph-position families are now public. Current counts
are generated in `docs/SKIASHARP-GAPS.md`; historical execution evidence is
unchanged. See `docs/TEXT-BLOBS.md` for explicit backend and outline limits.

## 0.68b inventory update

Current source inventory: four SkFont capability groups are now public. Exact
counts and dispositions are generated in `docs/SKIASHARP-GAPS.md`; execution
evidence remains separate. See `docs/FONT-QUERIES.md`.

# Capability inventory maintenance — 0.68a

0.67 updates expected bindings and public anchors on the accepted 0.66 baseline.
Historical execution evidence stays pinned to its original commit; it is not
rewritten into new geometry-execution evidence. All nine planned 0.67 groups
are `supported-with-limits`; see [geometry](../docs/GEOMETRY-COMPLETION.md).
There are 514 distinct bindings (463 CPU), 37 public modules and 46 remaining
`missing-available-abi` capability groups. These are inventory counts, not a
percentage of functionality or a claim that new native tests have already passed.


This directory is the reviewed input to `tools/api-inventory.py`. It does not
initialize a renderer or replace the runtime API. The user's private/local
`plans/` directory is not read, generated, ignored, renamed or modified by it.

## Files and trust boundaries

- `upstream-m119.json`: exact comparison pins; a finite normalized list of core C
  function declarations; all 86 managed core source files; explicit exclusions.
- `bindings-baseline.json`: expected CPU and combined CPU/GPU declaration sets at
  the baseline. Nine registries are scanned, including later Metal/D3D interop.
- `capabilities.json`: reviewed capability-family dispositions, every scoped C
  entry point, public declaration anchors, test sources, limitations, document
  behavior and next stage. Managed crosswalks are **source-family** coverage,
  not exhaustive C# overload/property/enum reflection.
- `baseline-evidence.json`: authentic historical Linux CI identity, library hash,
  manifest hash and aggregate audit. No per-symbol exported list was retained in
  that artifact. Candidate m153 probe data is not evidence for the default m119
  library. Current feature-level rendering claims are not inferred.

A "missing-available-abi" disposition means an entry is declared by the pinned C
interface. The symbol may be absent or a nonfunctional platform stub in a
particular binary. Native resolution is an optional separate gate; rendering
acceptance remains a different gate. Native ref/unref, equivalent value operations
and C# convenience overloads do not inflate a feature-completion percentage.

The functional C scope excludes `sk_linker.h` keep-alive scaffolding and
`sk_types.h` typedefs/macros from function counts. Their exact files are still
verified by the upstream source gate. Skottie/resources/invalidation add-ons and
platform Views/UI packages are explicitly outside the core comparison. ABI
signatures/structure layouts remain covered by the existing ABI tools.

## Normal source check

```bash
python3 tools/test-api-inventory.py
python3 tools/api-inventory.py --check
python3 tools/validate-api-inventory.py
```

The checker discovers all root, `private/` and `unsafe/` production `.rkt` files,
verifies registered binding forms (not comments or macro templates), rejects new
unregistered Skia binders, and checks the complete expected symbol set. Public
anchors are checked through explicit `provide`/`all-from-out` declarations, not
claimed to be expanded/reflected exports. Native callbacks/GUI code are not run.
A change to an anchored public declaration or discovered module must be reviewed.

`validate-api-inventory.py` requires a real complete Git checkout and verifies the
source manifest before and after. It hashes audited source files and publishes a
success receipt only after all selected gates pass. Its output is a fresh
`output/api-inventory-0.67-*` directory. It never silently treats a fragment fixture
as a complete checkout. Keep the existing full Racket and rendering validators.

## Exact pinned upstream verification

Prepare checkouts of the two exact commits (sparse checkouts are sufficient):

```bash
python3 tools/validate-api-inventory.py \
  --skia-source /path/to/mono-skia \
  --skiasharp-source /path/to/mono-SkiaSharp
```

Both HEAD commits, complete scoped trees, file Git blob hashes and parsed C
function names must match. Dirty or truncated source is rejected. Managed bodies
are hash-verified and their full core source tree must match; this is not a claim
that a C# compiler/reflection has audited every overload. The regular offline
check uses the retained normalized list, and reports that upstream verification
was not run unless the checkout gate was selected.

No downloads take place in the inventory tool. CI checks out exact pinned sources
into ignored output paths. Changing a comparison pin requires editing/reviewing
the upstream list and crosswalk, never silently following a moving branch.

## Explicit installed-library observation

```bash
python3 tools/validate-api-inventory.py \
  --native-library /absolute/path/to/libSkiaSharp.dylib
```

Use `.so` on Linux or `.dll` on Windows. Pass the actual installed library, not a
header or candidate ABI. The parent process never loads it. A disposable Python
child hashes it, calls only `sk_version_get_milestone` and
`sk_version_get_increment`, requires ABI 119.0 / 64-bit, and attempts to resolve
all scoped symbols. The result names resolved/missing entries and the exact
binary hash. Required CPU symbols must resolve; optional backend entries may not.

The scalar ABI check alone does not establish a NuGet package version. The
report records that package identity is not verified by the observer; compare its
library hash with the installer's retained provenance when selecting a package.

This is **symbol resolution, not direct-export enumeration, signature execution,
backend availability, hardware acceleration, or rendering**. A symbol stub may
resolve. Full native/rendering suites are still mandatory for implementation
acceptance. A changed library, crash, timeout, foreign token/hash, partial report
or invented execution flag fails the selected gate. All command/stdout/stderr
and input/observation evidence is retained.

## Updating the inventory

1. Review source and update the relevant capability disposition, actual public
   equivalent, restrictions, tests and planned stage. New native names must be
   mapped explicitly in both finite lists and the owning capability.
2. Update the expected binding declaration set when adding/removing bindings.
   Keep missing declarations distinct from source-equivalent implementations.
3. Run `python3 tools/api-inventory.py --write`. This regenerates only
   `docs/SKIASHARP-GAPS.md` after catalog and full-source checks. It cannot bless
   an unknown native symbol or missing source anchor automatically.
4. Run the Python tests, manifest updater, checker and selected validation gates.
   Include the regenerated source manifest in the commit.

Runtime test-source references do not become execution receipts when edited.
New public modules require explicit inventory additions. Future API sketches in
`docs/API-DESIGN-DECISIONS.md` are not public exports introduced by this stage.

## CI boundary

The existing source/contract job includes the new Python tests and source audit.
A separate **API inventory** workflow verifies pinned upstream source bytes and
observes the installed Linux m119 library on Racket 8.18 and 9.3. Existing four
rendering/package workflows and their required aggregate are unchanged. This
fifth workflow must also pass before accepting 0.65; adding it does not modify
GitHub branch-protection rules.

0.67 adds 55 native declarations across geometry families. Four low-level iterator/empty-value declarations remain unbound with explicit safe Racket equivalents; inventory rows retain that distinction.

## 0.68 split

Stage 0.68a (package version 0.68.1) covers typeface resources and metadata.
The four font-state/glyph-query groups remain explicitly assigned to 0.68b;
0.69 and subsequent stages are unchanged. Declaration coverage is not an
execution claim. See `docs/TYPEFACES.md`.

Current 0.68a inventory: 536 distinct bindings (485 CPU), 38 public modules,
43 available-ABI groups still missing and one bound-but-not-public group.
The four remaining SkFont-related groups are planned for 0.68b. The four
typeface groups implemented here are documented in [TYPEFACES](../docs/TYPEFACES.md).
