# Publication preflight — 0.79 / native generation 1

Read-only review on November 21, 2026. No push, tag, release upload, catalog
registration or repository/account change is authorized or performed.
The later [initial CI push preparation](PUSH-READINESS.md) gives the maintainer
a dedicated test branch with receipt-only automatic catalog uploads. The
maintainer performs that push; the agent has not pushed it.

Amendment, November 22: Windows now uses explicit direct NuGet acquisition.
Exclude its native package from the proposed publication set. The earlier
managed Windows execution receipts qualify the old route. The revised route
passed both released Windows lanes at `cc9bb585`; macOS/Linux packaging is unchanged.
See the [Windows procedure](PACKAGE-PUBLICATION.md#windows-direct-nuget-exception).

## Proposed identities

| Package | Version | Distribution |
| --- | --- | --- |
| `skia` | `0.79` | Existing single source/API collection |
| `skia-native-macos-1` | `1.0` | Both unchanged universal native dylibs |
| `skia-native-x86_64-linux-1` | `1.0` | Both unchanged x64 glibc libraries; declared natipkg dependencies |
| `skia-fonts-1` | `1.0` | Four approved unmodified Noto fonts and OFL notices |

The authoritative [catalog index](https://pkgs.racket-lang.org/pkgs) contained
2,845 names and none of these five names at inspection. The retained response
is `output/catalog/publication-followup-20261121/catalog-names.rktd`, 41,140 bytes,
SHA-256 `7b9c59c8412c469ea03ebdd2d2b1f855ab402d3f13858b14336d85c2a4855e13`.
This historical five-name check includes the now-excluded Windows name.
It is a point-in-time collision check, not a reservation. Recheck immediately
before any later authorized registration.

The existing public repository is
[soegaard/skia-for-racket](https://github.com/soegaard/skia-for-racket).
Its public main ref was `bfa9cf19512bc9b8721a7c045e980d4d9000fdd0`, with public
commit contact Jens Axel Søgaard, `jensaxel@soegaard.net`. Proposed package
maintainer is `soegaard`, consistent with existing `pkg-authors` metadata.
The maintainer must confirm the actual Racket catalog login/contact and control
of that account. GitHub ownership does not establish catalog-account ownership.

Proposed immutable release location, subject to that later approval:
`https://github.com/soegaard/skia-for-racket/releases/download/skia-0.79-native-1/`.
Append each exact package ZIP filename from the table (for example `skia.zip`
or `skia-native-macos-1.zip`). Public releases and tags were empty at inspection;
this location does not exist and has not been created. Use immutable archives
and their Racket SHA-1 checksums as catalog sources, with SHA-256 receipts retained
beside them. A mutable branch URL is not the proposed package source.

## Execution and review dependencies

| Blocker | Exact next action | Responsible party |
| --- | --- | --- |
| Native redistribution | Approved November 22 on the basis of unmodified binaries from [SkiaSharp](https://github.com/mono/SkiaSharp), with original licenses and third-party notices included. Windows DLL redistribution is excluded. | Maintainer decision recorded in the bound review |
| Intel, Windows, ordinary Linux and natipkg execution | All ten CS 8.18/9.3 catalog lanes passed at `cc9bb585`. The manual gate must rerun them for the resulting reviewed candidate. | Verified CI; manual-run operator |
| Same-attempt release evidence | Run the existing Release candidate workflow on the exact committed candidate; all CI, Acceptance, API inventory and catalog jobs plus the aggregator must pass | Maintainer/authorized GitHub runner operator |
| GitHub access to candidate | Push the prepared `codex/catalog-ci` branch for receipt-only automatic CI; separately review the full archive transfer before an eventual Release candidate dispatch | Project maintainer |
| Names/contact/immutable URL | Confirm catalog-account identity and proposed release location against the final exact manifest | Project maintainer |

The complete ten-lane CI receipts close the earlier external execution gaps
for `cc9bb585`. The aggregator continues to require approved review flags, a clean source
identity, identical archives across catalog lanes and complete same-attempt
evidence. `catalog_candidate_validated` remains false.

## Prepared runner commands

On a fresh disposable native host, install the released full 64-bit Racket CS
version and compiler prerequisites from `catalog-package.yml`. For each of 8.18
and 9.3, use a fresh output directory:

```sh
python tools/run-catalog-ci.py --racket /absolute/released/racket --output /absolute/new/catalog-run
```

On a native Linux x64 Docker runner, use the exact official natipkg runtime;
repeat with both version arguments and new destinations:

```sh
python tools/prepare-natipkg-runtime.py --version 8.18 --output output/catalog-runtime-8.18
docker build --platform linux/amd64 -t skia-catalog-natipkg -f packaging/prototypes/linux-audit.Dockerfile .
python tools/run-catalog-ci.py --racket output/catalog-runtime-8.18/bin/racket --natipkg-runtime output/catalog-runtime-8.18 --docker-image skia-catalog-natipkg --output output/catalog-run-8.18
```

After the candidate ref and Actions artifact transfer are separately authorized
and made available, the prepared complete release invocation is:

```sh
gh workflow run release-candidate.yml --repo soegaard/skia-for-racket --ref EXACT_CANDIDATE_REF
```

This command has not been run. Automatic push/PR catalog jobs retain verified
JSON receipts only. The full Release candidate caller retains native archives;
review that later transfer before dispatching it.

## Later publication sequence

Only after pre-publication review and every required gate pass, present the
exact immutable manifest for explicit publication approval. Publish the accepted
bytes and complete notices/checksums without rebuilding. Register the two
macOS/Linux native packages and `skia-fonts-1` before `skia`, then verify dependency-driven
public installation. Actual catalog-server documentation/test builds and public
built-package installs are post-publication checks; no disposable staging
catalog result claims they have already happened. The complete procedure and
rollback boundaries are in [the runbook](PACKAGE-PUBLICATION.md).
