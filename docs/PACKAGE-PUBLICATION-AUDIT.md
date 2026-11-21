# Catalog packaging: historical Stage A audit and B–F amendments

This is an implementation audit at source baseline
`e944213d0fac4b02ef81bb35beb1e26729aca8f7`, November 20, 2026.
It is **not** a redistribution approval or a validated catalog candidate.
The Stage A observations below predate loader/metadata integration. The later
B–F implementation uses source version 0.79 and the proposed generation-1
package family while retaining the collection/API. Current outcomes and gaps
are in [CATALOG-VALIDATION.md](CATALOG-VALIDATION.md); historical pending-work
statements below are not the current implementation status.

## Findings that affect the plan

* Fresh NuGet inputs for SkiaSharp 3.119.1 and HarfBuzzSharp 8.3.1.2 all identify
  upstream source commit `cc78b5933d23e6383db5d246e70db915770d55d6`. HTTPS NuGet
  acquisition and observed hashes are provenance, not independent authentication
  or maintainer review. The input audit deliberately emits an **unreviewed
  observation report**, not an automatically accepted publication lock.
* The pinned fontconfig-enabled Linux Skia image needs GLIBC symbols through
  **2.27**. HarfBuzz needs GLIBC symbols through 2.14. Both are ELF64 x86-64
  shared libraries with no RPATH/RUNPATH. Neither needs a dynamically linked
  libstdc++ in its `DT_NEEDED`. GLIBC >= 2.27 is a necessary lower bound; it is
  not a demonstrated minimum distribution or a musl compatibility claim.
* Skia's non-glibc dependency is `libfontconfig.so.1`. The ordinary-Linux OS
  dependency route and the catalog package route must both be executed.
  Installing `draw-lib` is not proof that `dlopen` of an absolute Skia path
  resolves that SONAME. Do not add a dependency and declare this solved without
  exercising the loader in a real `x86_64-linux-natipkg` installation.
* The inspected catalog package `draw-x86_64-linux-natipkg-3`, checksum
  `fcccbfd5b48cbb919e067a2e549b585167e6444c`, supplies fontconfig, FreeType,
  libpng16, zlib, expat and uuid. Its fontconfig image needs all of those plus
  baseline glibc libraries and has `$ORIGIN` RPATH. This is a potential reuse
  route, **not yet a qualified selection**. Review the actual dependency graph
  at both selected Racket releases; a moving development `draw-lib` now names a
  different native generation.
* Execution in the official Racket 9.3 `pkg-build` distribution confirms a real
  loader problem: direct loading fails with missing `libfontconfig.so.1` even
  though Racket's managed library search directory contains it. Explicitly
  loading its absolute packaged path first permits Skia milestone 119 and
  HarfBuzz 8.3.1 bootstrap calls. This proves a possible repair, not rendering,
  symbol-interposition safety or font functionality. The support package bundled
  in that release has checksum prefix `9a9017d1388d`, different from the current
  catalog's `fcccbfd5...`; those inputs must not be silently equated.
* Both fresh macOS libraries are universal x86-64/ARM64. Their load commands
  specify macOS 10.13 (Intel) and 11.0 (ARM64), and use system libraries and
  frameworks. An observed deployment target is not execution qualification.
  The prototype must prove installed bytes stay unchanged before hashes are
  used for runtime provenance. No rewriting or re-signing recipe is approved.
* Fresh AMD64 Windows import tables list system DLLs only. Skia imports
  `ole32.dll`, `FONTSUB.dll`, `USER32.dll`, `d3d12.dll`, `D3DCOMPILER_47.dll`,
  `KERNEL32.dll`; HarfBuzz imports `KERNEL32.dll`. This is static inspection,
  not a clean-PATH execution or minimum-Windows determination. Delay imports
  and the actual clean-machine behavior still require review.
* Racket's `.CHECKSUM` companion is an exact SHA-1 string: a trailing newline
  fails archive installation on both 8.18 and 9.3. The builder now writes
  exactly 40 ASCII bytes, separately from SHA-256 receipts.
* On both 8.18 and 9.3, ordinary package installation **rejects** installing a
  package in user scope when that package name is already installed in
  installation scope. The plan's same-name user-shadowing scenario is not
  available through ordinary installation. Do not use `--force` to manufacture
  that scenario. Test rejected installation plus independent scope lifecycle,
  and test partial-directory search-order behavior in the eventual loader's
  synthetic fixtures.
