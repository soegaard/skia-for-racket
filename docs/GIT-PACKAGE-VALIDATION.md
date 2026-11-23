# Revised Git package layout — local validation record

Current Windows amendment: [the managed Windows native package](WINDOWS-NATIVE-PACKAGE.md)
adds a sixth catalog entry after `c8cf88a0`. The five-entry results below remain
historical; they do not qualify the new Windows managed route or its changed lock.


November 23, 2026. The three source packages and two native package directories
are implemented. Fresh local macOS ARM64 checks pass on released Racket CS 8.18
and 9.3. The complete platform matrix and actual public Git fetching still need
fresh execution. Validation ran before the packaging commit; nothing was published.

The old unsplit `7693d907` / Release candidate run `45096827302`, attempt 2,
remains untouched baseline evidence. It does not qualify this split.
The validation worktree was on `codex/catalog-ci`, based on
`7693d907cb08e9bea1591384313a77f11e7fbedf`. Runtime receipts explicitly record
that uncommitted candidate; they do not certify the later commit's full CI gate.
Temporary Git commits used for local validation have no public remote.

## Implemented boundaries

- `skia/`: 0.79 meta-package, depending on `skia-lib` and `skia-doc`.
- `skia-lib/`: 0.79 implementation of the existing `skia` collection and public
  require paths, installed diagnostics, native metadata/pins and Windows helpers.
  It has no runtime or build dependency on documentation or its fonts.
- `skia-doc/`: 0.79 manuals, tutorial sources/copier, four unchanged Noto fonts
  and notices, and mandatory multilingual/Scribble integration tests.
- Root `tools/`: repository maintenance, generation, validation and CI.
  Concrete source ownership is resolved separately from historical API names.
- `skia-fonts-1` is absent from generation, dependencies and the publication set.

All 25 manual output names, explicit tags, public API links, `raco skia-examples`
and 43 editable assets remain. The copier's direct module path becomes
`skia-doc/tools/copy-tutorial-examples`. SkiaSharp 3.119.1, HarfBuzzSharp 8.3.1.2,
generation `skia-native-1`, explicit overrides, ABI checks, lazy loading and Linux
HarfBuzz isolation remain. Windows explicitly acquires the pinned NuGet pair;
our packages contain no Windows DLLs or raw NuGets.

## Prepared native tree and artifacts

```text
output/catalog/git-publication-prep/skia-libs/
  .gitattributes
  README.md
  skia-native-macos-1/
    info.rkt
    licenses/
    skia-native-1/
  skia-native-x86_64-linux-1/
    info.rkt
    licenses/
    skia-native-1/
```

This tree contains actual native files, without ZIP wrappers, LFS pointers or a
public remote. `prepared-native-tree.json` inventories 77 package files.
`qualified-file-comparison.json` ties native/font data to the qualified archives.
All four native binaries, all four fonts, and upstream/component notices are
unchanged. `native-metadata-deltas.json` records exactly four differences: each
native manifest's lock hash and each copy of the project redistribution review.
They describe documentation font ownership and distinguish old/new gate status.
The current lock SHA-256 is
`e52bccda1089dca6c1d99dd13043e4c10df032db69eeb5e4e559f6dde034afff`.

`native-git-roundtrip.json` verifies all 77 Git blobs with `core.autocrlf=true`;
attributes preserve native bytes and upstream notice line endings. This local
Git storage check is separate from anonymous public fetching.

`output/catalog/git-publication-prep/candidate/artifacts/` contains three source
ZIPs, two native ZIPs, Racket SHA-1 sidecars, native SHA-256 receipts and the
external source-set receipt. These ZIPs are evidence, not the publication host.
`qualification/candidate-byte-comparison.json` confirms that all five archives
match both executed macOS candidates and a separate network-denied offline
reassembly. No generated source identity is injected into the packages.
Dirty-worktree receipts do not certify a clean release commit.

## Executed checks

Evidence paths below are relative to `output/catalog/git-publication-prep/`.

