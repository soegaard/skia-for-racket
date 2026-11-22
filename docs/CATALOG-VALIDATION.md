# Catalog candidate validation — 0.79

Status: GitHub CI, Acceptance and API inventory passed at `47ebdda3`; eight
catalog execution lanes passed. Both natipkg lanes reached DrDr but exceeded
its unchanged 600-second bound after child processes lost the compiled cache.
**The publication candidate remains unqualified**. No publication action has
been performed. Native pins
remain SkiaSharp 3.119.1 / HarfBuzzSharp 8.3.1.2, native generation/revision 1/1.0.
Source/API collection remains `skia`. The final matrix and maintainer
redistribution approval remain required even when individual local checks pass.

## Fourth GitHub push

The maintainer pushed `47ebdda38738a6eae6914a467b0a898e1d459832`.
[CI](https://github.com/soegaard/skia-for-racket/actions/runs/44971726883) (12 jobs),
[Acceptance](https://github.com/soegaard/skia-for-racket/actions/runs/44971727004)
(52) and [API inventory](https://github.com/soegaard/skia-for-racket/actions/runs/44971726866)
(2) passed. [Catalog packaging](https://github.com/soegaard/skia-for-racket/actions/runs/44971726906)
passed its asset job and all eight macOS, Windows and ordinary Linux execution
lanes. Both actual natipkg lanes failed at DrDr.

All eleven evidence ZIPs matched GitHub's sizes/SHA-256 values before bounded
extraction under ignored `output/catalog/github-fourth-run-20261122/`. Every
staging receipt identifies the same clean source ZIP SHA-256
`497fbeb830372cd677393129413c1f3c343c670519bd59df361cdde0b1acd3e7`
and identical native/font archives. The strict selected-lane verifier accepted
all eight successful execution receipts, including Windows source/built/binary-lib
preservation, installation and removal.

| Catalog target | CS | Commands | DrDr | Observed result |
| --- | --- | --- | --- | --- |
| macOS ARM64 | 8.18 | 83 | 65.168 s | All selected checks passed |
| macOS ARM64 | 9.3 | 83 | 43.671 s | All selected checks passed |
| macOS Intel | 8.18 | 83 | 86.255 s | All selected checks passed |
| macOS Intel | 9.3 | 83 | 74.392 s | All selected checks passed |
| Windows x64 | 8.18 | 83 | 67.562 s | All selected checks passed |
| Windows x64 | 9.3 | 83 | 56.281 s | All selected checks passed |
| Ordinary Linux x64 | 8.18 | 84 | 42.900 s | All selected checks passed, UID 1001 |
| Ordinary Linux x64 | 9.3 | 84 | 64.474 s | All selected checks passed, UID 1001 |
| Actual natipkg x64 | 8.18 | 49 | Timeout, 600.012 s | DrDr incomplete |
| Actual natipkg x64 | 9.3 | 49 | Timeout, 600.027 s | DrDr incomplete |

Both natipkg lanes passed the full runtime bootstrap, dependency snapshot,
ordinary documentation-enabled setup, actual rendering/shaping in both text
initialization orders, negative managed/override cases, bounded CPU tests,
update/rollback, scope/removal and foreign-data checks. The earlier cache-copy
fix worked. Their remaining rebuilt installations are unrun because DrDr failed.

DrDr starts separate Racket processes. The
[test runner](https://github.com/racket/racket/blob/v8.18/pkgs/compiler-lib/compiler/commands/test.rkt)
does not copy the parent's `-MCR` arguments into their command lines. The
[upstream service environment](https://github.com/racket/pkg-build/blob/23cacfcedaead1021dff6bf97ae4a5852af2acfc/private/vm.rkt)
also supplies `PLTCOMPILEDROOTS`; our harness had omitted it. The service's
[documentation](https://github.com/racket/pkg-build/blob/23cacfcedaead1021dff6bf97ae4a5852af2acfc/private/about.rkt)
explains that machine-specific cached code lives separately from the portable
`compiled` trees. The assumption that parent startup flags alone covered all
descendants was incomplete. The 8.18 DrDr log includes static FFI errors such
as `(_fun _Class _string _long -> _Class)` as children bypassed that cache.

The harness now supplies the same reviewed cache through `PLTCOMPILEDROOTS`
during preparation, staging, validation and rebuilt-catalog generation. A real
DrDr subprocess preflight records its executable, version, target, native
execution mode and effective compiled roots. Natipkg evidence requires that
observed child result as well as the original parent profile and all existing
checks. Child processes retain their ordinary native execution mode, matching
the upstream service; the parent still uses its machine-independent compilation
profile. No Racket source, package test set or timeout was changed.

Offline x86-emulated probes of both pinned runtimes reproduced the missing
inheritance: unconfigured DrDr children reported only `same` and failed the
preflight. With the reviewed environment, real DrDr children reported the
owned `zo` root plus `same`, and passed both the preflight and an import of
`ffi/unsafe/objc`. Cache dependency headers confirmed native `ta6le` code. The
original runtime had been removed before these child checks. The diagnostic
bootstrap selected the `racket` collection; these probes do not establish the
full package traversal, rebuilt installations or native timing. Both complete
natipkg lanes must run again at the next pushed commit.

## Third GitHub push

The maintainer pushed `170546e3d373b7edd54e3a414178cce1c89d0eae`.
[CI](https://github.com/soegaard/skia-for-racket/actions/runs/44959239434) (12 jobs)
and [API inventory](https://github.com/soegaard/skia-for-racket/actions/runs/44959239452)
(2) passed. [Acceptance](https://github.com/soegaard/skia-for-racket/actions/runs/44959239520)
passed 50 jobs; the Windows WARP render-canvas lane timed out downloading Racket
in setup-racket (`connect ETIMEDOUT 165.124.149.122:443`) before project tests,
and its required gate consequently failed. This is an acquisition failure;
that lane still needs a successful fresh run.

[Catalog packaging](https://github.com/soegaard/skia-for-racket/actions/runs/44959239445)
passed its asset job and six execution lanes. All eleven retained artifact ZIPs
matched GitHub's sizes/SHA-256 values before bounded extraction under ignored
`output/catalog/github-third-run-20261122/`. Every staging receipt identifies
the same clean source archive SHA-256
`99baff73c7ad0e0647959349ea69f4ab3ac8277120256393a6517676795cbce1`
and identical native/font archives. The strict selected-lane verifier accepted
all six successful execution receipts.

| Catalog target | CS | Commands | DrDr | Observed result |
| --- | --- | --- | --- | --- |
| macOS ARM64 | 8.18 | 83 | 61.670 s | All selected checks passed |
| macOS ARM64 | 9.3 | 83 | 67.118 s | All selected checks passed |
| macOS Intel | 8.18 | 83 | 97.802 s | All selected checks passed |
| macOS Intel | 9.3 | 83 | 115.022 s | All selected checks passed |
| Ordinary Linux x64 | 8.18 | 84 | 54.050 s | All selected checks passed, UID 1001 |
| Ordinary Linux x64 | 9.3 | 84 | 45.714 s | All selected checks passed, UID 1001 |
| Windows x64 | 8.18 | 62 | 68.234 s | Failed binary-lib editable-source retention |
| Windows x64 | 9.3 | 62 | 75.672 s | Failed binary-lib editable-source retention |
| Actual natipkg x64 | 8.18 | 2 | Not run | Copied runtime failed `raco pkg config` |
| Actual natipkg x64 | 9.3 | 3 | Not run | Copied runtime failed ordinary package setup |

The Windows lanes passed the corrected payload/notice ZIP checks through all
three rebuilt forms, then exposed a separate metadata issue. Racket's
[package stripper](https://github.com/racket/racket/blob/v8.18/racket/collects/pkg/strip.rkt)
uses path equality for retention keys. A Windows path created from
`"scribblings/tutorials/squadron/model.rkt"` does not equal the path assembled
by directory traversal. The package now uses `build-path` components for every
nested retention entry. The retained file set is unchanged. A pure regression
evaluates the actual metadata expression with Unix and Windows path conventions
and checks every advertised tutorial asset. All byte-preservation assertions
and ordinary package/documentation tests remain required.

Both actual natipkg versions completed the full upstream bootstrap, `net/url`
import check and dependency snapshot staging before the copied runtime failed.
The earlier assumption that relocating the `zo` root alone relocated its
contents was wrong. Racket's
[compilation paths](https://github.com/racket/racket/blob/v8.18/racket/collects/compiler/compilation-path.rkt)
include the absolute source path under an absolute compiled root. Copying a
prepared runtime leaves its bytecode under the old runtime's key. The 8.18
copy hit the original static FFI error; the 9.3 copy reached ordinary setup
but reported missing `core-syntax.rkt` submodules.

Each owned runtime copy now moves its bootstrapped cache subtree to the copied
runtime's absolute key before executing Racket. Bytecode and dependency bytes
are preserved. Missing caches, symlinks, overlapping paths and destination
collisions fail clearly. Per-environment receipts record the move and compiled
file count; natipkg evidence requires it for every disposable runtime. No Racket
source is patched, and full upstream bootstrap, ordinary documentation-enabled
setup, network denial, DrDr, shaping/rendering and rebuilt installation checks
remain mandatory. Fresh native GitHub execution is required before qualification.

Local metadata/pure tests passed all 12 cases on released macOS ARM64 Racket
8.18 and 9.3 with dependencies staged and networking denied. The actual metadata
expression retains every advertised tutorial asset under both path conventions.
Offline x86-emulated Linux probes bootstrapped the `racket` collection for each
pinned installer, then exercised copies after removing the original runtime.
Both corrected copies passed imports, package configuration and ordinary source
compilation. The unfixed 8.18 copy reproduced the static FFI failure; the 9.3
import-only probe also passed without rekeying, so that narrow probe does not
reproduce or qualify its full package-setup failure. These are diagnostic cache
tests, not complete native catalog qualification. Production still uses the
complete upstream bootstrap and all existing package checks.

## Second GitHub push

The maintainer pushed `d75b82d4a3599aa299a79fd093bc2622c0f92352`.
[CI](https://github.com/soegaard/skia-for-racket/actions/runs/44940434255) (12 jobs),
[Acceptance](https://github.com/soegaard/skia-for-racket/actions/runs/44940434311) (52)
and [API inventory](https://github.com/soegaard/skia-for-racket/actions/runs/44940434318)
(2) passed. [Catalog packaging](https://github.com/soegaard/skia-for-racket/actions/runs/44940434237)
passed its asset job and seven execution lanes; three lanes failed.

All retained staging receipts identify the same clean source ZIP SHA-256
`665fe01fc6e3e45d65afe1f7af8f82df7e85c245a9cb95e6569239a3029ae5fb`
and identical native/font ZIPs. All ten downloaded evidence artifact ZIPs were
checked against GitHub's sizes/SHA-256 values before bounded extraction under
ignored `output/catalog/github-second-run-20261121/`.

| Catalog target | CS | Commands | DrDr | Observed result |
| --- | --- | --- | --- | --- |
| macOS ARM64 | 8.18 | 83 | 72.758 s | All selected checks passed |
| macOS ARM64 | 9.3 | 83 | 141.526 s | All selected checks passed |
| macOS Intel | 8.18 | 83 | 87.972 s | All selected checks passed |
| macOS Intel | 9.3 | 83 | 82.985 s | All selected checks passed |
| Ordinary Linux x64 | 8.18 | 84 | 43.434 s | All selected checks passed, UID 1001 |
| Ordinary Linux x64 | 9.3 | 84 | 46.718 s | All selected checks passed, UID 1001 |
| Actual natipkg x64 | 9.3 | 85 | 75.066 s | All selected checks passed, UID 1001; service bootstrap/profile review below |
| Windows x64 | 8.18 | 56 | 68.985 s | Failed during source archive payload comparison |
| Windows x64 | 9.3 | 56 | 71.422 s | Failed during source archive payload comparison |
| Actual natipkg x64 | 8.18 | Not started | Not run | Catalog preparation failed |

The Windows lanes passed full documentation setup, actual rendering/shaping,
negative loader cases, update/rollback, scope/removal, foreign data, DrDr,
read-only source and the example copier. Rebuilding exposed a harness error:
it indexed ZIP members with Windows backslashes, such as
`licenses\BUILD-EVIDENCE.json`. Expected members now use POSIX separators while
preserving the complete nested directories. A cross-platform regression uses
real file reads with Windows-style relative paths and duplicate notice basenames;
no file is flattened or omitted from the preservation check.

### Natipkg runtime assumption corrected

The untouched official 8.18 installer reports the actual natipkg target, but
plain `require net/url` fails with `compile: unable to generate foreign function
statically: (_fun -> _ulong)`. The same failure reproduced without Skia in a
fresh network-disabled Debian container using the exact installer SHA-256.
Identity and `setup/getinfo` probes passed. Source-only loading passed, while
ordinary native compilation and `-MCR` before bootstrap still failed.

The [upstream Docker example](https://github.com/racket/pkg-build/blob/23cacfcedaead1021dff6bf97ae4a5852af2acfc/examples/docker/build.rkt)
requires compile-any settings consistent with the selected installer. Its
[runtime installation](https://github.com/racket/pkg-build/blob/23cacfcedaead1021dff6bf97ae4a5852af2acfc/private/install-step.rkt)
and [startup configuration](https://github.com/racket/pkg-build/blob/23cacfcedaead1021dff6bf97ae4a5852af2acfc/private/vm.rkt)
include `raco setup --recompile-only` with `-MCR` and a private `zo:` cache.
The earlier assumption that the target subpath alone established the complete
service configuration was incomplete. The 9.3 result remains genuine functional
evidence, but both natipkg versions must be rerun with the full service profile.

The preparer now performs that upstream bootstrap in an isolated home, checks
an actual `net/url` import, and only then records a ready runtime profile. All
subsequent Racket commands preserve its startup flags and relocated cache.
Evidence checks require the profile and actual machine-independent compile target.
No Racket source, installer hash, native pin or supported target was changed.
Package installation still builds all registered manuals and runs all existing
qualification checks. The bootstrap is not a package documentation shortcut.

Local QEMU diagnosis reached standard-library recompilation but the full
bootstrap exceeded its 360-second diagnostic bound. After Racket's setup
initialization, `net/url` and the actual catalog writer passed under `-MCR`.
Detailed failed/partial diagnostic commands are retained in
`output/catalog/github-second-run-20261121/probe-options.json`. These results do
not qualify the full bootstrap, native Linux timing or package installation.
The candidate uses the complete supported upstream command, and fresh native
GitHub execution remains required.

Preparation errors now retain a failed JSON receipt and bounded metadata log;
they cannot turn a failed job into a pass or substitute for installed execution
evidence. The native approval flags and `catalog_candidate_validated` remain false.

## First GitHub push

The maintainer pushed `codex/catalog-ci` at
`487ff1489464e83f5916fd5139a7e9a963394e01`. Attempt 1 completed on November 21,
2026. This is GitHub Actions execution against disposable staging catalogs;
nothing was submitted to the Racket package server.

| Workflow | Result | Jobs |
| --- | --- | --- |
| [CI](https://github.com/soegaard/skia-for-racket/actions/runs/44929473832) | Passed | 12 |
| [Acceptance](https://github.com/soegaard/skia-for-racket/actions/runs/44929473902) | Passed | 52 |
| [API inventory](https://github.com/soegaard/skia-for-racket/actions/runs/44929473829) | Passed | 2 |
| [Catalog packaging](https://github.com/soegaard/skia-for-racket/actions/runs/44929473901) | Failed | Asset job and four macOS lanes passed; six execution lanes failed |

Every retained platform staging receipt identifies the same clean source ZIP,
SHA-256 `93f6edd5e00b196d8da6bcc006ac0f54fb421ad409ebc9aab41f936cf8133c86`,
and the same four native/font ZIP digests. The asset upload contains exactly six
JSON receipts/digests; no candidate ZIP was uploaded. Downloaded evidence ZIP
sizes and SHA-256 values were checked against GitHub's artifact records before
bounded extraction into ignored `output/catalog/github-first-run-20261121/`.

| Catalog target | Racket CS | Commands | DrDr | Result |
| --- | --- | --- | --- | --- |
| macOS ARM64 | 8.18 | 83 | 60.427 s | Complete selected checks passed |
| macOS ARM64 | 9.3 | 83 | 64.702 s | Complete selected checks passed |
| macOS Intel | 8.18 | 83 | 90.166 s | Complete selected checks passed |
| macOS Intel | 9.3 | 83 | 68.112 s | Complete selected checks passed |

Those receipts include dependency-driven full documentation setup, denied
network execution, both text load orders, negative loader cases, scope/update/
removal behavior, read-only source and all three rebuilt-package reinstalls.
They identify `487ff148`, not the subsequent follow-up changes.

The failed lanes remain failed:

- Both Windows lanes installed, built manuals and completed the first actual
  pixel/PNG/script-shaping smoke. The Python harness rejected a reported DLL
  path. Racket emitted literal UTF-8 `æ`; the harness used the host default
  text codec. A regression reproduces the resulting mojibake with CP1252;
  command logs now decode explicitly as UTF-8. Containment and file-existence
  checks remain mandatory, with separate diagnostics. A Windows rerun is required.
- Ordinary Linux 8.18 completed 48 commands through DrDr, where the font-fallback
  regression assumed a system CJK face. It now uses the original AV-only font
  fixture, proves B is absent, and unconditionally requires a Latin fallback
  from the declared platform font baseline. Separate declared-font tests still
  require CJK/Arabic/Hebrew shaping. No test is omitted or made conditional.
- Linux 8.18's receipt identified `/usr` as its runtime source. Linux 9.3's
  [runner annotation](https://github.com/soegaard/skia-for-racket/actions/runs/44929473901/job/136922721838)
  reports a full disk; its job log and evidence artifact are unavailable.
  The default setup action installed a Unix-style tree into `/usr`, which the
  harness mistakenly copied wholesale. The workflow now selects an in-place
  directory under `runner.temp`, and the harness rejects system-prefix layouts.
  Linux execution also returns to the ordinary runner UID after namespace
  creation (or selects it in Docker). Root execution is rejected by both the
  validator and evidence checker, so read-only source permissions cannot be
  bypassed by the qualification process.
- Both natipkg jobs stopped at HTTP 403 from the official release download URL,
  before Racket installation or package execution. The reviewed official mirror
  is now a bounded transport fallback with unchanged installer digest pins,
  HTTPS-only redirects and an acquisition receipt. Changed/oversized bytes still
  fail immediately; no unverified installer is executed.

Source/harness tests and local native diagnostics check the follow-up, but only
fresh GitHub execution can close the Windows/native Linux matrix gaps. Separate
workflow successes do not replace the eventual full same-attempt release gate.
Native approval flags and `catalog_candidate_validated` remain false.

## Exact identities

Implementation began at `e944213d0fac4b02ef81bb35beb1e26729aca8f7` with the
existing planning changes preserved. The final successful local runs used
source ZIP SHA-256
`13c0ca48a0613d7014bbf205bc24a1a11fb4a5df3e8a0b27d0a4a7cc5510b6f8`
(Racket SHA-1 `d10512f879821aa91ef0fdb7c032c79013cf78ad`, 1,667 files).
That ZIP records observed HEAD `e944213d` and `source_worktree_clean: false`.
It includes the implementation and then-current planning changes.

The implementation was subsequently committed as `da4d59b9`. This did not
change the identity of the tested ZIP or turn its receipts into clean-commit
release evidence. A new committed candidate, new archives and new execution
receipts are required for release qualification. The publication plan and its
index entry are included in the next candidate under the maintainer's explicit
November 21 instruction, without discarding their existing content.
The checked-in `packaging/native-assets.json` identifies all original archives,
component texts, source commits, font hashes, observations and pending review.

Released macOS ARM64 Racket 8.18/9.3 runtimes were independently checked against
the official release-page SHA-256 values. The ordinary shell Racket 8.12 and
the development Racket under an application directory named 9.3 are not release
qualification substitutes. The development runtime is used only for explicitly
labelled source/pure diagnostics.

During the historical Linux probes, Docker was ARM64 with Rosetta disabled by
the operator. The Linux container was
x86-64 under QEMU, Debian 12, image
`sha256:66faed12f86f6ef4f2be913ea97e769a2dc20b86738a1203e43a803885638634`.
It had no OS fontconfig and no external network interface/route. Real official
Racket 9.3 pkg-build reports `x86_64-linux-natipkg`; its installer SHA-256 is
`2d2daf7afd6656641b13b52663f027e1f9717abc1e2d134fb73bb5df22f0daca`.
QEMU functional evidence does not establish native Linux catalog throughput.

## Commands and retained evidence

The [runbook](PACKAGE-PUBLICATION.md) supplies reproducible acquisition,
assembly, staging, OS isolation and validator commands. Generated candidate
ZIPs/checksums/receipts and detailed command arrays/logs are under ignored
`output/catalog/`; `result.json` records command arguments, exit codes, timings
and checks, with failures retained. Initial local runs are diagnostic iterations,
not substitutes for one complete final-candidate matrix.

Executed source checks include `python3 tools/test-native-packages.py` (28
adversarial archive/identity/format/checksum tests),
`python3 tools/test-catalog-packaging.py` (strict partial/mismatched evidence
rejection), and the repository CI/release/API contract regressions. Exact final
commands, counts, archive identities and run status are retained separately in
`output/catalog/local-validation-report.json` and its linked logs/receipts, so a
result report does not change the source ZIP it describes. Source checks must
be repeated after the deliberate frozen-policy review; an input-drift failure
is not waived or treated as an API execution pass. The final source/synthetic
run passed all 54 scripts (3,099 tests), and the separate Reference run passed
586 tests. Those results are recorded in the local report; the new candidate's
changed source and frozen policy inputs must be checked again.

The native directory prototype completed both macOS runtime versions with
source/built/binary-lib preservation, compatible update/rollback, exact scope
rejection/removal and unrelated-directory ownership. Original Stage A reports
remain in `output/catalog/evidence-macos-8.18` and `evidence-macos-9.3`.
Those explicit-override/bootstrap probes alone did not qualify the new loaders.

## Final successful local runs

| Released Racket CS | Target | Result | DrDr | Receipt directory |
| --- | --- | --- | --- | --- |
| 8.18 | `aarch64-macosx` | All local validator checks passed | 22.513 s | `output/catalog/final-evidence/macos-arm64-8.18/` |
| 9.3 | `aarch64-macosx` | All local validator checks passed | 20.216 s | `output/catalog/final-evidence/macos-arm64-9.3/` |

Each final run completed 83 commands against the identical source ZIP above
and the same native/font archives. Its `result.json` reports
`passed-local-selected-checks`; every required check is true. The corresponding
`staging-receipt.json` binds the source, lock, complete dependency snapshot and
candidate archive hashes. All command logs are retained beside those receipts.

Both runs passed ordinary dependency-driven installation with all registered
manuals enabled, dependency checking, denied-network execution, actual CPU
pixels/PNG and HarfBuzz shaping in both text load orders, broken-payload and
wrong-architecture/ABI rejection, override precedence and lazy imports,
read-only first use, update/rollback, scope/removal ownership and unrelated-file
preservation. Foreign-target packages remained inert during setup and retained
their data when rebuilt.

Source, built and binary-library forms preserved native/data/notice bytes and
all 43 advertised editable tutorial files. After removing the original
environment and catalog-visible candidate archives, all three rebuilt forms
installed in fresh environments, rendered/shaped in both orders, copied the
shaping example and removed their managed generation successfully. These final
runs supersede the earlier copier failure below for this dirty local snapshot.

Both receipts still report `catalog_candidate_validated: false`. They establish
local behavior on macOS ARM64, not the complete platform matrix, redistribution
approval, or a same-attempt release run for a clean committed candidate.

## Retained failed iterations and Linux diagnostics

The exact source ZIP `1d6eea743145fe8f919b4cc07fb83709c9dbee2cb17c053c16bb2f6ba7bebbaf`
was staged with all native/font candidates unchanged on macOS ARM64 at both
released versions. In `/private/tmp/skia-bf-mac-8.18-run-2` and
`/private/tmp/skia-bf-mac-9.3-run-7`, ordinary setup built every registered manual
with networking denied. Dependency checking, both text load orders, CPU pixel/
PNG/script shaping tests, missing/corrupt/wrong-pair/generation/architecture/ABI
rejections, override precedence, read-only source, compatible update/rollback,
scope ownership/removal and actual DrDr passed. DrDr took 17.109 and 20.140
seconds respectively. Source and built reinstalls and removal passed after the
original environment and all catalog-visible candidate archives were removed.
Binary-library installation and both rendering/shaping orders passed too, but
the editable example copier failed; these runs therefore remain **failed**.

That failure exposed Racket's nonrecursive source-keep semantics. Explicit
metadata now retains all 43 files in the advertised tutorial catalog. A local
diagnostic rebuilt the corrected binary-library package, checked all 43 byte
identities and copied the shaping tutorial successfully. Separate foreign-target
tests installed and repeatedly set up the Windows/Linux packages as inert data
on macOS, rebuilt binary-library forms with every payload/notice retained, and
removed them. The final successful fresh runs above include both the complete
editable-source preservation checks and the foreign-target checks. Their
receipts are distinct from these retained failed iterations.

The natipkg fontconfig 2.13.0 fix passed actual asymmetric pixels, PNG and Latin/
Arabic/Hebrew/CJK shaping with both Draw-first and Skia-first initialization and
no manual native/fontconfig override. This diagnostic overlaid the new loader
in a disposable prior installation, then used ordinary native-package update/
setup; it is **not** a complete fresh-source qualification. A subsequent fresh
full-doc installation used candidate ZIPs and a complete Linux dependency
snapshot in internal Docker `/work`, with `--network none` and no OS fontconfig,
but was interrupted when Docker became unavailable. After reopening Docker,
the `desktop-linux` context could not find the original container. Its complete
internal receipt could not be recovered; no successful fresh setup, DrDr or
rebuilt-form result is claimed. The host observation is recorded in
`output/catalog/final-evidence/linux-interrupted.json`.

The QEMU runtime's first identity
and package-config processes took 117.435 and 157.802 seconds. Native Linux
timing qualification remains required. The earlier successful rendering and
load-order diagnostics do not close the interrupted fresh-run gap.

## Findings corrected during B–F

* Original NuGet combined notices omitted Wuffs and were not a current link map.
  Exact pinned supplemental texts, full Adobe DNG terms/patents, FreeType
  acknowledgement and static GCC runtime terms are now retained.
* The public API has no directory-font-manager constructor. Script tutorials
  load declared Noto files through existing `typeface-from-file`; the data
  package also provides licensed CJK coverage to the bounded tests.
* Catalog dependency metadata must include build dependencies; otherwise
  catalog-archive misses the registered manuals' closure.
* Ordinary setup built the manuals offline, but dependency checking exposed
  undeclared `pict-doc`. It is now declared explicitly.
* The new default picture/pict smoke found that native inexact extents failed
  the old exact-pixel guard. The finite checked ceiling now becomes an exact
  allocation count, with a regression; no public API/feature was added.
* Actual DrDr traversal also discovers editable `.rkt` downloads copied under
  generated `doc/`. Those output assets are explicitly excluded; source tests
  remain mandatory and manuals/examples retain their existing dedicated gates.
* Racket's catalog archiver repacks even local candidate ZIPs. The stager restores
  the original bytes/checksums and catalog records, then binds the complete
  dependency graph and every staged archive hash into its execution receipt.
  Earlier repacked snapshots are retained as diagnostics and rejected by the
  exact-candidate preflight.
* Built/binary-library metadata is rewritten by Racket. All data/native/notice
  bytes remain exact; a separate metadata comparison allows only Racket's
  documented package-state and copy-to-move conversion.

## Required external qualification and decisions

The first GitHub attempt now supplies complete macOS ARM64/Intel results on both
released versions, as recorded above. Windows clean-PATH/dependent-DLL behavior,
source stripping and update/remove after process exit still require complete
successful catalog reruns. Native x86-64 Linux timing, the actual natipkg build-service
configuration and ordinary fontconfig baseline must be qualified independently
of Apple-silicon emulation. Deployment/load-command observations do not by
themselves certify older OS releases or every distribution at glibc 2.27.
Linux ARM64, musl, 32-bit and BC are not newly supported targets.

Maintainer redistribution review remains pending: exact embedded graph/runtime
attestation and GCC exception applicability, Adobe conditions and Windows
redistribution terms. Proposed package names/version and public availability
need a separate final review. The maintainer pushed the GitHub test branch;
the agent does not push, publish, tag, create repositories, register catalog
entries or change repository settings.
The release aggregator refuses to approve incomplete/pending catalog evidence.
