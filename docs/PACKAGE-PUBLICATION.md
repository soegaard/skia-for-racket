# Git catalog publication runbook — 0.79

The candidate uses three source packages and three native packages. The runtime
still provides the `skia` collection and its existing public API. The source
split needs fresh qualification; the successful unsplit baseline is commit
`7693d907`, Release candidate run `45096827302`, attempt 2 (November 23, 2026).
No catalog registration or native repository publication has been performed.

| Package | Version | Proposed ordinary catalog source |
| --- | --- | --- |
| `skia` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia` |
| `skia-lib` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia-lib` |
| `skia-doc` | 0.79 | `https://github.com/soegaard/skia-for-racket.git?path=skia-doc` |
| `skia-native-macos-1` | 1.0 | `https://github.com/soegaard/skia-libs.git?path=skia-native-macos-1` |
| `skia-native-x86_64-linux-1` | 1.0 | `https://github.com/soegaard/skia-libs.git?path=skia-native-x86_64-linux-1` |
| `skia-native-win32-x86_64-1` | 1.0 | `https://github.com/soegaard/skia-libs.git?path=skia-native-win32-x86_64-1` |

Use the repositories' ordinary default branches. Record the two resolved Git
commits and each package path when validating/submitting. A Git catalog checksum
is the resolved commit; ZIP SHA-1 sidecars and SHA-256 receipts describe archive
candidates only. No GitHub Release, ZIP host, archive branch, or new version pin
is required. Publishing either repository or catalog entries needs separate
maintainer authorization.

## Package ownership

`skia` is a small meta-package depending on `skia-lib` and `skia-doc`.
`skia-lib` provides `skia`, `skia/dc`, `skia/pict`, `skia/racket-draw` and the other
existing public modules. It includes installed diagnostics, Windows acquisition
helpers, native metadata and pin files. Repository audit/build/CI tools remain
at the repository root. Their source-path resolver keeps historical API module
names distinct from their concrete `skia-lib/` paths.

`skia-doc` depends on the library. It owns the 25 registered manuals, navigation,
tutorial copier, all 43 advertised editable assets, four unchanged Noto files,
OFL/copyright notices, and multilingual/Scribble integration tests. There is no
`skia-fonts-1` package or dependency. The library has no dependency on `skia-doc`.
The command remains `raco skia-examples`; the direct module invocation is now
`racket -l skia-doc/tools/copy-tutorial-examples -- ...`.