| Check | Result | Retained evidence |
| --- | --- | --- |
| macOS ARM64, released CS 8.18 | 118 commands and all 24 required checks passed | `qualification/macos-arm64-8.18/` |
| macOS ARM64, released CS 9.3 | 118 commands and all 24 required checks passed | `qualification/macos-arm64-9.3/` |
| Installed-package CPU CI rehearsal, CS 9.3 | 23 commands passed, including ABI mirrors and independent DC pixel oracles | `qualification/cpu-ci/` |
| Actual public API reflection, headless and GUI | Both match unchanged frozen captures, with invalid native overrides | `qualification/public-api/` |
| Python regressions | 63 suites passed; eight CI inspector self-tests also pass | `python-tests-complete/`, `qualification/source-checks/` |
| Source/API/reference/release contracts | Passed without runtime-release certification | `qualification/source-checks/` |
| Offline deterministic assembly and native/font comparison | Passed | `candidate-offline-proof/`, comparison receipts above |

Each lifecycle run installs `skia-lib` alone from a five-entry copied-directory
catalog, adds and independently removes documentation, and installs `skia` in a
separate fresh environment. It exercises ordinary dependency-driven setup with
manuals, explicit tests for both subpackages, actual CPU pixels, procedural AV
and default-font shaping, both initialization orders, and all four
documentation-owned scripts/fonts. Library-only tests cannot find a
documentation package or bundled Noto assets.

Both runs preserve managed-payload negatives, override exclusivity, wrong ABI
rejection, absolute-path/provenance checks, read-only first use, foreign-target
preservation, compatible update/rollback, scope/sentinel checks and removal.
Source, built and binary-library packages are rebuilt and installed after the
original environments, directory sources and candidate archives are removed.
Every form retains four fonts/notices, 43 editable assets, copier and working
rendering/shaping. All execution uses OS network denial after dependency staging;
connection probes confirm denial. Full DrDr traversals take 21.540 seconds on
8.18 and 21.004 seconds on 9.3, below the unchanged 600-second bound.

The CPU rehearsal uses a clean temporary Git mirror and disposable Racket
installation with a normally installed standard dependency baseline. It tests
the developer-native route, in addition to the lifecycle runs' managed route.
`ci-mirror.json` records its temporary commit. This is a local rehearsal, not a
GitHub run or qualification of an uncreated real source commit.
The CPU rehearsal preceded the final text-only notice/developer-path corrections;
`qualification/final-text-corrections.json` proves that executable package
sources are identical. The final lifecycle reruns use the corrected text.

## Commands

The retained `result.json` and `ci-report.json` files contain every command,
exit code, duration and log path. Released runtimes are under
`output/catalog/runtimes/{8.18,9.3}/racket/`; the verified native cache is
`output/catalog/bf-inputs/`.

Final staging used `tools/stage-native-catalog.py --snapshot --allow-dirty`,
the matching runtime/cache and the following fresh stage directories:

| Version | Stage | Reused standard dependency catalog |
| --- | --- | --- |
| 8.18 | `/private/tmp/skia-git-stage-8-final` | `/private/tmp/skia-git-stage-8-12/snapshot/catalog` |
| 9.3 | `/private/tmp/skia-git-stage-9-final` | `/private/tmp/skia-git-stage-9-4/snapshot/catalog` |

Staging receipts retain the exact Racket catalog-archive command and dependency
inventory. A fresh run may use the official released catalog as described in
[the runbook](PACKAGE-PUBLICATION.md); temporary historical stages are not
publication inputs. For each version, validation used the matching runtime,
stage and new work directory:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' \
  python3 tools/validate-catalog-package.py \
  --runtime output/catalog/runtimes/8.18/racket \
  --catalog /private/tmp/skia-git-stage-8-final/snapshot/catalog \
  --owned-stage /private/tmp/skia-git-stage-8-final \
  --work /private/tmp/skia-git-validation-8-notices \
  --wrong-abi output/catalog/mac-arm-abi-fixture/skia-wrong-abi.dylib
```

The 9.3 execution used `/private/tmp/skia-git-validation-9-notices`.
The independent offline rebuild command was:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' \
  /usr/bin/env PYTHONDONTWRITEBYTECODE=1 python3 tools/stage-native-catalog.py \
  --racket output/catalog/runtimes/8.18/racket/bin/racket \
  --cache output/catalog/bf-inputs \
  --output output/catalog/git-publication-prep/candidate-offline-proof --allow-dirty
```

The clean temporary mirror ran:

```sh
env RACKET=/private/tmp/skia-git-ci-runtime/racket/bin/racket \
  PYTHONDONTWRITEBYTECODE=1 \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/output/catalog/python314/bin/python \
  tools/ci.py --profile cpu --id macos-arm64 --timeout 1800
```

Regression/check commands use `output/catalog/python314/bin/python`, including
its policy dependencies. Every `tools/test-*.py` and `tools/test_*.py` runs with
separate logs. Final source checks also include:

```sh
python3 tools/static-check.py
python3 tools/check-package-layout.py
python3 tools/check-gpu-source.py --require-integration
python3 tools/api-inventory.py --check
python3 tools/validate-release-scope.py --check --require-no-open-gaps
python3 tools/validate-public-api.py --source-only --directory /new/api-evidence
python3 tools/validate-release-candidate.py --source-only --directory /new/release-evidence
python3 tools/check-reference.py --output /new/outside-checkout/reference-evidence
git diff --check
```

## Assumptions exposed and corrected

- A Scribble conversion test and its three fixtures belonged to the old runtime
  tree. They now belong to documentation; core conversion tests remain in the
  library. Tutorial-retention tests move with the copier.
- Manual module references, including dynamic evaluator/navigation prefixes,
  become `skia-doc/scribblings/...`; explicit output names and tags stay fixed.
- Installed diagnostics need fourteen helper modules plus procedural,
  codec/runtime/geometry and reflection fixtures. Helper copies and concrete
  package ownership are checked against canonical maintenance sources.
- Binary reconstruction exposed stripped doctor fixtures. Explicit retention
  fixes that failure; fresh complete lifecycle runs pass.
- Racket CS 8.18 and 9.3 deliberately strip manual registrations, manual sources
  and generated docs in `--binary-lib` form. Source/built forms must build and
  link all 25 manuals. Binary-library form explicitly verifies Racket's omitted
  documentation state while retaining fonts/notices, 43 assets, copier and
  runtime functionality. No metadata workaround bypasses package stripping.
- The CPU rehearsal first used a minimal runtime missing standard native
  dependencies. A disposable ordinary standard dependency installation fixes
  that environment assumption. A second rehearsal exposed old-root DC source
  fingerprints; DC/canvas lookup and a regression were corrected. The final CPU
  rehearsal passes. Failed reports remain in `qualification/cpu-ci-diagnostics/`.
- The reviewed workflow graph preserves 77 executing jobs and 84 artifacts.
  Sixteen Windows developer-installer destinations explicitly select `skia-lib`.
  GPU source discovery still requires its integration modules. No API capture,
  capability decision or evidence requirement is weakened. See
  [the deliberate review](RELEASE-SCOPE-REVIEW.md).

## Failed or unrun external checks

The cached Docker AMD64 image runs on this ARM64 host. The pinned official Linux
CS 9.3 natipkg runtime downloads and installs with the locked hash, but its
required machine-independent bootstrap exceeds the existing 1200-second bound
under emulation. `linux-natipkg/racket-9.acquisition.json` and
`racket-9.bootstrap.log` retain that failure. No partial runtime, profile-marker
workaround or extended budget is counted as qualification.

Fresh ordinary Linux x86-64/natipkg, macOS Intel and Windows x86-64 execution on
both released versions remains unrun for this split. Windows acquisition has
source/synthetic coverage here; actual Windows install/setup/rebuild needs its
runner. The full manual Release candidate workflow must run again on a clean
real commit, retaining every existing feature/API/docs and platform gate.
No new platform is advertised.

`tools/prepare-git-catalog.py` defaults to printing the five proposed sources
without networking. After separately authorized repository publication,
`--execute` verifies both anonymous public HEAD commits and performs fresh Git
dependency installs, setup, core/docs tests, copying and removal. That phase has
not run. Local directory, archive and Git-blob checks cannot prove public fetching.

## Proposed catalog entries and remaining decisions

| Package | Proposed ordinary default-branch source |
| --- | --- |
| `skia` | `https://github.com/soegaard/skia-for-racket.git?path=skia` |
| `skia-lib` | `https://github.com/soegaard/skia-for-racket.git?path=skia-lib` |
| `skia-doc` | `https://github.com/soegaard/skia-for-racket.git?path=skia-doc` |
| `skia-native-macos-1` | `https://github.com/soegaard/skia-libs.git?path=skia-native-macos-1` |
| `skia-native-x86_64-linux-1` | `https://github.com/soegaard/skia-libs.git?path=skia-native-x86_64-linux-1` |

Both eventual public Git commits remain to be resolved after authorization;
archive SHA-1 sidecars are not Git checksums. Confirm the catalog account/contact
and current name availability before registration. Publishing the prepared
native repository/source layout and registering the five entries each need
explicit authorization. No GitHub Release or ZIP-host decision is needed, and
the approved upstream licensing basis is not reopened.
