# Implementation plan: publish Skia with platform-specific native packages

Status: proposal and implementation hand-off. No catalog registration, release
upload, package installation, or runtime implementation is performed by this
document.

Date: November 20, 2026.

Amended November 22, 2026 at the maintainer's request: Windows x86-64 uses an
explicit installer that acquires both pinned binaries directly from NuGet.
The project does not publish a Windows native data package. macOS and Linux
retain the package-managed design. This supersedes the original Windows
one-command/native-package assumptions and does not approve any publication.

Inspected source baseline: `e944213d0fac4b02ef81bb35beb1e26729aca8f7`.
Recheck the checkout and relevant instructions before implementation. Preserve
unrelated work. The proposed names and release numbers below require a final
availability/maintainer check before publication, not before local development.

## 1. Outcome and first-release decisions

On macOS and Linux, a user should be able to run:

```sh
raco pkg install --auto skia
```

and then use `(require skia)`, render a PNG, and perform text shaping without
running the project's native-install scripts, configuring library paths,
installing .NET, or compiling Skia. Normal Racket package installation may
download packages; compilation, documentation building, testing, and first
render must not download anything.

Windows is the explicit exception. With Python 3.12 or later available, use:

```sh
raco pkg install --auto --no-setup skia
racket -l skia/tools/install-windows-natives
raco setup --pkgs skia
```

The middle command acquires the locked SkiaSharp 3.119.1 and HarfBuzzSharp
8.3.1.2 Win32 NuGets from their official HTTPS URLs and installs the validated
pair under the selected Racket user's library directory, `skia-upstream-1`.
This directory is outside every Racket package. Setup, imports, tests and first
render never initiate acquisition. CI stages those two inputs before denying
network access, then exercises the same installer with its explicit offline
cache option. Built/source/binary-library packages and uploaded artifacts must
exclude both DLLs and raw NuGets. Reinstalling on a fresh Windows environment
requires the explicit installer again. Retain every Windows execution gate.

The public catalog must be able to build the registered manuals and exercise
a meaningful CPU test suite. A source checkout, the installed source package,
and the catalog's rebuilt package must all retain correct native discovery.

Recommended first-release decisions:

| Area | Decision |
|---|---|
| User-facing package | `skia`, with the existing single collection named `skia`. |
| Source organization | Keep the existing collection layout; no simultaneous `skia-lib`/`skia-doc` split. |
| Native packages | macOS and Linux packages each contain both pinned libraries; Windows uses direct upstream acquisition. |
| Native pins | Retain SkiaSharp 3.119.1 and HarfBuzzSharp 8.3.1.2. Do not combine publication with a native ABI upgrade. |
| Initial targets | macOS ARM64 and x86-64, Windows x86-64, glibc Linux x86-64 including the catalog's `natipkg` configuration. |
| Linux ARM64 | Prepared extension, but not advertised or selected automatically until a real execution lane passes. |
| Native installation | macOS/Linux use Racket-managed foreign-library installation; Windows uses an explicit owned pair outside package contents. Both use private generation-qualified directories. |
| Native acquisition | Locked maintainer/CI preparation for macOS/Linux; explicit user NuGet installer on Windows. No setup-time or runtime downloader. |
| Documentation | Keep executable CPU figures, supplied by declared dependencies; eliminate undeclared font/environment assumptions. |
| Verification | Add catalog-style source and built-package testing; retain existing full native/GPU/GUI acceptance. |
| Publication | An explicitly approved, separate operation after candidate validation. |

This is a packaging release, not a 1.0 declaration or a new graphics feature
milestone. Propose source version `0.79` to distinguish the distribution change
from the current `0.78`; finalize the number before freezing the candidate.

## 2. Current state and the gaps this plan closes

| Existing component | Evidence and implementation implication |
|---|---|
| [`info.rkt`](../info.rkt) | Collection `skia`, version `0.78`, Racket 8.18 / draw-lib 1.22 minima, MIT metadata, manuals, and test exclusions already exist. Native package dependencies do not. |
| [`private/native-default-version.txt`](../private/native-default-version.txt) | Authoritative default SkiaSharp pin is 3.119.1. Preserve it. |
| [`private/native-loader.rkt`](../private/native-loader.rkt) | Lazy Skia loading tries an override, package-relative `native/<rid>`, then a bare library name. Package-managed selection and provenance need an explicit new route. |
| [`private/harfbuzz-native.rkt`](../private/harfbuzz-native.rkt) | Lazy HarfBuzzSharp loader includes Linux symbol-isolation behavior. Preserve that isolation when changing path discovery. |
| [`tools/install-native.sh`](../tools/install-native.sh), [`tools/install-harfbuzz.sh`](../tools/install-harfbuzz.sh), [`tools/install-native-windows.py`](../tools/install-native-windows.py) | Establish asset IDs, members, pins, and some validation. They remain developer/offline escape hatches, not package setup hooks. |
| [`tools/ci.py`](../tools/ci.py) | Installs a source archive with `--no-setup`, runs no-native checks, explicitly installs native assets, then uses `--no-docs`. This does not verify the intended catalog installation. |
| [`tools/ci-package-smoke.rkt`](../tools/ci-package-smoke.rkt) | Useful raster/PNG/identity probe. Its path assumptions need mode-specific handling for native dependency packages. |
| [`scribblings/quick/eval.rkt`](../scribblings/quick/eval.rkt) | Registered documentation renders live Skia figures. Missing native libraries are a documentation-build failure, not just a runtime inconvenience. |
| [Documentation workflow](../.github/workflows/pages.yml) | Builds manuals after manually installing natives and OS/font packages. Audit those assumptions for catalog builds. |
| [`tests/native-test.rkt`](../tests/native-test.rkt) | Its `test` submodule requires both native libraries. Standard package test discovery must be exercised, not replaced by `run-tests.rkt --pure`. |
| [`tools/release_candidate.py`](../tools/release_candidate.py) | Existing source-archive and release evidence checks deliberately exclude native files. Preserve that source guarantee and add separate native artifacts. |
| [`NOTICE.md`](../NOTICE.md) | Current notice describes a source-only distribution. Native redistribution needs a real component/license inventory. |