* Setup's foreign-library receipt associates a directory basename with its
  collection; it does not itself reject every ownership overwrite. Therefore
  disjoint platform selectors, pair packaging, and preflight ownership checks
  remain requirements. Directory flattening would not solve this issue.

## Transitive input inventory

| Image | Direct dependencies or observed lower bounds |
| --- | --- |
| Linux Skia | pthread, fontconfig.so.1, dl, m, libc, ld-linux-x86-64.so.2; GLIBC <= 2.27 requirements |
| Linux HarfBuzz | pthread, m, libc, ld-linux-x86-64.so.2; GLIBC <= 2.14 requirements |
| Catalog fontconfig | freetype.so.6, png16.so.16, z.so.1, pthread, expat.so.1, m, uuid.so.1, libc; `$ORIGIN` |
| Catalog FreeType | png16.so.16, m, z.so.1, pthread, libc; `$ORIGIN` |
| Catalog expat / uuid | baseline glibc libraries |

No support libraries or fonts have been copied from the maintainer's machine.
No glibc redistribution is proposed. The original four-glyph font generator
in `tests/typeface-fixtures.rkt` can supply deterministic AV shaping tests;
it does not replace the Arabic/CJK fonts needed by existing tutorial figures.
The Pages workflow currently installs DejaVu, Liberation, Noto core and Noto
CJK. Documentation's declared-font solution is still open.

## Notice inventory and release stop

All six acquired archives contain `LICENSE.txt` and the same combined
`THIRD-PARTY-NOTICES.txt`. The local prototype preserves both verbatim for
each upstream library, along with its nuspec. It does not infer that MIT alone
covers the native package.

The supplied notice sections are ANGLE, HarfBuzz, Skia, etc1, gif, libpng,
DNG SDK, expat, FreeType, ICU, imgui, jsoncpp, libjpeg-turbo, libwebp,
libmicrohttpd, piex, SDL, sfntly, SPIR-V Headers, SPIR-V Tools and zlib.
The document includes differing licenses and subcomponent conditions. A
section's inclusion in a combined upstream notice does not establish that
component's presence in each platform binary. Exact embedded-component/source
mapping, per-component identifiers, source-offer obligations where applicable,
support-library selection and font notices require a completed redistribution
review. **No payload has been approved for publication.**

There is a concrete completeness gap: all three inspected Skia binaries contain
Wuffs strings (Linux includes `#base: bad wuffs version` and Wuffs decoder
vtable strings), but the combined notice has **no Wuffs section**. This is an
indicator of incorporated code, not a complete link-map reconstruction. The
NuGet source commit's Skia submodule is
`40f75dc0051d141913c07c20d4c19590c7da0cb7`; its `DEPS` pins Wuffs to
`e3f919ccfe3ef542cfc983a82146070258fb57f8`, and `third_party/wuffs/BUILD.gn`
builds its GIF/LZW implementation. That exact Wuffs repository has an
Apache-2.0 `LICENSE`, acquired separately as review evidence. It is **not yet
part of the experimental ZIP's notices**. Audit the remaining component set
too; copying the NuGet notice alone is insufficient. Relevant immutable sources:

* [SkiaSharp's Skia submodule](https://github.com/mono/SkiaSharp/tree/cc78b5933d23e6383db5d246e70db915770d55d6/externals/skia)
* [Skia DEPS](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/DEPS)
* [Wuffs build selection](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/third_party/wuffs/BUILD.gn)
* [Pinned Wuffs license](https://github.com/google/wuffs-mirror-release-c/blob/e3f919ccfe3ef542cfc983a82146070258fb57f8/LICENSE)

The experimental builder fails closed without `--local-candidate`, and even
editing review flags cannot enable release assembly: complete license and
transitive-dependency metadata must be implemented after this review. Its
archives and receipts are explicitly labelled local experiments and always
record `catalog_candidate_validated: false`.

## Reproduction

Acquire the exact six pinned NuGet archives using the URLs recorded in the
observation report. Keep them in an ignored input directory. Then:

```sh
python3 tools/test-native-packages.py
python3 tools/audit-native-inputs.py --inputs output/catalog/input \
  --output output/catalog/observed-native-inputs.json
python3 tools/build-native-packages.py \
  --lock output/catalog/observed-native-inputs.json \
  --inputs output/catalog/input --output output/catalog/prototype-archives \
  --local-candidate
python3 tools/prototype-native-lifecycle.py \
  --runtime output/catalog/runtimes/8.18/racket \
  --archive output/catalog/prototype-archives/skia-native-macos-1.zip \
  --directory /private/tmp/skia-catalog-lifecycle-8.18
```

Use a fresh output/evidence directory on each invocation. Repeat the lifecycle
probe with the exact released 9.3 runtime. It copies the runtime before any
package mutation and uses explicit disposable HOME/PLTADDONDIR values; every
`raco` operation is invoked with that same copied Racket executable. Logs and
partial failure receipts are retained. It never uses `--no-docs`, `--force` or
checksum bypasses. The native fixture has no manual and cannot prove full Skia
manual building, `raco test --drdr` or automatic managed discovery. Adding
`--source-root /absolute/checkout` runs actual asymmetric rendering, exact PNG
round trips and generated-font AV shaping using the existing explicit-override
route with checkout bytecode disabled. Those results are labelled separately.

Runtime tarballs were checked against the official release-page SHA-256:

| Runtime | SHA-256 |
| --- | --- |
| 8.18 aarch64 macOS minimal CS | `d59d2021577f3ae2dd31c1058ace38043e7e660726c49081781550d81c32fcf1` |
| 9.3 aarch64 macOS minimal CS | `93c498c54804945c53412395e9ec7b33c56834f541710c2b3e161182be0c2670` |

## Observed validation results

Implementation amendment for stages B–F: the public API has no directory-font-
manager constructor. The earlier plan's font-directory discussion concerns the
DC font mapping, not a standalone native manager. The declared Noto data is
therefore used through existing `typeface-from-file` operations in script
figures/tests. No new public font-manager feature is introduced.

* `python3 tools/test-native-packages.py`: 28 tests passed, including unsafe
  paths, duplicate/case collisions, special files, archive expansion, bounded
  metadata, DTD/entity/UTF-16 rejection, wrong asset identity/architecture,
  missing notices, hash/CRC corruption, deterministic ZIPs and exact checksums.
* Racket 8.18 and released 9.3: 12 platform-selection fixtures passed each.
* macOS ARM64: 50-command lifecycle probe passed at **each** released Racket
  version, including repeated explicit-path CPU render/shaping after conversion
  and recovery of moved payloads. Earlier 41-command bootstrap-only results
  also passed. No macOS Intel or Windows execution is claimed.
* Three platform ZIPs and `.CHECKSUM` companions matched byte for byte across
  two assemblies from verified cached inputs. All receipts remain explicitly
  unreviewed/local and false for candidate validation.
* Linux x86-64 under QEMU with Docker `--network none`: real ordinary 9.3 and
  `x86_64-linux-natipkg` native setup passed; foreign macOS install/remove was
  inert in both. Both direct Skia loads failed for missing fontconfig. The
  proposed natipkg preload bootstrap passed. No complete Linux render/shaping,
  load-order, docs or lifecycle pass is claimed.
* Existing Windows installer regressions: 12 passed. Existing CI driver
  regressions: 103 passed. Existing release-candidate regressions: 147 passed
  with pinned PyYAML 6.0.3 in a disposable Python 3.14 venv. The local Python
  3.12 lacked SSL, and initial runs without YAML failed; those failures were
  retained rather than changing the checks.
* Existing release source contracts passed with `source_verified: true`,
  `release_candidate_validated: false`, 66 unchanged required jobs and 73
  unchanged required artifacts. No source or workflow ledger was regenerated.

Full dependency-driven source installation, a candidate staging catalog,
all-manual setup, DrDr traversal, production managed discovery, Linux text load
orders, minimum-Racket Linux, Windows, Intel macOS, and same-candidate full
CI/Acceptance/API execution remain **unrun/unimplemented**, not passed.

## Next gate

Complete Linux ordinary/natipkg execution and redistribution review before
turning the observations into `packaging/native-assets.json` or changing main
package dependencies/version and frozen release/API/source ledgers. The
original Docker application and backend were Intel binaries. The operator
replaced them with ARM64 Docker and disabled Rosetta after the verified Racket
runtime failed at Chez's `petite` bootstrap under Rosetta. QEMU then executed
the offline probes. Initial environment failures are retained. A Windows runner
and Intel macOS execution lane remain unavailable in this session. ARM64 macOS
bootstrap results cannot close those gates.

Stages C–F still require the paired lazy managed loader, installed rendering
and shaping, font/doc audit, staged exact-source dependency catalog, offline
execution, bounded DrDr traversal, rebuilt source-package round trips and
same-candidate CI/Acceptance/API evidence. Do not bless new policy snapshots to
conceal those missing checks. Publication remains a separate approved action.

## B–F validation amendments

The real natipkg manual build disproved the assumption that preloading and
configuring Racket's fontconfig alone was sufficient. Its three declared
FreeFont faces enumerate correctly and explicit `sans` matches/shapes, but
Racket's minimal `fonts.conf` lacks the needed `sans-serif` alias and weak
default-family rule. Skia m119's default
legacy typeface consequently becomes an empty face and shaping has no font
stream. The implementation adds a small generation-owned natipkg fontconfig
configuration using the same declared fonts, a `sans-serif` alias and a weak
default `FreeSans` append rule. The alias alone did not repair an empty family
pattern. It does
not replace a native library, add a font-manager API or copy host fonts. The
support library is fontconfig 2.13.0. Relative paths and its process-wide
patched directory prefixes did not work after Draw-first initialization.
An explicit-path prototype passed both orders. The payload therefore retains
a hashed XML template; first native use materializes escaped declared font and
cache paths into a content-addressed text file in Racket's addon font cache.
Installed source and library bytes remain untouched. The derived cache is
recorded separately and involves no native installation or download. The native
process environment selects it before Skia's first font manager; Scribble
environment copies cannot substitute for that environment. An existing explicit
process `FONTCONFIG_FILE` is preserved. Ordinary font caches may outlive package
removal; the owned native payload must still disappear.

Racket `catalog-archive` also repacks candidate ZIPs. The stager now restores
the original candidate ZIP/checksum bytes and overlays their exact catalog
records after staging standard dependencies. Earlier snapshot runs are useful
payload diagnostics, not exact-archive qualification. Execution preflight and
the release verifier reject those earlier receipts.

Racket's `pkg create --built` rewrites `info.rkt` into a module and adds
`package-content-state`; binary-library form changes foreign-directory copy
metadata to move metadata. Rebuilt archives must retain every native/data and
notice byte exactly, while a Racket metadata comparison checks all data-package
fields and permits only those documented packaging-state/directory rewrites.
Comparing metadata source syntax byte for byte would reject Racket's own forms.

Keeping a directory in `binary-keep-files` does not recursively keep the `.rkt`
sources inside it when corresponding bytecode exists. Actual binary-library
installation rendered/shaped successfully but the advertised tutorial copier
failed because `language-sampler.rkt` had been stripped. Main package metadata
now retains every editable file named by the tutorial catalog explicitly. The
validator independently checks the complete catalog source set in each rebuilt
ZIP before exercising the installed copier, so new catalog entries cannot
silently lose their editable source.

The first installed catalog picture/pict test exposed a pre-existing geometry
bug: native picture extents are inexact numbers, so `ceiling` also returned an
inexact integer and the allocation guard rejected an otherwise valid default
`picture->pict` call. The implementation work includes the minimal conversion of
that already-checked ceiling to an exact pixel count, with an inexact-extent
regression. It adds no API or drawing feature and preserves the finite/range and
memory guards. Using explicit bounds merely to avoid this failure would not
validate the advertised default bridge.

## Primary references

* [Racket package-build native conventions](https://pkg-build.racket-lang.org/about.html)
* [Foreign-library setup metadata](https://docs.racket-lang.org/raco/setup-info.html)
* [Racket package stripping](https://docs.racket-lang.org/pkg/strip.html)
* [Racket 8.18 release and checksums](https://download.racket-lang.org/releases/8.18/)
* [Racket 9.3 release and checksums](https://download.racket-lang.org/releases/9.3/)
* [Inspected catalog support package](https://pkgs.racket-lang.org/package/draw-x86_64-linux-natipkg-3)