The native packages redistribute unmodified binaries from the
[SkiaSharp project](https://github.com/mono/SkiaSharp), with original licenses
and third-party notices retained. The approved native pair remains SkiaSharp
3.119.1 / HarfBuzzSharp 8.3.1.2. Existing generation `skia-native-1`, platform
selectors, Linux HarfBuzz isolation, explicit overrides and ABI checks remain.
Supported qualification targets are macOS ARM64/x86-64, Windows x86-64, and
Linux glibc x86-64 (ordinary and real natipkg), on released Racket CS 8.18/9.3.

## Local preparation and validation

The prepared native repository tree is
`output/catalog/windows-native-package/skia-libs/`. It contains the three package
subdirectories, actual native files, metadata and notices. It has no ZIP wrapper,
LFS pointer, or public remote. The per-file comparison and metadata deltas are
recorded beside it. Never flatten a native generation into a shared namespace.

Use a new output directory for every staging/validation run:

```sh
python3 tools/stage-native-catalog.py \
  --racket /absolute/released-racket/bin/racket \
  --cache /absolute/verified-inputs --output output/catalog/candidate-stage \
  --snapshot
```

A clean committed checkout is required for candidate evidence. `--allow-dirty`
labels local implementation experiments and does not certify a committed release.
`--base-catalog /absolute/staged/catalog` can reuse an already staged dependency
closure. Assembly is offline with a cache; dependency acquisition is a separate
phase. All six candidate ZIPs are restored byte-for-byte after catalog staging.

Run the existing `tools/run-catalog-ci.py` platform entry point, or the underlying
validator in an OS network-denied sandbox/container after staging:

```sh
python3 tools/validate-catalog-package.py \
  --runtime /absolute/relocatable-racket \
  --catalog output/catalog/candidate-stage/snapshot/catalog \
  --owned-stage output/catalog/candidate-stage \
  --work output/catalog/candidate-execution \
  --wrong-abi /absolute/locally-compiled-wrong-ABI-fixture
```

The validator uses disposable runtime/home copies and a six-entry directory
catalog whose files are compared with the candidate archives. It proves library
installation without documentation/Noto, adding documentation, independent docs
removal, a separate full dependency installation, ordinary setup and dependency
checks, registered manual builds, both packages' DrDr tests, both text load orders,
core pixels/AV/default-font checks and documentation multilingual coverage.
It also retains loader negatives, ABI rejection, scope/update/rollback/removal,
foreign-target preservation and fresh source/built/binary-library round trips.
Original candidate archives/directories are removed before rebuilt installs.
No source identity is injected into the installable Git package directories.

The full manual Release candidate workflow remains the release evidence gate.
It verifies the exact committed source package set, all existing feature/API/docs
jobs, ten platform/version catalog lanes, and same-run-attempt artifact evidence.
A local pass, historical run or source-only policy check does not replace it.

## Windows managed native package

Windows x86-64 uses the same ordinary dependency-driven installation:

```sh
raco pkg install --auto skia
```

`skia-lib` selects `skia-native-win32-x86_64-1` only for `win32\x86_64`.
The data-only package contains `libSkiaSharp.dll` and `libHarfBuzzSharp.dll` in
`skia-native-1`, with the paired manifest, upstream licenses and component
notices. Racket owns installation, update and removal in the selected scope.
There is no native acquisition script during setup or first rendering. The three
source packages continue excluding native libraries and raw NuGets.

The optional `racket -l skia/tools/install-windows-natives` developer command
still acquires the pinned pair directly from NuGet, with Python 3.12 or later.
Its separate `skia-upstream-1` cache is used only when no managed generation or
installed native dependency exists. A selected broken managed payload fails
clearly. Explicit per-library overrides retain highest precedence. The developer
`--root` route and feature/ABI workflow installers remain available.

The optional cache is separately removed with
`racket -l skia/tools/install-windows-natives -- --remove` after closing native
processes. Ordinary package removal owns the managed Windows payload.
See [Windows validation and evidence](WINDOWS-NATIVE-PACKAGE.md).

## Authorized external phase, later

1. Review/commit this split and run the full existing manual gate on that exact
   commit. Keep the old run as baseline, not evidence for the split.
2. After explicit authorization, create/publish the prepared `skia-libs` Git tree
   and publish the source commit on the intended default branch. No release/tag
   or ZIP host is needed. Record both public repository HEAD commits.
3. Run `tools/prepare-git-catalog.py --help` for the disposable actual Git-fetch
   check. Its six catalog sources use the table above and the resolved commits;
   exercise dependency installation, setup, core/docs tests and removal before
   public registration. Directory/ZIP tests do not prove anonymous Git fetching.
4. Confirm catalog account/contact, name availability and the two repository
   commits. Register the three native packages, `skia-lib`, `skia-doc`, then `skia`
   using the ordinary Git sources. This is a separate publication action.
5. Check the public catalog's actual build/test results and documentation links.

The approved upstream licensing basis is retained. The remaining decisions are
execution/publication decisions in [the preflight](PUBLICATION-PREFLIGHT.md),
not a new licensing investigation.

Racket CS 8.18 testing confirms that `raco pkg create --binary-lib` removes
manual registrations, Scribble manual sources and generated documentation by
definition. The binary-library round trip must retain all four fonts, notices,
43 editable assets, the copier and core rendering/shaping. Full registered
manual/navigation checks apply to source and built round trips. This follows
Racket's package-strip semantics; metadata is not disguised to bypass them.