The earlier readiness check confirmed that a source-only core import succeeds
with invalid native-library overrides, while instantiating the Quick manual
fails for missing Skia. It did not establish a full catalog build or current
release-matrix success.

## 3. Package family and platform selection

### 3.1 Proposed packages

Each native package supplies the pair of libraries as one tested unit. This
avoids independently updating SkiaSharp and HarfBuzzSharp to an unreviewed
combination. It does not merge their licenses or claim they share one ABI.

| Package | Dependency selector | Native inputs | First release |
|---|---|---|---|
| `skia` | All platforms; useful native execution only where qualified | Racket source and current manuals/examples | Required |
| `skia-native-macos-1` | `#rx"^(aarch64|x86_64)-macosx$"` | The `osx` members from the two macOS NuGet packages | Required on both architectures |
| Windows direct installer | Windows x86-64 CS only; no native package dependency | The two locked `win-x64` members acquired from NuGet by the user | Required explicit preparation |
| `skia-native-x86_64-linux-1` | `#rx"^x86_64-linux(-natipkg)?$"` | The two `linux-x64` shared libraries | Required in ordinary and catalog environments |
| `skia-native-aarch64-linux-1` | `#rx"^aarch64-linux(-natipkg)?$"` | The two `linux-arm64` shared libraries | Deferred until execution-qualified |

The locally installed macOS assets for the pinned versions contain both
`x86_64` and `arm64` slices, as checked with `lipo`. Verify the freshly acquired
release inputs too; do not use a developer's existing binaries as release
inputs. A universal macOS package still needs two runtime test lanes.

