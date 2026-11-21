# Catalog packaging and publication runbook

The 0.79 source candidate keeps the single `skia` collection and existing public
API. It declares native generation 1 (package revision 1.0), with SkiaSharp
3.119.1 and HarfBuzzSharp 8.3.1.2 unchanged, plus `skia-fonts-1` 1.0 data.
**Nothing has been published.** See [the validation record](CATALOG-VALIDATION.md)
for executed commands, failures, timings and external qualification gaps.

## Review and freeze the inputs

Read the [complete plan](../plans/skia-package-catalog-publication.md),
[original audit and amendments](PACKAGE-PUBLICATION-AUDIT.md),
[component review](../packaging/COMPONENTS.md), and
[locked inputs](../packaging/native-assets.json). The lock records immutable
URLs, archive/member/font sizes and hashes, NuGet/source identities, native
architectures/load requirements, component notices and Linux support routes.
Font Git blob hashes were inspected separately from their downloads.

Maintainer redistribution sign-off is pending, including exact GCC runtime
exception applicability, Adobe DNG conditions, Windows toolchain terms and
upstream's incomplete embedded-component attestation. Do not mark those fields
approved merely because the program runs. Names/version defaults and catalog
name availability still need final maintainer review before first publication.

The source package is MIT. Each native package has its own component license
expression and complete original/supplemental texts. The font package is
OFL-1.1 and contains unmodified Noto files and their copyright metadata.

## Acquire, then assemble offline

Use exact released 64-bit Racket CS 8.18 and 9.3 executables, not a development
version whose directory happens to be named 9.3. Generated/native/font binaries
stay under ignored output directories and never enter the source ZIP.

```sh
python3 tools/prepare-native-packages.py --lock packaging/native-assets.json \
  --cache output/catalog/verified-inputs
python3 tools/test-native-packages.py
python3 tools/test-catalog-packaging.py
python3 tools/build-native-packages.py --lock packaging/native-assets.json \
  --inputs output/catalog/verified-inputs --output output/catalog/assembly-a --local-candidate
python3 tools/build-native-packages.py --lock packaging/native-assets.json \
  --inputs output/catalog/verified-inputs --output output/catalog/assembly-b --local-candidate
python3 tools/compare-native-artifacts.py output/catalog/assembly-a output/catalog/assembly-b
```

Acquisition accepts only the existing lock. For a fully local cache, supply
`--from-directory` for the six NuGets and `--font-directory` for the four fonts.
The bounded ZIP reader rejects traversal, collisions, symlinks, bad CRCs,
oversized/decompression-bomb inputs and ambiguous XML. Assembly has no network
code and validates every input before writing a payload. Stored ZIP members
have sorted names, fixed timestamps and regular-file modes. Racket's `.CHECKSUM`
is an exact 40-byte SHA-1 string without a newline; receipts additionally record
SHA-256, source/lock/generator identities and original member hashes. Native
bytes are unmodified; the lock permits no transformations.

Default release assembly refuses pending review. `--local-candidate` explicitly
allows disposable testing and keeps all receipts unvalidated. It does not
approve redistribution or bypass the final release checks.

## Stage the unpublished catalog

```sh
python3 tools/stage-native-catalog.py --racket /absolute/released/racket \
  --output output/catalog/candidate --cache output/catalog/verified-inputs --snapshot
```

A dirty implementation checkout must add `--allow-dirty` for local diagnosis;
its source identity explicitly remains dirty and cannot satisfy release gates.
The catalog contains exact source/native/font ZIPs and dependency metadata,
including build dependencies for registered manuals. `--snapshot` stages the
selected interpreter's complete platform-specific dependency closure from its
explicit official release catalog. `--base-catalog` can reuse an already staged
compatible closure. Never point the ordinary maintainer's package config here.
The receipt retains the complete dependency graph and SHA-1/SHA-256/size inventory
of every staged archive. Execution rechecks that closure before installing.

The source writer rejects native libraries, font binaries, bytecode, caches and
generated output. Staging embeds an observed commit/clean-state receipt into
the source archive; a dirty HEAD is never labelled an exact validated commit.

## Execute with networking denied

On a **fresh disposable CI runner**:

```sh
python3 tools/run-catalog-ci.py --racket /absolute/released/racket \
  --output output/catalog-ci
```

This separates acquisition from execution, compiles a deliberately incompatible
scalar ABI fixture, then runs the validator under macOS sandbox-exec, Linux
network-namespace isolation, or narrowly scoped Windows process firewall rules.
Windows rules are removed in `finally`. The tool is for disposable runners;
never use it to change a normal workstation's network configuration.

For a prepared macOS runtime/catalog, run the lower-level validator inside an
OS network-denial sandbox. Use a new work directory each time:

```sh
cmake -S tools/catalog-fixtures -B output/catalog/abi-fixture -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build output/catalog/abi-fixture --config Release
sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  python3 tools/validate-catalog-package.py \
  --runtime /absolute/relocatable/racket-root \
  --catalog /absolute/candidate/snapshot/catalog --owned-stage /absolute/candidate \
  --wrong-abi /absolute/abi-fixture/skia-wrong-abi.dylib \
  --work '/private/tmp/skia catalog qualification'
```

