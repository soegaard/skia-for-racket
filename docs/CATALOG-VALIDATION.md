# Catalog candidate validation — 0.79

Status: implemented packaging with local qualification still in progress; **not a validated
publication candidate**. No publication action has been performed. Native pins
remain SkiaSharp 3.119.1 / HarfBuzzSharp 8.3.1.2, native generation/revision 1/1.0.
Source/API collection remains `skia`. The final matrix and maintainer
redistribution approval remain required even when individual local checks pass.

## Exact identities

Implementation began at `e944213d0fac4b02ef81bb35beb1e26729aca8f7` with the
existing unrelated `plans/README.md` modification and untracked publication plan
preserved. Local ZIPs include the working-tree changes and explicitly report
`source_worktree_clean: false`. They are not presented as an accepted commit.
The checked-in `packaging/native-assets.json` identifies all original archives,
component texts, source commits, font hashes, observations and pending review.

Released macOS ARM64 Racket 8.18/9.3 runtimes were independently checked against
the official release-page SHA-256 values. The ordinary shell Racket 8.12 and
the development Racket under an application directory named 9.3 are not release
qualification substitutes. The development runtime is used only for explicitly
labelled source/pure diagnostics.

Docker is ARM64 with Rosetta disabled by the operator. The Linux container is
x86-64 under QEMU, Debian 12, image
`sha256:66faed12f86f6ef4f2be913ea97e769a2dc20b86738a1203e43a803885638634`.
It has no OS fontconfig and no external network interface/route. Real official
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
is not waived or treated as an API execution pass.

The native directory prototype completed both macOS runtime versions with
source/built/binary-lib preservation, compatible update/rollback, exact scope
rejection/removal and unrelated-directory ownership. Original Stage A reports
remain in `output/catalog/evidence-macos-8.18` and `evidence-macos-9.3`.
Those explicit-override/bootstrap probes alone did not qualify the new loaders.

## Integrated local execution and retained failures

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
removed them. Final fresh runs must include these added checks. Their receipts
are distinct from the retained failures above.

The natipkg fontconfig 2.13.0 fix passed actual asymmetric pixels, PNG and Latin/
Arabic/Hebrew/CJK shaping with both Draw-first and Skia-first initialization and
no manual native/fontconfig override. This diagnostic overlaid the new loader
in a disposable prior installation, then used ordinary native-package update/
setup; it is **not** a complete fresh-source qualification. A fresh full-doc
installation uses the same candidate ZIPs and complete Linux dependency
snapshot in internal Docker `/work`, with `--network none` and no OS fontconfig.
All commands and failures remain retained. The QEMU runtime's first identity
and package-config processes took 117.435 and 157.802 seconds. Native Linux
timing qualification is required even if this emulated functional run succeeds.

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

Independent macOS x86-64 and Windows x86-64 execution is unavailable locally.
Both versions on those runners, Windows clean-PATH/dependent-DLL behavior,
source stripping, update/remove after process exit, and universal-slice evidence
remain required. Native x86-64 Linux timing, the actual natipkg build-service
configuration and ordinary fontconfig baseline must be qualified independently
of Apple-silicon emulation. Deployment/load-command observations do not by
themselves certify older OS releases or every distribution at glibc 2.27.
Linux ARM64, musl, 32-bit and BC are not newly supported targets.

Maintainer redistribution review remains pending: exact embedded graph/runtime
attestation and GCC exception applicability, Adobe conditions and Windows
redistribution terms. Proposed package names/version and public availability
need a separate final review. There is no authorization to publish, tag, push,
create repositories, register catalog entries or change repository settings.
The release aggregator refuses to approve incomplete/pending catalog evidence.
