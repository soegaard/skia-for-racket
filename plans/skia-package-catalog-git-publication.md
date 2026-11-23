# Revised plan: split library and documentation, publish through Git

Date: November 23, 2026.

Status: planning only. No repository creation, push, release upload, catalog
registration, package installation, or runtime change is performed by this plan.

This supersedes the archive-hosting and single-source-package requirements in
the [original publication plan](skia-package-catalog-publication.md), and the
earlier revision of this plan that retained a separate `skia-fonts-1` package.
The maintainer proposed putting the fonts in `skia-doc`. Adopt a library,
documentation, and meta-package split following Peek's package roles. Preserve
the native implementation and licensing decisions; qualify the changed package
boundaries before publication.

## November 23 amendment: managed Windows package

The maintainer requested `skia-native-win32-x86_64-1` after the split was committed
as `c8cf88a0`. It joins the macOS/Linux packages in the proposed `skia-libs` data
repository. Its source is
`https://github.com/soegaard/skia-libs.git?path=skia-native-win32-x86_64-1`.
There are now six proposed catalog entries: three source and three native.

This amendment supersedes every Windows direct-download exception and five-entry
instruction below. Windows x86-64 gains an ordinary platform-qualified `skia-lib`
dependency and uses `raco pkg install --auto skia`, including normal setup and
rebuilding. The optional pinned NuGet installer remains available for developer
checkouts/explicit overrides. Managed packages take precedence; broken managed
data cannot fall back to that cache. Keep both native pins, the upstream
licensing basis/notices, fonts and public API unchanged. Raw NuGets and native
binaries stay out of the three source packages; the Windows DLLs belong in their
separate data package. The ordinary native Git tree therefore has three package
directories and binary attributes for DLLs as well as dylibs/shared objects.

Build the Windows package from the already locked original Win32 NuGets, with
bounded extraction and deterministic offline assembly. Verify its hashes,
selectors and source/built/binary-library retention using the existing framework.
Existing Windows CS 8.18/9.3 catalog lanes must perform dependency-driven setup,
managed provenance, negatives, update/rollback, scope/removal and rebuilt installs
without the optional NuGet installer. The old direct-route and five-entry
receipts remain historical; they do not qualify this amendment. Fresh actual
Windows execution, the full manual gate and anonymous Git fetching remain
required before catalog submission. No publication is authorized.

## 1. What the sibling repositories demonstrate

| Example inspected | Relevant convention | Application to Skia |
| --- | --- | --- |
| `../peek/info.rkt` | Peek has a meta-package depending on its implementation and documentation. | Make `skia` install `skia-lib` and `skia-doc`. |
| `../peek/peek-lib/info.rkt`, `../peek/peek-doc/info.rkt` | Independent packages can occupy repository subdirectories, each with its own metadata. | Separate the implementation from manuals, tutorial assets, and fonts. |
| `../poppler-libs/poppler-aarch64-macosx-2/` | Actual native library files, notices, and `info.rkt` are checked into a Git package directory. | Store the already prepared Skia native payloads as ordinary Git files. |
| Poppler's package and nested collection `info.rkt` files | Package dependencies and collection-level `install-platform`/`copy-foreign-libs` describe installation. | Retain Skia's existing equivalent metadata; its single-collection packages combine those roles in one `info.rkt`. |
| `../racket-poppler/info.rkt` | The bindings select native packages with platform-qualified dependencies. | Keep the current Skia dependency selectors. |

The public catalog confirms this is how these packages are registered:

- [peek](https://pkgs.racket-lang.org/package/peek) uses
  `https://github.com/soegaard/peek.git`.
- [peek-lib](https://pkgs.racket-lang.org/package/peek-lib) uses
  `https://github.com/soegaard/peek.git?path=peek-lib`.
- [poppler-aarch64-macosx-2](https://pkgs.racket-lang.org/package/poppler-aarch64-macosx-2)
  uses `https://github.com/soegaard/poppler-libs.git?path=poppler-aarch64-macosx-2`.

Racket explicitly supports Git repository sources and `?path=` subdirectories.
An optional `#revision` selects a branch, tag, or commit; otherwise the repository's
default branch is used. The resolved Git revision supplies the package checksum.
Separately hosted ZIPs and `.CHECKSUM` files are another supported distribution
method, not a requirement. See [package sources](https://docs.racket-lang.org/pkg/Package_Concepts.html)
and [GitHub deployment](https://docs.racket-lang.org/pkg/getting-started.html#%28part._github-deploy%29).

The earlier plan chose archive distribution and then made permanent archive
hosting a blocker. That choice can be replaced without replacing the native
packaging implementation. No GitHub Release or branch containing ZIP files is
needed for the proposed Git route.

## 2. Starting point: the previous package layout is qualified

The current implementation is commit
`7693d907cb08e9bea1591384313a77f11e7fbedf` on `codex/catalog-ci`.
[Release candidate run 45096827302, attempt 2](https://github.com/soegaard/skia-for-racket/actions/runs/45096827302)
has a retained verification report recording 78 successful jobs, 84 verified
evidence artifacts, ten catalog execution lanes, and both candidate-validation
flags true. This plan inspected those retained records and the implementation
chat; it did not repeat remote execution.

Evidence is in
`output/catalog/manual-45096827302-attempt-2-20261123/VERIFIED-CANDIDATE.md`,
`verification-summary.json`, and `qualified-packages/` beneath that directory.
Preserve these files and the qualified ZIPs as historical evidence and as the
input for preparing the native packages and documentation font assets. They
qualify the old package layout, not the proposed library/documentation split.

A read-only comparison made for this plan found all 1,678 tracked files at that
commit byte-identical to the corresponding members of qualified `skia.zip`.
The ZIP's sole extra file is `private/source-identity.json`, inserted by
`tools/stage-native-catalog.py`. `tools/catalog-smoke.rkt` already treats that
file as optional. Ordinary Git installation must work without fabricating it.

Accepted decisions remain in force:

- `skia` version 0.79 and the existing public collection/module paths.
- SkiaSharp 3.119.1 and HarfBuzzSharp 8.3.1.2, with unchanged native bytes.
- Managed native packages for macOS ARM64/Intel and Linux x86-64, including natipkg.
- Keep the four approved unmodified Noto fonts and their OFL notices, now as data
  inside `skia-doc`. Supersede the separate `skia-fonts-1` dependency and package.
- The November 22 maintainer approval of the upstream licensing basis, with
  original and supplemental notices retained. Do not reopen that investigation.
- Windows uses the approved explicit pinned NuGet installer. There is no Windows
  native package to publish, and Windows DLLs/raw NuGets stay out of our repositories.

Checked-in status documents still describe earlier pending runs. Record the
successful baseline, then distinguish new validation of the split from that
historical result. Do not reopen the accepted native licensing investigation.

## 3. Recommended repository and catalog layout

Keep the source, documentation, and meta-packages in `soegaard/skia-for-racket`.
Prepare a proposed separate native repository, `soegaard/skia-libs`, following
the role of `soegaard/poppler-libs`. The new repository has not been created or
reserved. Use explicit package subdirectories so the repository root does not
accidentally install the other packages' files a second time.

```text
skia-for-racket/                  repository container
  skia/                          meta-package: skia
    info.rkt                     depends on skia-lib and skia-doc
  skia-lib/                      package: skia-lib, collection "skia"
    info.rkt
    main.rkt, private/, ...       implementation and public modules
    tests/                       tests independent of documentation fonts
    tools/                       installed runtime tools, Windows installer
    packaging/                   installed metadata needed by those tools
    examples/                    examples needed by library checks/tools
  skia-doc/                      package and collection: skia-doc
    info.rkt                     depends on skia-lib
    scribblings/                 manuals and editable tutorial sources
    fonts/                       four existing font files
    licenses/                    OFL texts and font copyright records
    private/                     documentation font helper
    tests/                       font-dependent integration tests
    tools/                       tutorial-example copier
  tools/, api/, plans/, docs/     repository maintenance files as appropriate

skia-libs/                       repository container, not a catalog package
  README.md
  .gitattributes
  skia-native-macos-1/           package root
    info.rkt
    README.md
    licenses/
    skia-native-1/
      manifest.json
      libSkiaSharp.dylib
      libHarfBuzzSharp.dylib
  skia-native-x86_64-linux-1/     package root
    info.rkt
    README.md
    licenses/
    skia-native-1/
      manifest.json
      libSkiaSharp.so
      libHarfBuzzSharp.so
      fontconfig/fonts.conf.in
```

There are five catalog entries; there is no `skia-fonts-1` or `skia-libs` entry:

| Catalog name | Version | Proposed source URL |
| --- | --- | --- |
| `skia` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia` |
| `skia-lib` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia-lib` |
| `skia-doc` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia-doc` |
| `skia-native-macos-1` | 1.0 | `https://github.com/soegaard/skia-libs.git?path=skia-native-macos-1` |
| `skia-native-x86_64-linux-1` | 1.0 | `https://github.com/soegaard/skia-libs.git?path=skia-native-x86_64-linux-1` |

The dependency direction is:

```text
skia --------> skia-lib --------> matching native package (macOS/Linux)
  \                ^
   +--> skia-doc --+
          contains the fonts
```

`skia-lib` must have no runtime or build dependency on `skia-doc` and must not
load its font helper. The meta-package owns no `skia` implementation collection;
`skia-lib` alone provides `(require skia)`, `skia/dc`, `skia/pict`, and the other
existing public modules. The separate `skia-doc` collection avoids duplicate
collection metadata and accidental ownership of runtime modules.

On macOS/Linux, user-facing installation becomes:

```sh
raco pkg install --auto skia       # library, manuals, examples, and fonts
raco pkg install --auto skia-lib   # library without documentation font assets
```

Installing `skia-doc` later adds the manuals and fonts to a library-only install.
Normal `skia` installation still includes the approximately 17.3 MB of font data;
the benefit is optional documentation, not eliminating font redistribution.
Git acquisition may fetch a repository snapshot containing other subdirectories,
so do not promise zero font transfer for every direct Git installation. The
installed `skia-lib` package contains no Noto assets and does not depend on the
documentation/font package. Existing platform support, including Racket's own
font support on natipkg, remains; this is not a promise of a font-free system.

Use the ordinary default-branch URLs for catalog maintenance, as the sibling
packages do. Record the exact resolved commits in the submission record and
validate those revisions. Before registration, the chosen default branches must
contain the validated content; do not accidentally register an older `main`.
Commit-pinned `#<commit>` URLs are useful during testing but are not a required
permanent publication policy. A pinned catalog source would need deliberate
updates; a branch source follows later commits through normal catalog checks.

A separate native repository keeps native binaries out of the source repository.
Fonts are intentionally stored in the documentation package in the source
repository. The old blanket exclusion of font files from every source package
must become a package-specific rule: fonts are allowed in `skia-doc`, and remain
excluded from `skia-lib` and the meta-package.

## 4. Preserve the working installation design

The generated native package directories are already ordinary Racket packages.
Retain their package names, selectors, dependency declarations, and
`copy-foreign-libs '("skia-native-1")` layout. The generation directory, paired
library manifest, loader precedence, ABI checks, Linux fontconfig support, and
HarfBuzz isolation have passed execution tests. Git hosting does not require
flattening the libraries or replacing those loaders with bare `ffi-lib` calls.

Poppler demonstrates the standard metadata mechanism, not a requirement to
copy its exact filenames or collection layout. Racket documents platform-aware
foreign-library copying in [setup metadata](https://docs.racket-lang.org/raco/setup-info.html).

Keep all actual native/font files in ordinary Git storage, with binary attributes
so checkout cannot alter them. Do not replace them with Git LFS pointers or add
installation-time downloads. The largest documentation font is the existing CJK
file, 16,467,736 bytes; the macOS Skia library is 15,383,440 bytes. Keep their
existing contents and notices. Avoid committing generated ZIPs or caches as well.

## 5. Implementation sequence before any publication

### A. Prepare package directories from the qualified payloads

1. Recheck checkout state and latest accepted decisions. Preserve unrelated work.
2. Under a new ignored workspace directory such as
   `output/catalog/git-publication-prep/skia-libs/`, unpack the two qualified native
   ZIPs into their corresponding package directories. Extract the font files,
   notices, copyright records, and provenance from the old qualified font ZIP for
   inclusion in `skia-doc`; do not install its old package `info.rkt` there.
3. Compare every extracted file with its qualified archive member. Record a
   concise per-file comparison and the three original archive SHA-256 values.
   Do not rebuild Skia, re-download different inputs, or change the approved font
   set. Preserve native installation metadata where possible. If changed lock
   metadata requires updating a native manifest, record that separately from
   unchanged library bytes; do not claim the resulting archive has the old hash.
4. Add a repository README explaining the package mapping, upstream pins, licenses,
   and refresh procedure. Add binary `.gitattributes` entries for the native and
   font formats. If a package README's obsolete publication wording is corrected,
   record that as an explicit documentation-only difference.
5. Ensure the proposed repository contains no Windows DLLs, raw NuGets, build
   outputs, compiled Racket caches, or copied maintainer-machine libraries.

No new public repository is needed to complete this preparation. Once authorized,
the prepared tree can become the sibling checkout and public data repository.
Keep the existing generators as maintainer tools for future refreshes; a new
generation framework is unnecessary for the initial import.

### B. Split implementation, manuals, and tests without a dependency cycle

1. Move the runtime collection into `skia-lib`, preserving its internal relative
   module relationships and public `skia/...` require paths. Inventory installed
   tools before moving repository-only tooling: the Windows installer and its
   Python helpers, native lock, and version files must remain available in an
   installed/binary package. Update maintenance scripts that assume the repository
   root is also the collection root.
2. Give `skia-lib` collection name `"skia"`, the runtime dependencies and native
   selectors. Give `skia-doc` collection name `"skia-doc"`, a dependency on
   `skia-lib`, and the Scribble/documentation dependencies its imports require.
   Move manual registrations and documentation-specific build dependencies out
   of the runtime package. Set compatible 0.79 dependency minima for the split.
3. Make `skia` a small `collection 'multi` meta-package depending on `skia-lib`
   and `skia-doc`. Do not copy the implementation or manuals into it.
4. Move manuals and their shared assets into `skia-doc`. Replace cross-package
   relative imports with public collection imports where appropriate. Update
   documentation catalog module paths from `skia/scribblings/...` to
   `skia-doc/scribblings/...`, preserving registered manual output names, tags,
   navigation, and public API links. Audit evaluators and registration tests that
   currently derive the source repository from their own location.
5. Move the four fonts and complete OFL/copyright records into `skia-doc`. Replace
   `collection-path "skia-fonts-1"` with one documentation-owned runtime-path
   helper. Documentation code remains MIT and the font files remain OFL-1.1;
   use metadata describing both components. Remove the old package dependency
   and generation/publication target rather than retaining a compatibility shell.
6. Split the Noto-dependent cases out of `tests/catalog-package-test.rkt` and
   `tools/catalog-smoke.rkt`. Core checks in `skia-lib` keep deterministic tests
   using the original in-memory AV fixture, real default-font checks, rendering,
   and Skia/Draw initialization-order checks. Put full Noto multilingual checks
   in `skia-doc` and keep them mandatory in the documentation/full CI lanes.
   Do not add `skia-doc` as a build dependency of `skia-lib` to make its tests pass.
7. Move the tutorial copier implementation and `skia-examples` raco registration
   to `skia-doc`, retaining the command name and behavior when docs are installed.
   Audit the old `skia/tools/copy-tutorial-examples` invocation and document any
   change; avoid an unconditional library-to-docs import. Move all 43 advertised
   editable assets and their explicit binary-retention entries with the copier.
8. Update staging, source/archive exclusions, package retention checks, source
   inventory paths, and workflow commands for five packages. Adjust frozen path
   records through explicit review; preserve exported API signatures and test
   assertions. `raco test --package skia` alone would test an almost empty
   meta-package, so CI must name `skia-lib` and `skia-doc` explicitly.

### C. Make the runbook describe the split and Git publication

Update `docs/PACKAGE-PUBLICATION.md`, `docs/PUBLICATION-PREFLIGHT.md`, and the current
status at the top of `docs/CATALOG-VALIDATION.md` to record the successful final
run and the Git source table. Preserve historical failures under their dates.
Update relevant README/install text and the catalog submission draft.

Separate these three facts throughout the documentation:

- The previous unsplit implementation passed its full release gate.
- The changed package layout and Git installation need fresh checks below.
- No public catalog entry has been registered.

Remove the requirement to choose a ZIP host, publish a GitHub Release, or maintain
an archive branch. Existing ZIPs remain useful test/evidence artifacts. Their
archive SHA-1 sidecars are not the catalog checksums of Git sources.

### D. Verify library-only and full installation from directories and Git

Use a fresh disposable Racket user/addon environment and a temporary catalog;
leave the maintainer's normal package database and catalog settings alone.

1. Map all five package names to clean prepared package directories in the local
   catalog. Use copies, not linked developer directories. Install `skia-lib`
   alone; verify its actual package/dependency set contains neither `skia-doc`
   nor `skia-fonts-1`, and no Skia-bundled Noto assets. Run its setup, dependency
   checks, CPU tests, and both load-order
   checks with no documentation checkout accessible as a fallback.
2. In a separate fresh environment, install `skia`. Check automatic selection
   of both source subpackages and only the applicable native package. Build all
   manuals through ordinary setup and run both packages' tests, including full
   multilingual checks. Also test adding `skia-doc` to a library-only install.
3. Test without the archive-only `private/source-identity.json`. Check example
   copying, independent docs removal while the library remains usable, and
   source/built/binary-library retention for each package. Compare native/font
   bytes against the qualified inputs and preserve all required notices.
4. Preserve the Windows procedure: install `skia` or `skia-lib` without setup,
   run `racket -l skia/tools/install-windows-natives`, then perform setup. It must
   not acquire a new Windows package dependency or bundle the downloaded DLLs.
5. After authorized repository publication, repeat a fresh dependency-driven
   install using a disposable catalog whose entries are the actual Git URLs and
   resolved commit checksums. This checks public fetching and `?path=` handling
   before the public catalog entries are registered. A directory-copy test alone
   is not evidence of successful public Git retrieval.

The full-install macOS/Linux smoke commands become:

```sh
raco pkg install --auto skia
raco setup --check-pkg-deps --pkgs skia-lib skia-doc skia
raco test --drdr --package skia-lib
raco test --drdr --package skia-doc
racket -l skia/tools/catalog-smoke --
racket -l skia/tools/catalog-smoke -- --draw-first
```

These examples assume the disposable catalog/environment has already been
configured. They are not instructions to install today's unpublished packages
into the ordinary user profile.

### E. Qualify the changed package boundaries

The November 23 full run remains baseline evidence for the native implementation.
This amendment changes package layout, dependencies, documentation paths, test
ownership, and packaging tools. It is no longer a hosting-only change. Run the
affected source, API, documentation, lifecycle, and CI/release checks on the new
committed layout; do not label the split qualified based on old receipts.

Use the existing CS 8.18/9.3 matrix for macOS ARM64/Intel, ordinary Linux and real
natipkg, and the approved Windows route. Test library-only and full installs,
including that library tests cannot silently find the docs fonts. Reuse the
existing infrastructure; adapt its package lists and evidence semantics rather
than adding another release framework or preserving obsolete job counts as a
goal. Keep meaningful native, API, documentation, and multilingual coverage.

The current archive verifier should continue checking archive candidates. For
Git publication, identity is the pair of repository commits plus package paths
and payload hashes. A small companion comparison/report can establish that;
there is no need to teach a native loader about Git or embed its containing
commit in a tracked file.

## 6. Publication sequence after explicit approval

Prepare the complete directories, source revisions, catalog-entry table,
description/tags, owner/contact, comparison report, and local check results first.
Recheck package-name availability when preparing submission. The existing
maintainer owns other catalog entries, but confirm the intended account instead
of inferring it from a GitHub username.

Request authorization for the concrete remaining external actions: creating or
using the data repository, pushing/merging the prepared content, and registering
the five catalog entries. Follow the scope of that authorization; no such action
is authorized by this planning request.

After authorization:

1. Publish the prepared `skia-libs` tree and make the intended Skia source revision
   available on its chosen catalog branch. Record both exact commits.
2. Check anonymous Git access and complete the Git-source installation checks
   above. Stop to fix a failure before registration.
3. Register `skia-native-macos-1` and `skia-native-x86_64-linux-1`
   with their `?path=` source URLs. Verify metadata and dependency resolution.
4. Register `skia-lib`, then `skia-doc`, then the `skia` meta-package, using their
   source subdirectory URLs after their dependencies exist.
5. Install from the public catalog in a fresh environment, inspect actual package
   build/test logs and hosted manuals, and check the public built-package route.
   Use the Windows instructions when checking Windows; do not claim a one-command
   Windows install.

Normal updates then use reviewed Git commits and Racket's catalog update
mechanism. Keep compatible package-version constraints and the existing native
generation policy. No recurring manual ZIP upload is required.

## 7. Completion checklist

- [ ] Two ordinary native-package directories prepared with payloads and notices.
- [ ] `skia-lib`, `skia-doc`, and `skia` have an acyclic dependency graph.
- [ ] `skia-lib` alone provides the existing public `skia` modules and needs no docs fonts.
- [ ] `skia-doc` owns the four unchanged fonts, licenses, manuals, and tutorial copier.
- [ ] `skia-fonts-1` is absent from the new dependency graph and publication set.
- [ ] Comparisons tie the native and font files to their qualified original inputs.
- [ ] Library-only and full setup/tests, example copying, rebuilding, and removal pass.
- [ ] Fresh checks qualify the split; old results remain accurately labelled baseline evidence.
- [ ] Proposed repositories, package paths, resolved revisions, and account details are concrete.
- [ ] Explicit authorization is obtained before repository/catalog mutations.
- [ ] Actual public Git fetching and dependency-driven installation pass.
- [ ] Five catalog entries resolve, and actual server/manual/built-package results are checked.

## 8. Prompt for the implementation chat

```text
Adjust publication preparation to follow the Git-based Racket package conventions
used by ../peek, ../poppler-libs, and ../racket-poppler.

Read plans/skia-package-catalog-git-publication.md. Its latest amendment puts the
fonts in skia-doc and adopts the skia/skia-lib/skia-doc split. It supersedes the
old mandatory ZIP-hosting route and separate skia-fonts-1 package. Do not publish.

Preserve the successful 7693d907 / run 45096827302 attempt-2 evidence, approved
upstream licensing basis, unchanged font/native bytes, native pins, and explicit
Windows NuGet exception. Preserve the working loaders and public API.

Create three package subdirectories in the source repository: skia as a small
meta-package; skia-lib providing the existing skia collection; and skia-doc
containing manuals, tutorial assets, the four Noto fonts, and their notices.
skia depends on both; skia-doc depends on skia-lib; skia-lib must have no runtime
or build dependency on skia-doc. Keep require paths such as skia and skia/dc.

Move Noto-dependent tests to skia-doc and keep them mandatory in full CI. Library
tests use the existing procedural fixture and real platform-font checks. Move
documentation registration and the tutorial copier with the docs, retaining
manual output identities, the raco command, and all advertised editable assets.
Audit relative paths, installed Windows tools, package retention metadata, and
repository scripts. Remove skia-fonts-1 from generation/dependencies/publication.

Prepare skia-libs locally with only skia-native-macos-1 and
skia-native-x86_64-linux-1, reusing the qualified payloads. Extract the fonts from
the qualified font archive into skia-doc without changing their bytes. Preserve
licenses and provenance; record any changed metadata honestly. Store actual
binary files, not ZIP wrappers or Git LFS pointers. Do not create a public repo.

Update the publication runbook/status and submission draft to use ordinary
Git source URLs and ?path= subdirectories. Remove mandatory ZIP-host selection,
GitHub Release, and archive-branch steps. Keep existing generators and receipts
as maintainer tools/evidence. Font files are permitted only in skia-doc, not in
skia-lib or the meta-package; update the former blanket source-font exclusion.

Validate fresh library-only and full installations, docs/setup, CPU rendering and
shaping, multilingual coverage, and per-package retention/removal. Run tests for
skia-lib and skia-doc explicitly: testing only the meta-package is insufficient.
This split requires fresh qualification of changed dependencies and paths on the
existing platform/version matrix; old full-gate results are baseline evidence.
Prepare actual Git URL checks for the authorized external phase. Do not weaken
tests or invent another release framework.

Return the prepared tree location, exact changes, comparison and check results,
the five proposed catalog entries, and concrete remaining external actions.
Do not create repositories, push/merge publicly, register packages, upload
releases, or change repository/account settings without explicit authorization.
```