Use Racket's target platform matching, not `uname`, Python's architecture, or
the host's CPU. Test cross-target metadata selection independently from native
execution. `#:platform` dependencies and `install-platform` guards have
different jobs; generate and verify both. [Platform specifications](https://docs.racket-lang.org/raco/matching-platform.html)

The anchored Linux selector intentionally includes `natipkg`. It is not a
libc compatibility detector: some unsupported systems may report the same
platform string. Advertise glibc requirements and fail clearly on unsupported
runtime combinations; do not claim musl support from a regex match.

### 3.2 Main-package metadata

Append entries of this form to the existing dependency list:

```racket
("skia-native-macos-1"
 #:version "1.0" #:platform #rx"^(aarch64|x86_64)-macosx$")
("skia-native-x86_64-linux-1"
 #:version "1.0" #:platform #rx"^x86_64-linux(-natipkg)?$")
```

These are fragments inside the dependency datum, not standalone expressions.
Do not add the ARM64 Linux dependency until its release gate is satisfied.
Use catalog package names, not NuGet URLs or unpublished developer paths.
Windows has no native package dependency. Keep its two upstream archives in
the input lock for the direct installer, and explicitly exclude that target
from native ZIP generation and the distributable artifact manifest.

Racket's dependency version is a lower bound, not an exact upstream asset pin.
The `-1` package family, reviewed lock manifest, loader checks, and release
evidence carry the stronger compatibility policy. [Package metadata](https://docs.racket-lang.org/pkg/metadata.html)

Keep these distinct:

- Source package version: proposed `0.79`.
- Native Racket package version: initially `1.0`, incremented for compatible
  packaging corrections within the generation.
- Upstream asset versions: `3.119.1` and `8.3.1.2`, recorded as upstream data.

Do not copy `3.119.1` into Racket's `version` field: its minor component exceeds
Racket's permitted range. A changed upstream pair requires a new reviewed
generation/package family unless a separately approved compatibility policy
justifies otherwise. [Package versions](https://docs.racket-lang.org/pkg/Package_Concepts.html)

Also shorten `pkg-desc`, add `pkg-authors`, retain the existing public module
paths, and audit runtime/build dependencies without speculative removals.
The source still exposes GUI modules and the example-copying command; moving
dependencies or files must not break them.

## 4. Native package layout and installation

### 4.1 Use data-only packages with unique collections

Generate each native package outside the source tree, for example:

```text
skia-native-x86_64-linux-1/
  info.rkt
  README.md
  licenses/
    ...reviewed upstream/component license and notice files...
  skia-native-1/
    libSkiaSharp.so
    libHarfBuzzSharp.so
    manifest.json
    ...only explicitly approved private support libraries/data...
```

The native package's single collection is its own package name, never `skia`.
It exports no duplicate Skia modules, has no installer program, and contains
no compiled Racket bytecode. Its root `info.rkt` controls installation of the
`skia-native-1` directory through `copy-foreign-libs`.

Conceptual metadata for the Linux package:

```racket
#lang info
(define collection "skia-native-x86_64-linux-1")
(define version "1.0")
(define deps '(("base" #:version "8.18")))
(define install-platform #rx"^x86_64-linux(-natipkg)?$")
(define copy-foreign-libs '("skia-native-1"))
(define compile-omit-paths '("skia-native-1"))
(define test-omit-paths '("skia-native-1"))
(define distribution-preference 'binary)
;; Add audited transitive dependencies, authors, description, license metadata,
;; and the verified keep-file declarations before publishing this template.
```

This deliberately incomplete template must not be published unchanged. The
license field depends on the redistribution inventory; the main package's MIT
declaration must not be copied blindly to a mixed native payload.

Racket supports installing foreign-library payloads under its managed library
directories. The inspected setup implementations also support copying a
directory as one managed entry. Verify that behavior, upgrade/removal receipts,
and package stripping on the supported minimum before relying on the layout.
[Foreign-library installation](https://docs.racket-lang.org/raco/setup-info.html)

### 4.2 Why an isolated native directory

Install into `<Racket library directory>/skia-native-1/`, preserving upstream
library basenames. The loader will construct absolute filenames there.

This avoids placing this project's SkiaSharp/HarfBuzzSharp files or support
libraries directly into the global library-name namespace. A future
`skia-native-2` can coexist on disk without overwriting generation 1. It does
not promise that incompatible versions can safely coexist in one process.

Only the matching native package may own this directory in a given target
installation. Detect overlapping package selectors and foreign-file ownership
conflicts in preparation/tests. Never resolve a conflict with `--force` or by
deleting another package's files. The same selectors must produce exactly one
native package for each automatic macOS/Linux target and none for Windows or
explicitly excluded targets.

Keep filenames and library bytes unmodified when possible. Directory copying
does not magically repair ELF dependency paths, Mach-O install names, signatures,
or Windows dependent-DLL search. Any necessary transformation must be explicit,
reproducible, recorded, and requalified under Section 6.

### 4.3 Source, built, and binary-library forms

Use native archives containing the data and metadata, not a `.zo` bundle tied
to the preparation machine's Racket version. `distribution-preference` is a
preference, not proof of compatibility with every packaging mode.

Derive/test `source-keep-files`, `binary-keep-files`, and
`binary-lib-keep-files` as needed so that native payloads, manifests, and
required notices survive conversion. Racket's stripping process can turn
copy metadata into move metadata and recover installed files when repackaging.
Do not rely on the original source copy still existing. [Package forms and stripping](https://docs.racket-lang.org/pkg/strip.html)

Required lifecycle proof:

1. Install each native package in a disposable user installation.
2. Build/package the source into built and binary-library forms using Racket's
   tools and the target Racket version.
3. Install those forms into a second, clean environment after removing access
   to the first environment and staging tree.
4. Verify payload, notices, loader paths, and actual rendering/shaping.
5. Update and remove the packages and check managed-directory ownership/cleanup.

For Windows, test the direct installer's paired replacement/rollback and
explicit removal instead of native-package ownership. Test both user and
installation scopes in disposable runtimes. Rebuilt Racket packages must
contain no downloaded DLLs or NuGets, preserve the installer and lock, and work
after a fresh explicit acquisition. Never copy the download directory into a
candidate, built package or evidence upload.

Include user-specific and installation-wide scope tests in disposable
environments. Do not require users to write into the installed source package.

## 5. Locked acquisition and reproducible artifact generation

### 5.1 One reviewed native-distribution manifest

Add a source-controlled manifest, suggested path
`packaging/native-assets.json`, containing:

- Schema and native-distribution generation.
- Target selectors, supported VM/word-size qualifications, and package names.
- Native Racket package versions and expected upstream version pair.
- Exact NuGet package IDs, HTTPS URLs, and archive members for each target.
- Expected archive SHA-256, expected unmodified member SHA-256, and sizes.
- Required architecture slices/machine types and observed deployment baselines.
- License/notice sources, their hashes, and per-component license identifiers.
- Approved transitive dependencies or private support files, if any.
- Any transformation recipe and hashes before/after transformation.

Do not put guessed or automatically accepted hashes into this manifest. A
maintainer reviews the initial provenance and locks the acquired inputs; future
builds check those expectations. Recording a hash after downloading does not,
by itself, authenticate the upstream source.

Reference the current default-version file and existing HarfBuzz pin in drift
checks. Avoid scattering another independent set of version constants among
the loader, installers, metadata templates, workflow, and documentation.

### 5.2 Separate network preparation from offline packaging

Suggested tools:

- `tools/prepare-native-packages.py`: fetch or accept local upstream archives,
  validate the lock manifest, and prepare a verified input cache.
- `tools/build-native-packages.py`: network-free extraction, metadata generation,
  deterministic package assembly, and receipt generation.
- `tools/test-native-packages.py`: adversarial archive/metadata/selector tests.

Reuse carefully the Windows installer's bounded archive and PE validation.
The Unix scripts provide member-selection knowledge, but their current
post-download hash recording is not sufficient for locked release assembly.

Required checks include duplicate archive entries, absolute/traversal paths,
case-insensitive collisions, symlinks where not explicitly allowed, zip bombs,
oversized metadata/members, invalid XML entity declarations, wrong package ID
or version, missing notices, empty libraries, wrong machine type, and hash
mismatches. Extract only allowlisted members; do not execute the inputs during
extraction. Native inspection/execution belongs to the qualified host jobs.

Use deterministic member order, normalized metadata/modes/timestamps, and a
specified archive algorithm. Build twice from the same locked inputs and
compare output bytes. If compression-tool variation is material, pin that tool
or use a deterministic stored ZIP rather than asserting reproducibility.

Generate for every distributable:

- Its package ZIP and Racket-compatible `.CHECKSUM` companion.
- A separate SHA-256 digest for the project release manifest.
- A receipt linking source commit, generator version, lock digest, upstream
  hashes, payload hashes, package metadata, and final archive digest.

Racket archive/catalog checksums use SHA-1; do not put a SHA-256 value into
`.CHECKSUM`. The additional SHA-256 is the project's stronger integrity record,
not a replacement for the package protocol. [Package checksums](https://docs.racket-lang.org/pkg/Package_Concepts.html)

Keep downloaded NuGet archives in the maintainer evidence/cache area, not in
each user's installed native package. Ship the actual required license files
and notices explicitly instead of relying on an opaque retained archive.

## 6. Transitive libraries, fonts, and redistribution review

This is an early release gate, not final cleanup after publishing packages.

### 6.1 Linux ordinary and `natipkg` environments

Inspect the pinned ELF binaries with tools such as `readelf` to enumerate
`DT_NEEDED`, RPATH/RUNPATH, architecture, and required GLIBC/GLIBCXX symbols.
Run load tests in controlled environments with known library inventories.

The current Linux asset is fontconfig-enabled, intentionally supporting the
public system-font APIs. Do not silently switch to a no-dependencies variant
if that removes advertised font functionality.

For each non-baseline dependency, choose and record one route:

1. A compatible existing catalog native package, declared directly where
   needed, with proven dynamic-loader resolution.
2. An explicitly licensed and qualified private support library in the
   isolated native directory.
3. A documented OS baseline dependency on ordinary Linux, with a separate
   declared-package solution for the catalog environment.

The preferred order is reuse, then a minimal private support set. Do not
redistribute glibc or an entire Linux userspace. Do not assume that because
`draw-lib` is installed, its chosen fontconfig/FreeType versions are ABI- and
loader-compatible with SkiaSharp. Native packages must be independently
installable; dependencies must not accidentally rely on the main Skia package
being installed first. Avoid cycles.

The same Linux native archive may serve ordinary and `natipkg` installations
only after both pass. Conditional support dependencies can differ. If different
payloads are genuinely required, introduce an explicit `natipkg` package and
disjoint selectors through a reviewed amendment, not an invisible runtime
download or a misleading support claim.

The package service documents `x86_64-linux-natipkg` and expects missing native
libraries to be supplied through packages. Its build VM is isolated from the
network. Use the real target configuration in qualification; merely setting an
environment variable or unit-testing a platform string is not equivalent.
[Package-build native-library conventions](https://pkg-build.racket-lang.org/about.html)

### 6.2 macOS and Windows

- macOS: inspect both universal slices, minimum OS/load commands, linked
  frameworks, install names, and signatures. Test the actually downloaded
  package path and managed-directory layout on Intel and ARM64. Preserve
  signatures where possible; any re-signing or binary modification needs a
  documented recipe and verification. Do not claim notarization without it.
- Windows: validate AMD64 PE identity and import tables; determine whether a
  separately installed runtime DLL is required. Test outside a developer
  shell with a clean PATH. Any redistributable support DLL needs an approved
  package/redistribution route. Do not change machine PATH or require an
  administrator installer as a hidden normal-install step.
  The explicit direct installer owns `skia-upstream-1`, preserves original and
  collected component notices and records the exact NuGet/member hashes. Its
  user scope needs no administrator privileges. Upstream terms still apply to
  use and any later redistribution; this exception does not approve bundling
  Windows DLLs in our releases or CI artifacts.
- Preserve the HarfBuzzSharp isolation used to coexist with GTK/Pango. Test
  both load orders and actual Draw and Skia text on Linux; resolving a symbol
  is not sufficient to prove that dependent relocations used the intended ABI.

### 6.3 Fonts and notices

Inventory fonts actually required by CPU documentation and test fixtures.
Remove assumptions about fonts installed by the GitHub Pages workflow. Use
ordinary portable family fallback where appropriate, or a small legally
redistributable fixture/declared font package when a specific face is essential.
Do not download fonts during setup or copy an unreviewed developer font folder.
Any newly shipped font changes the current no-font-files notice and needs its
own license record.

Produce a component/license inventory for Skia, SkiaSharp, HarfBuzzSharp,
embedded third-party code, support libraries, and any fonts/data. Collect the
required license/notice texts from the pinned upstream release or its exact
source revision. If the redistribution obligations cannot be established,
stop that payload's release for maintainer review. This plan is not a legal
determination and does not grant rights to upstream material.

## 7. Loader integration and installed provenance

### 7.1 Discovery policy

Introduce a small shared private discovery helper, suggested
`private/native-package-paths.rkt`, used by both loaders. It should compute
platform/package expectations and inspect Racket's configured library search
directories without loading either native library.

Resolve each library on first use in this order:

1. Its explicit environment override, exclusively. Invalid overrides remain
   errors; do not retry another installation.
2. The selected package-managed `skia-native-1` directory in Racket's library
   search order, using an absolute library filename.
3. The existing package-relative `native/<rid>` developer installation, only
   if no managed generation is present.
4. The existing system-library fallback, only if neither managed nor local
   installation is selected.

On Windows, step 2 selects the explicitly installed `skia-upstream-1` pair in
Racket's library search order and reports origin `upstream-download`, with the
absolute download directory and acquisition manifest. It does not claim a
Racket native dependency package owns those files. Missing Windows data in an
installed package reports the explicit installer command; a selected broken
pair fails without borrowing from another scope or a host DLL.

Choose one managed generation directory as a pair: do not load Skia from one
scope and HarfBuzz from another just because one file is missing. A present but
incomplete, mismatched, corrupt, or unloadable managed payload is an actionable
error, not permission to silently use a system library. Test user/install-wide
shadowing explicitly. Separate explicit overrides remain intentional escape
hatches and must be reported as such.

This adds managed-package precedence over legacy developer files. Document the
change and tell developers to use the existing explicit overrides when they
intend to test a local build. Do not infer developer intent from the working
directory or a `.git` directory.

Retain lazy imports, ABI/version/symbol checks, ownership rules, and current
unsupported-backend behavior. The new path layer must not create contexts,
probe fonts, access the network, or initialize `racket/gui/base` during require.
On an unqualified platform, imports/pure utilities should retain their present
behavior; native use should explain the support boundary and explicit override
route without falsely promising an automatic binary.

### 7.2 Provenance and diagnostics

Extend private diagnostics and the installed smoke to report:

- Source package version/commit and native distribution generation.
- Interpreter platform, architecture, VM, and pointer width.
- Selected origin: managed package, explicit override, legacy local, or system.
- Absolute selected library paths, asset versions, observed ABI versions, and
  loaded-file digests gathered by the verification tool.
- Manifest identity and any permitted installation transformations.

Do not label a bare `ffi-lib` search string as the proven resolved pathname.
For the managed route, load the explicit path and verify it lies in the
selected managed directory. If Racket or the preparation recipe rewrites
library bytes, distinguish original, packaged, and installed hashes and prove
the authorized transformation; do not weaken digest checks globally.

Keep normal import fast; release/doctor validation may hash the full files.
Hash checks are integrity/provenance evidence, not a security boundary against
an attacker who can modify both a library and its manifest.

The existing CI verifier requires libraries inside the installed source tree.
Retain that rule for the explicit legacy-installer test mode; add a separate
managed-package mode with equally strict directory/package checks. Do not
change the condition to accept any library found anywhere on the host.

## 8. Documentation and standard package tests

### 8.1 Documentation must build through normal setup

The catalog lane must run ordinary installation/setup with documentation
enabled. Do not use `--no-docs`, hidden manual downloads, or a pre-populated
checkout `native/` directory to obtain a green result.
The documented Windows exception runs `pkg install --no-setup`, the explicit
upstream installer, then full `raco setup --pkgs skia`. Its private library
directory is outside the source package. This explicit sequence and its raw
upstream input receipts must be visible in Windows evidence.

Audit every entry in `scribblings` and their transitive support modules for:

- Native initialization before dependency foreign-library installation.
- Missing font assumptions and network/file downloads.
- GUI windows, GPU contexts, or hardware-only demonstration code.
- Generated images written into read-only installed source directories.
- Missing fixture/source files, private working-directory assumptions, and
  dependencies available only in a full developer distribution.
- Broken references, unresolved bindings, duplicate manual output names, and
  source-copy links affected by packaging modes.

Keep executable CPU figures where feasible. If a specific example cannot run
in the catalog environment, provide a checked static figure/recorded result
with explicit provenance and execute its source in dedicated CI. Do not render
an error placeholder or silently omit the example and call the manual passed.
GPU examples must not require a GPU merely to build their documentation.

On macOS/Linux, build native packages and the main package together through normal dependency
installation. Test that foreign libraries are present when Scribble evaluation
first needs them; do not assume setup phase ordering from a manual test.

### 8.2 Meaningful, bounded catalog tests

Add `tests/catalog-package-test.rkt` with deterministic CPU coverage of:

- Managed-library selection and ABI checks with all overrides removed.
- A small asymmetric RGBA render, PNG encode/decode, and exact interior pixels.
- Real HarfBuzz shaping with a known available/licensed test font.
- A small path/picture operation and PDF/SVG output smoke.
- Bitmap/pict/Racket Draw integration without a display.
- Ordinary resource cleanup and invalid argument/state handling.

Measure the actual `raco test --drdr --package skia` traversal. It discovers
more than the project's custom aggregate runner, including test submodules and
modules without one. Audit runnable examples/tools/manuals accordingly.

Use explicit, reviewed exclusions for hardware-dependent, environment-specific,
or expensive developer checks, and keep those checks required in their own CI
lanes. Do not omit the whole test tree or suppress missing-native failures on a
supported platform. Pure/core regressions and the installed CPU smoke remain
mandatory. A source/no-native development check is a different declared mode.

The service currently documents a 90-second default per test and a 10-minute
overall testing limit. Target substantial headroom and report timings. Do not
rely on raising individual timeouts to evade the overall limit.
[Build-service testing limits](https://pkg-build.racket-lang.org/about.html)

No test may depend on Git history, an upstream download, a developer's installed
package scope, or a writable source directory. Tests that intentionally produce
stderr need a reviewed local configuration, not a global ignore-errors rule.

## 9. Catalog-equivalent validation pipeline

### 9.1 Candidate staging catalog

Generate a disposable local/file-served catalog containing the exact candidate
`skia` archive and native archives, with source URLs, package checksums, and
dependency metadata. Put it before an explicitly controlled official catalog
snapshot for standard Racket dependencies. Never write into the user's normal
catalog configuration.

All workflows installing candidate source must use this staging catalog or its
equivalent cached snapshot. Otherwise newly added native dependency names will
fail before public registration, or resolve to an older published native
package. Update common setup code used by CI, Acceptance, and API inventory;
do not rely on registering unfinished packages to make development CI work.

Separate two environments:

- Acquisition/staging: network enabled; fetch and verify all declared packages.
- Execution: all inputs available from a local snapshot/cache; outbound network
  denied while install/setup code, documentation, tests, and rendering run.

The source and native package digests must be identical in both. An installation
with a completely empty package cache and no network is not the intended test:
the build service stages packages before isolated execution too.
Windows also stages its two raw upstream NuGets separately before isolation.
They are acquisition inputs, never catalog sources or distributable packages.

### 9.2 Required matrix

| Lane | Required proof |
|---|---|
| Metadata/generator | Selector truth table, malformed inputs, archive reproducibility, checksums, license completeness, no source/native mixing. |
| Linux x86-64 ordinary | Clean package install and discovery in a documented glibc baseline. No preinstalled SkiaSharp/HarfBuzzSharp. |
| Linux x86-64 `natipkg` | Actual package-build target configuration; transitive dependency resolution, full manuals, catalog-style tests, built-package round trip. |
| Minimum Racket 8.18 | Source/native install, directory copy/remove behavior, public imports, CPU smoke, and documentation compatibility. |
| Current released Racket | Same catalog path on the release version selected when the candidate is frozen. Do not equate a development executable with the release. |
| macOS ARM64 | Candidate universal payload, managed paths, rendering/shaping, clean-user install/update/remove. |
| macOS x86-64 | Independent execution of the other universal slice with the same package digest. |
| Windows x86-64 | Direct pinned NuGet preparation, clean PATH/runtime dependencies, paired upstream DLLs, full manuals/DrDr/rendering/shaping offline, scope/update/rollback/removal, and DLL/NuGet exclusion from every rebuilt package and upload. |
| No-native developer mode | Imports and pure tests with deliberate invalid overrides; no native/GUI initialization. |
| Optional Linux ARM64 | Real ARM64 execution and all native-package claims before adding this target to release metadata. |

Run the initial ordinary Linux and `natipkg` lanes before expanding the rest:
they are most likely to uncover hidden fontconfig/library assumptions. Do not
substitute an Ubuntu runner with many preinstalled libraries for the actual
catalog target. Use the documented pkg-build tooling or a faithfully configured
target installation, and retain its configuration. [Pkg-build](https://docs.racket-lang.org/pkg-build/index.html)

### 9.3 Standard commands and environment invariants

Within a disposable user home/addon tree and staged catalog, the relevant
commands include:

```sh
raco pkg install --auto --batch skia
raco setup --check-pkg-deps --pkgs skia
raco test --drdr --package skia
racket -l skia/tools/catalog-smoke
```

`tools/catalog-smoke.rkt` is proposed new tooling; the other commands are
existing Racket entry points. The validator must select one exact Racket
executable and use it for every associated `raco` invocation.

Run from outside checkout/staging/installation directories. Clear native,
collection, and dynamic-library overrides; retain only the deliberately staged
package environment. Record loaded module paths. Prove that no checkout
`native/`, `compiled/`, or generated documentation directory supplied the result.

The full manual build must also run at least once from source with no compiled
cache. Then separately verify installation from built and binary-library
packages generated by the selected Racket version. Test source stripping,
notice retention, and the advertised example-copy command; if binary-library
mode omits example source, document and diagnose that limitation explicitly.

### 9.4 Negative and lifecycle cases

Automate failures for missing native dependencies, wrong architecture, wrong
ABI, wrong asset pair, missing member/manifest, corrupt digest, invalid override,
partial shadowing between user and installation scopes, and failed dependent
library loading. Missing managed payload must not be hidden by a host library.

Also test:

- Package directories and user paths containing spaces/non-ASCII characters.
- Source directory read-only after setup, with first rendering still working.
- Repeated setup; compatible native-package update; explicit rollback rehearsal.
- Removal after closing all rendering processes, retaining unrelated libraries.
- A user-scoped native dependency shadowing an installation-wide one.
- A changed working directory and removal of original downloaded archives.
- Both GTK/Pango-first and Skia-first text rendering orders.
- A foreign-target native package building as inert data without executing its
  binaries on the Linux catalog builder.

Never run destructive package removal or scope experiments in the maintainer's
ordinary Racket installation. Use disposable environments with exact targets.

## 10. Integration with the existing release machinery

### 10.1 Preserve existing source and execution guarantees

Do not weaken the source archive's native-binary exclusion. Templates, lock
data, generators, and tests are source; generated native packages live under
ignored output/staging directories and are separate release artifacts.

Add a catalog-packaging reusable/manual workflow or an equivalent group within
the existing CI. The release candidate must require its result alongside the
current CI, Acceptance, and API inventory gates. Keep publication permissions
out of pull-request/test workflows.

Review and update the frozen workflow graph, source/release-scope ledgers,
package-version assertions, and matrix documentation intentionally. In
particular, `tools/release_candidate.py` currently asserts version `0.78`.
Do not remove that check merely to avoid deciding the new release baseline.

Keep the old explicit-installer lanes as developer-route regression coverage.
Where necessary, set explicit local-library overrides only in those lanes.
The catalog lane must use no such overrides and must prove dependency-package
discovery on macOS/Linux and explicit upstream-pair discovery on Windows.
Record these modes separately. Windows feature/developer lanes pass an explicit
checkout root to preserve their existing local-library containment checks.

### 10.2 Release artifact set

The final candidate evidence should identify:

- One exact source commit and source package ZIP/digests.
- One exact lock manifest and generator identity.
- All native ZIPs, their Racket checksums, SHA-256 values, and payload receipts.
- The staged catalog snapshot and exact dependency graph.
- Target/Racket identities and package inventories for every required lane.
- Full setup/doc/test logs, loaded-library paths/digests, render/text checks,
  and source-to-built round-trip results.
- Redistribution/notice review and supported-platform statement.

The existing release aggregator's artifact size/count limits need explicit
review: native archives are substantial and should not be accidentally embedded
multiple times inside every evidence ZIP. Do not respond by disabling all
download/decompression limits. Bound the native artifact set separately.

A final receipt can say `catalog_candidate_validated: true` only after all
required lanes complete at the candidate identity. Keep publication approval
and overall project/1.0 readiness separate. Preserve failures and partial
reports honestly.

## 11. Implementation work packages

| Stage | Deliverables | Exit condition |
|---|---|---|
| A. Audit and prototype | Confirm names/pins/platforms; inventory transitive libraries and notices; prove managed subdirectory copy/strip/remove on minimum/current Racket. | No unresolved feasibility issue hidden in the metadata template. |
| B. Lock and generate | Reviewed native lock, offline deterministic builder, archive/checksum/selector tests, package templates. | Each native ZIP rebuilds reproducibly from known inputs; no unsigned-off payload. |
| C. Integrate loaders | Shared private path discovery, managed pair selection, diagnostics, shadowing/error tests, updated doctor/smoke. | Actual package-managed rendering/shaping; old explicit overrides and isolation preserved. |
| D. Integrate metadata/docs/tests | Native dependencies, concise metadata, font/doc audit, bounded catalog suite, installation instructions. | Normal dependency-driven setup builds every manual and runs meaningful CPU tests. |
| E. Qualify distribution | Staging catalog, offline execution, platform/minimum/current matrix, built/binary-library lifecycle tests. | macOS/Linux pass dependency-driven setup; Windows passes the explicit upstream installer exception with no downloaded binary in a rebuilt package. |
| F. Integrate release evidence | Required catalog gate, reviewed frozen policy/version changes, immutable artifact manifest, publication runbook. | Complete candidate receipt, checksums, notices, and reproducible commands ready for maintainer review. |
| G. Publish and observe | Approved public assets, native catalog entries first, main entry last, actual server build inspection. | Public installation and server results verified; no success claim based only on local CI. |

Suggested new/changed files during implementation:

- `packaging/native-assets.json`: locked inputs and distribution policy.
- `packaging/templates/`: native metadata/README templates; store templates with
  non-module suffixes where appropriate so root collection setup does not
  mistake them for nested installable packages.
- `private/native-package-paths.rkt` plus the two existing loaders: discovery.
- `tools/prepare-native-packages.py`, `tools/build-native-packages.py`,
  `tools/test-native-packages.py`: preparation and offline generation.
- `tools/validate-catalog-package.py`, `tools/catalog-smoke.rkt`, and validator
  regression tests: real installs, logs, provenance, and explicit failure modes.
- `tests/native-package-pure-test.rkt`, `tests/catalog-package-test.rkt`:
  pure selection contracts and installed CPU checks.
- `info.rkt`, affected documentation/evaluators, `README.md`, `native/README.md`,
  `NOTICE.md`, `docs/CI.md`, and `docs/PORTABILITY.md`.
- `docs/PACKAGE-PUBLICATION.md`: operator instructions, platform support,
  artifact identities, updates/rollback, and catalog maintenance.
- Relevant CI/release workflows and reviewed policy files.

Prefer extending existing manifest/archive and validation utilities over a
second unrelated release framework. Any helper refactoring should preserve the
existing installer tests and failure semantics.

## 12. Publication runbook and authority boundary

Implementation may prepare and validate files locally or in authorized test
CI. It must not automatically create public releases, tags, repositories,
catalog registrations, or change branch-protection settings. Those actions
require a separate explicit maintainer go-ahead.

After that approval:

1. Confirm catalog name availability, owner account, support contact, source
   version, and native generation. Resolve any naming collision before upload.
2. Freeze/tag the exact validated source commit. Retain native input locks and
   final artifacts; do not rebuild different bytes during the upload step.
3. Publish immutable, anonymously downloadable HTTPS release assets: `skia.zip`,
   each native package ZIP, `.CHECKSUM` files, SHA-256 manifest, notices, and
   durable release evidence. Use a release-specific URL directory.
4. Verify every asset URL, redirect, archive, and digest without authentication.
   Private/draft release assets and expiring Actions artifact URLs are not
   suitable catalog sources.
5. Register each native package first, pointing to its immutable archive.
   Verify catalog metadata/dependencies and allow its build to complete.
6. Register `skia` last, with the exact source archive, a short description,
   useful tags, owner/contact information, and documentation links. It must
   depend only on already available catalog entries.
7. Test `raco pkg install --auto skia` from a new ordinary user environment
   using the public catalog, without the staging catalog.
8. Inspect the actual package-build install, documentation, dependency, and
   test results. Check the hosted manuals and representative figures.
9. Test installation from the service's built-package catalog too, with the
   appropriate Racket version. Verify that native payloads survived repackaging.
10. Record public catalog checksums, source URLs, observed build status, and
    successful fresh-install evidence. Only then call publication complete.

The catalog points to package sources and discovers their updates; registration
is not a replacement for hosting release artifacts. [Sharing packages](https://docs.racket-lang.org/pkg/getting-started.html)

For this first release, recommend immutable release-archive URLs for both source
and native packages. Update catalog pointers deliberately for subsequent
releases. Do not point the stable package at the development branch or a
mutable `latest` asset. Git tags are a valid alternative for source, but choose
one release mechanism and document its checksum semantics consistently.

### Updates and rollback

- Never replace bytes at an already published immutable URL or move a release
  tag. Publish a new artifact/revision and update the catalog entry.
- Compatible packaging corrections can advance native package version within
  generation 1; changing the locked upstream pair requires explicit review and
  normally a new generation with a different install directory.
- Publish/validate newly required native entries before updating the main
  package to depend on them. Keep old generations available for older clients.
- Rehearse a rollback to a complete compatible source/native set. A dependency
  lower bound can prevent installing an older native revision; do not promise
  that merely reversing one URL will downgrade every installed dependency.
- Stop rendering processes before native replacement, especially on Windows.
  Use package-manager update/removal, not ad hoc deletion of library files.
- Retain permanent candidate evidence rather than depending on the existing
  short-lived Actions artifact retention period.

## 13. Definition of done

Implementation-ready candidate:

- [ ] Source package keeps the existing public collection/API and supported minima.
- [ ] Native generation/pins, selectors, artifact hashes, and notices are reviewed.
- [ ] No binary or compiled cache enters the source-only archive.
- [ ] Every native package installs independently and only on its intended target.
- [ ] Native-directory copy/strip/update/remove works on minimum/current Racket.
- [ ] Managed loading uses explicit paths and preserves HarfBuzz isolation.
- [ ] Missing/corrupt selected native payloads fail without hidden host fallback.
- [ ] macOS/Linux ordinary installation requires no native-install script or custom environment.
- [ ] Windows explicitly acquires both pinned NuGets; full setup/tests/rendering remain offline afterward.
- [ ] No Windows DLL/NuGet/native package enters release assets, CI evidence or rebuilt packages.
- [ ] Offline setup builds all registered manuals with declared inputs.
- [ ] Catalog-style tests have meaningful CPU coverage and timing headroom.
- [ ] Source, built, and binary-library distribution paths are exercised.
- [ ] Every advertised target has real installation/render/shaping evidence.
- [ ] Existing full CI/Acceptance/API gates remain required and pass.
- [ ] Candidate evidence names the exact archives to publish; publication is still pending.

Publication complete, after separate approval:

- [ ] Durable public assets match validated digests and carry required notices.
- [ ] Native catalog entries precede the main package and resolve correctly.
- [ ] Fresh public-catalog installation works without staging configuration.
- [ ] Actual catalog build, dependencies, manuals, and tests have been inspected.
- [ ] Public built-package installation and native discovery are verified.
- [ ] Release/support/update/rollback information is recorded for maintainers.

Unresolved at planning time: exact transitive Linux/Windows support dependencies,
the completed native license inventory, minimum OS/libc baselines, final catalog
name availability, and any documentation font fixtures. Stage A resolves these;
do not turn them into optimistic claims or hide them behind a green source-only
check. Linux ARM64 remains a separate expansion unless fully qualified.

## 14. Prompt for the implementation chat

Copy the following prompt into the implementation chat:

```text
Implement catalog-ready packaging for skia-for-racket according to
plans/skia-package-catalog-publication.md. Read the complete plan and applicable
repository instructions first, inspect the current checkout, and preserve
unrelated work. This task is implementation and validation, not authorization
to publish externally.

The intended macOS/Linux installation is `raco pkg install --auto skia`, followed
by working CPU rendering and HarfBuzz shaping with no native-install script.
Windows uses the explicit direct NuGet installer exception in Section 1; retain
its complete execution gates and exclude downloaded Windows bytes from all
distributable and rebuilt packages. Keep
the existing single `skia` collection and public API; do not simultaneously
split the source/docs packages, add graphics features, or upgrade the pinned
SkiaSharp 3.119.1 / HarfBuzzSharp 8.3.1.2 pair.

Work through stages A-F of the plan. Start with the Linux/natipkg transitive
dependency and license audit and a minimal native-directory lifecycle prototype
on supported Racket versions. Treat the plan's package names/version as proposed
defaults, and document any substantive assumption contradicted by current code
or testing before broadening scope.

Build macOS/Linux data-only native packages containing both libraries.
Use a reviewed locked-input manifest, bounded safe extraction, deterministic
offline assembly, Racket-compatible archive checksums plus SHA-256 receipts,
and complete upstream/component notices. Install the payload into an isolated
generation-qualified Racket-managed library directory. Verify source/built/
binary-library preservation, removal, and scope behavior; do not flatten files
into a shared namespace as an unreviewed workaround.

Integrate lazy managed-path discovery into both existing loaders. Preserve
explicit override behavior, ABI checks, Linux HarfBuzz isolation, and the
developer installer route. A selected but broken managed payload must fail
clearly, not fall back to a random host library. Add accurate absolute-path and
artifact provenance to validation diagnostics without loading natives at import.

Update package metadata, installation documentation, registered manual build
assumptions, and bounded catalog tests. Use a disposable staging catalog so all
candidate CI/Acceptance/API workflows resolve the exact unpublished native
archives. Prove ordinary dependency-driven setup with documentation enabled,
network-disabled execution after dependency staging, `raco test --drdr`, actual
rendering/shaping, and installation from rebuilt packages. No `--no-docs` shortcut,
runtime download, blanket test skip, or undeclared font/system-library assumption
may substitute for these checks.
The explicit Windows preparation step occurs before full documentation setup
and uses the pinned raw NuGets staged before network denial in qualification.

Retain the existing full release gates and source-archive binary exclusions.
Review frozen workflow/API/release policies and version assertions deliberately;
do not regenerate manifests or relax evidence checks merely to hide failures.
Qualify macOS ARM64/x86-64, Windows x86-64, and Linux x86-64 including natipkg.
Do not advertise Linux ARM64, musl, 32-bit, or other new targets without execution
evidence. Use disposable environments for installation/update/removal tests.

Deliver the implementation, tests, maintainer publication runbook, candidate
artifacts/receipts where feasible, and a concise report of exact commands,
passed/failed/unrun checks, platform limitations, and remaining decisions.
If external execution or redistribution review is unavailable, report the
specific gap without claiming completion. Stop before creating/pushing tags,
uploading releases, registering/updating catalog entries, creating repositories,
or changing account/repository settings; request explicit publication approval
after the validated candidate is ready.
```

## 15. Planning verification and references

This plan is based on repository inspection and official Racket documentation.
Local read-only inspection confirmed the current pins, the two macOS library
slices, and directory-copy/repackaging support in installed Racket sources.
Ten local platform-selection fixtures passed using `setup/matching-platform`;
version checks accepted `1.0` and `0.79` and rejected `3.119.1`. These are metadata
checks, not execution qualification of the named platforms.
No native packages, lock hashes, license decisions, or publication receipts have
been fabricated. No full catalog simulation was run while writing this plan.

Primary references:

- [Package metadata and platform dependencies](https://docs.racket-lang.org/pkg/metadata.html)
- [Platform matching API](https://docs.racket-lang.org/raco/matching-platform.html)
- [Foreign-library installation metadata](https://docs.racket-lang.org/raco/setup-info.html)
- [Source, binary, and built package forms](https://docs.racket-lang.org/pkg/strip.html)
- [Package names, versions, checksums, and updates](https://docs.racket-lang.org/pkg/Package_Concepts.html)
- [Package-build environment and native-library conventions](https://pkg-build.racket-lang.org/about.html)
- [Pkg-build tooling](https://docs.racket-lang.org/pkg-build/index.html)
- [Publishing packages](https://docs.racket-lang.org/pkg/getting-started.html)
- [Existing project release-candidate process](../docs/RELEASE-CANDIDATE.md)
