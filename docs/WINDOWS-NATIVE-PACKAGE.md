# Windows native package — November 23, 2026

The maintainer requested `skia-native-win32-x86_64-1` after source-split commit
`c8cf88a0`. This replaces the Windows direct-download exception for ordinary
installation. The optional NuGet installer remains a developer tool. Nothing
has been pushed, published, tagged or registered by this implementation.

## Installation and contents

The intended catalog command is `raco pkg install --auto skia`, or `skia-lib`
without documentation. `skia-lib` selects this data-only package only for
`win32\x86_64`, with native package version 1.0 and generation `skia-native-1`.
It contains `libSkiaSharp.dll`, `libHarfBuzzSharp.dll`, the paired manifest and
complete upstream/component notices. Racket owns setup, update and removal.
Imports and first rendering do not acquire libraries. The three source packages
continue excluding native binaries and raw NuGets; the native package contains
the DLLs. The four Noto fonts stay in `skia-doc`.

The DLLs are unmodified binaries from the
[SkiaSharp project](https://github.com/mono/SkiaSharp), with original licenses
and third-party notices retained. Pins remain SkiaSharp 3.119.1 and
HarfBuzzSharp 8.3.1.2. No new licensing investigation or native rebuild is needed.

Both loaders share lazy paired discovery. Explicit overrides retain precedence;
managed `skia-native-1` data precedes the optional `skia-upstream-1` developer
cache. A broken selected managed pair, or an installed native dependency whose
generation is missing, fails without falling back to that cache or a host DLL.
The legacy `--root` developer installers and feature/ABI CI routes remain.

## Prepared tree and receipts

The prepared ordinary Git tree is
`output/catalog/windows-native-package/skia-libs/`, containing:

- `skia-native-macos-1/`
- `skia-native-x86_64-linux-1/`
- `skia-native-win32-x86_64-1/`

It holds actual native files, metadata and notices, with binary Git attributes;
there are no LFS pointers, ZIP wrappers or public remote. All 115 package files
are inventoried in `prepared-native-tree.json`. `native-metadata-deltas.json`
records the macOS/Linux manifest/review-document changes. Their library bytes
remain unchanged; the Windows DLLs match the original locked NuGet members.

`native-artifacts/` contains three native ZIPs, Racket SHA-1 sidecars and SHA-256
receipts. `native-repro/` is an independently assembled comparison set. Assembly
uses bounded extraction from `output/catalog/bf-inputs` with networking denied.
Source ZIP assembly and disposable catalogs now cover six packages. ZIPs are
local evidence, not a required publication host.

## Validation and limits

| Local check | Result |
| --- | --- |
| Offline native assembly and independent reproduction | Three archives match byte for byte, including Racket SHA-1 sidecars |
| Locked Windows DLLs and PE inspection | Exact hashes/sizes; both images are x86-64 PE DLLs |
| Native Git storage with `core.autocrlf=true` | All 115 package files preserved |
| Platform metadata and lazy discovery target | Passed on released Racket CS 8.18 and 9.3 |
| Paired discovery/selector regressions | 20 pure tests passed on CS 9.3 |
| Python regression suites | All 63 passed |
| Actual frozen public API reflection | Headless and GUI match; invalid native overrides prevent native loading |
| Windows foreign-package rebuilding on macOS | All 37 non-metadata files, including both DLLs/notices, preserved in source, built and binary-library forms |
| Full six-package macOS CS 9.3 lifecycle | Incomplete: disk exhaustion at command 105; fresh identical-input retry failed at command 44 for the same resource reason |
| Actual Windows CS 8.18/9.3 and full manual release gate | Unrun; existing CI lanes remain required |

The lifecycle failures report `errno=28`, “No space left on device,” while
copying package files. They do not certify a complete lifecycle pass. Their
partial logs/receipts remain in `macos-arm64-9.3-disk-full/` and
`macos-arm64-9.3-retry-disk-full/`. The standalone foreign-package probe initially
hit the same limit before package execution, then passed in a fresh disposable
environment; both attempts are retained. Current package/archive bytes are
compared with the executed candidates in `retry-candidate-comparison.json`.

Source/platform-selection and paired-discovery tests run locally, including
managed precedence, missing DLLs, missing managed generations, optional-cache
fallback restrictions and unsupported Windows architectures. The catalog
verifier requires the same managed lifecycle checks on Windows as macOS/Linux,
plus exact Windows archive/member hashes and managed path/package identity.
The previous direct-download evidence cannot qualify the new route.

The existing ten CS 8.18/9.3 catalog lanes and full manual release gate remain.
Windows staging builds the native ZIP before OS network denial, then runs
ordinary dependency-driven installation with manuals, DrDr, actual rendering
and shaping, negatives, update/rollback, scope/removal and fresh rebuilt-package
installs. The catalog validator does not invoke the optional NuGet installer.
Receipt-only push/PR artifacts remain free of native payloads; full manual
candidate evidence may contain the three reviewed native ZIPs. Loose SkiaSharp/HarfBuzzSharp DLLs and
NuGets are rejected as loose evidence, and every source archive excludes them.

Actual Windows execution is unavailable on this macOS host. Windows CS 8.18/9.3
DLL loading, file-lock/removal behavior and end-to-end managed lifecycle must be
qualified by the existing Windows CI lanes. Local PE inspection, metadata and
foreign-platform retention are not Windows execution evidence. Fresh full
matrix/manual-gate and anonymous public Git fetching remain pending.

Exact local commands/results and receipts are retained under
`output/catalog/windows-native-package/`. The earlier five-entry split evidence
in `docs/GIT-PACKAGE-VALIDATION.md` remains historical and uses a different lock.

The offline assembly commands were:

```sh
python3 tools/build-native-packages.py --lock packaging/native-assets.json \
  --inputs output/catalog/bf-inputs \
  --output output/catalog/windows-native-package/native-artifacts --local-candidate
python3 tools/build-native-packages.py --lock packaging/native-assets.json \
  --inputs output/catalog/bf-inputs \
  --output output/catalog/windows-native-package/native-repro --local-candidate
python3 tools/compare-native-artifacts.py \
  output/catalog/windows-native-package/native-artifacts \
  output/catalog/windows-native-package/native-repro
```

Both assembly commands ran under an OS sandbox denying networking. The duplicate
reproduction ZIPs were removed after exact comparison; their receipts and
`offline-reproduction.json` remain. `candidate/artifacts/` retains all six
candidate archives. Each execution directory retains command arguments, exit
codes and logs; `metadata-commands.json` records both released-version probes,
`python-tests/` the 63 suites, `public-api/` both actual reflection groups,
`foreign-windows-forms/` the non-executing retention proof, and `source-checks/`
the static/API/reference/release contracts. Source-policy checks preserve
`release_ready: false` and do not supply missing platform execution.

## Proposed catalog sources

| Package | Proposed ordinary default-branch source |
| --- | --- |
| `skia` | `https://github.com/soegaard/skia-for-racket.git?path=skia` |
| `skia-lib` | `https://github.com/soegaard/skia-for-racket.git?path=skia-lib` |
| `skia-doc` | `https://github.com/soegaard/skia-for-racket.git?path=skia-doc` |
| `skia-native-macos-1` | `https://github.com/soegaard/skia-libs.git?path=skia-native-macos-1` |
| `skia-native-x86_64-linux-1` | `https://github.com/soegaard/skia-libs.git?path=skia-native-x86_64-linux-1` |
| `skia-native-win32-x86_64-1` | `https://github.com/soegaard/skia-libs.git?path=skia-native-win32-x86_64-1` |

Confirm both public commits and the catalog account/contact/name availability
before registration, following the publication runbook. Creating or publishing
the native repository, pushing the source layout and registering entries each
require separate authorization. No GitHub Release or ZIP host is required.