`--owned-stage` authorizes removal of that disposable stage's original candidate
archives/cache after rebuilding, so rebuilt installations cannot resolve the
original candidates. Preserve a separate assembly artifact set first. The
validator copies the runtime, uses new homes/addon directories containing spaces
and non-ASCII text, runs outside source/staging/install directories, clears
native/library/collection overrides, and records OS network-denial errors.
Timeouts or DNS failures do not establish isolation.

The ordinary commands include:

```sh
raco pkg install --auto --batch skia
raco setup --check-pkg-deps --pkgs skia
raco test --drdr --package skia
racket -l skia/tools/catalog-smoke --
racket -l skia/tools/catalog-smoke -- --draw-first
```

No native-install script, `--no-docs`, runtime download or missing-native skip is
used in this lane. It builds every registered manual from the source package,
checks dependencies, actual pixels/PNG/shaping/default fonts, original AV
fixture, path/picture/PDF/SVG/bitmap/pict behavior, lazy imports, corrupt/missing
managed data, incompatible ABI, invalid overrides, read-only source first use,
compatible update/rollback, scope/removal ownership and example copying. It
rebuilds source/built/binary-lib packages, verifies data/notices, removes the
original environment and candidate archives, and reinstalls the rebuilt forms.
Every advertised editable tutorial file is checked against the tutorial catalog
in all forms; directory keep entries alone do not preserve compiled Racket
source. Foreign-target packages also set up as inert data and preserve their
native/notice bytes in binary-library rebuilding without activating a generation.
The actual DrDr traversal has a 600-second overall bound and retains its timing.
Partial diagnostic switches never satisfy the final catalog evidence checks.
Use `x86_64` for the fixture on an Intel Mac; the compiler's default target can
differ from the selected Racket target on Apple silicon.

## Qualify Linux and the other platforms

Ordinary Linux explicitly needs glibc >= 2.27, OS fontconfig and a default Latin
font (the CI baseline declares `fonts-dejavu-core`). That symbol
floor is an inspection result; Debian 12 execution alone does not qualify every
older distribution. The real natipkg native package directly declares draw's
native and TTF support packages. Skia preloads absolute Racket-managed
fontconfig. On first native use, its verified data-only template is materialized
with absolute declared font/cache paths into a content-addressed configuration
under Racket's user font cache. Native `FONTCONFIG_FILE` selects that file even
inside Scribble evaluators; existing native fontconfig environment settings are
preserved. The old fontconfig needs both a `sans-serif` alias and a weak default
family rule. Source/library payloads remain read-only and native bytes remain
unchanged. Derived font caches may survive package removal like other font
caches. HarfBuzzSharp retains Linux local/deep-bind isolation. Test both text
initialization orders and cold-cache first use with read-only installed source.

`packaging/racket-runtimes.json` pins official 8.18/9.3 pkg-build installers.
`tools/prepare-natipkg-runtime.py` acquires those exact runtimes. The catalog
workflow stages on the real target, then executes in the recorded Debian image
without OS fontconfig and with Docker `--network none`. Record image digest,
package inventory and actual target identity. Apple-silicon QEMU is useful
functional evidence but cannot replace native x86-64 throughput qualification.

Require both Racket versions on macOS ARM64/x86-64, Windows x86-64, ordinary
Linux x86-64 and actual natipkg. Windows must use clean PATH/dependent-DLL tests
and stop rendering processes before update/remove. Keep macOS deployment and
Windows imported-DLL requirements distinct from execution-qualified baselines.
Do not advertise Linux ARM64, musl, 32-bit, BC or new targets from metadata alone.

## Retain all release gates

The existing CI, Acceptance, API inventory, GPU/GUI and source-binary exclusions
remain required. CI's explicit developer-installer lane now resolves declared
dependencies through a disposable candidate catalog, installs the same locked
inputs and selects its local libraries using explicit overrides. It stays
separate from managed catalog qualification. Pages build assumptions also use
an exact unpublished dependency catalog. Frozen API call-boundary snapshots
remain the historical 0.78c baseline and are not regenerated for packaging.

The 0.79 release graph adds Catalog packaging as a fourth required gate: ten
platform/version execution lanes and one reproducible artifact set. Review the
frozen graph, current-version assertions, release-scope input hashes and matrix
document together. The aggregator retains existing bounded artifact checks,
compares candidate archive digests across catalog lanes, checks complete local
receipts and approved review state, and refuses partial/mismatched evidence.
Native ZIPs are retained once; per-lane uploads contain bounded logs/receipts.

A complete candidate needs one clean committed source identity, exact source
and native/font ZIPs/checksums/receipts, approved lock/notices, dependency snapshot
and same-attempt CI/Acceptance/API/catalog evidence. Current local working-tree
runs remain partial evidence; `catalog_candidate_validated` stays false.

## Publication requires a separate decision

Stop here until every required qualification and review gap is closed. Then
present the exact immutable artifact set, all receipts and checks, names,
versions, repositories and catalog source URLs to the maintainer and request
explicit publication approval. Implementation/testing does **not** authorize
creating repositories, tags, releases, uploads, catalog entries or settings.

After explicit approval, publish the already-validated immutable archives and
complete notices/checksums, register native/font dependencies before the main
`skia` package, verify public catalog resolution in a fresh disposable user,
and archive the exact accepted evidence. Do not rebuild different bytes during
upload. Updates keep generation 1 only for a compatible packaging revision;
asset/ABI changes require a deliberate new generation. Rehearse explicit
rollback to the previous archive and checksum rather than relying on implicit
version downgrades. Public catalog updates are a separate authorized action.
