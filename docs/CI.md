# GitHub Actions CI

## Required raster canvas GUI gate — 0.58

The new `canvas` job runs `tools/ci.py --profile canvas --id canvas-linux-x64`
on the pinned Linux x64 / Racket 9.3 identity. It uses the same isolated source
ZIP installation, dependency setup, fresh native installers, ABI checks and
pre-native GUI-free imports as the established package jobs. Only the final
`validate-skia-canvas.py --require-gui --manifest-only` command runs under an
Xvfb display created for that subprocess. Existing CPU and EGL profiles retain
their display-free environment and do not start Xvfb.

The canvas validator requires 38 pure lifecycle cases, 14 native backing/bitmap
transfer cases and 15 actual GUI/eventspace cases. Fresh subprocesses also
verify GTK-first and Skia-first loading, with both Skia and ordinary Racket
text rendering required in each process. The headless suites also run
through `run-tests.rkt`; the pure suite runs before native installation. The
GUI suite, load-order probes and `skia/canvas` are explicitly omitted from
headless `raco test` discovery. `tools/test-validate-skia-canvas.py` and the CI-driver regressions
check required-GUI/failure reporting without treating mocks as GUI execution.

`CI required` includes the `canvas` result. A headless-only validator pass,
missing GUI report, zero case count, failed native bridge, failed text
coexistence probe or failed GUI process cannot satisfy the lane. Reports and logs are retained under
`output/ci-canvas-linux-x64/skia-canvas/`, together with installation, identity,
source and native-provenance evidence in the parent artifact. Partial evidence
is kept on failure. Xvfb validates tested widget/eventspace behavior at its
reported scale; it does not certify physical screen pixels or macOS Retina
monitor transitions. Run the [host review](SKIA-CANVAS.md#validation-and-acceptance)
for those properties.

The existing 0.57 DC gate, 20 retained DC PNGs, all native pins and all GPU
jobs/workloads remain unchanged. Its validator and capabilities continue to
report the 0.57 drawing contract. A successful new 0.58 run is required;
adding the workflow is not itself acceptance.

## Retained styles/compatibility gate — 0.57

The installed-package DC validator now requires 148 pure and 149 native cases,
plus the existing 24 alpha-controller and new 45 style-math subchecks. Four new
64x64 style captures independently check gradients, stipples, hatches, opacity
and legacy styles; direct/procedure/datum Skia images agree within two channel
units. Reference edge differences are retained without universal equality claims.
The consolidated review retains 20 PNGs, including all previous exact oracles.
Missing/failing style evidence fails the parent gate. Both new RackUnit suites
also run through run-tests.rkt, with the pure suite before Skia installation.
Only the private region-utility query bridge creates a scratch Cairo context;
it has no access to Skia pixels and is not a drawing fallback. Minimum Racket
8.18, dependency pins and all existing GPU CI workloads remain unchanged.

## Real-consumer gate introduced in 0.56

The existing installed-package DC gate additionally requires sixteen native
consumer cases and eight pict/plot captures. Its complete coverage is now
124 pure + 109 native DC cases, plus the existing controller subchecks.
Every new capture has semantic probes. Same-recording procedure/datum images
are compared within two channel units; direct/reference images are retained
for review, not certified pixel-identical. See [DC-CONSUMERS.md](DC-CONSUMERS.md).

Missing/failed child reports, changed identities, incomplete captures and
failed consumer inspection block the parent DC gate. All sixteen old/new PNGs
and logs remain in the existing dc-foundation artifact directory. The source
lane runs the consumer inspector regressions through test-dc.py. The minimum
Racket version, workflow jobs, native pins and GPU workloads are unchanged.

## DC replay/alpha gate introduced in 0.55

The required minimum remains Racket CS 8.18 / draw-lib 1.22. The existing
installed-package `validate-dc.py` gate now runs 124 pure and 93 native cases,
including both replay forms and nested alpha. Its pure suite invokes another
24 standalone production-controller cases without claiming native execution.
Both existing exact oracles are unchanged; three new direct/procedure/datum
alpha captures are checked against independent compositing math with a fixed
maximum error of two 8-bit channel units. All eight PNGs and command logs are
retained under `dc-foundation/`, including partial evidence on failure.

The two new RackUnit suites also run in `run-tests.rkt`; pure replay must work
before Skia installation. Missing images, count reductions and failed commands
block success. Text samples do not certify Cairo/Pango glyph equivalence.
The source manifest and all established CPU/GPU jobs/workloads remain required.
No `pict`, plot, style-expansion, GUI or GPU-facade acceptance is claimed here.

## Workflow and required result

`.github/workflows/ci.yml` runs for pull requests, pushes to `main`, version tags
starting with `v`, and manual dispatch. The source lane publishes the validated
matrix from `tools/ci-matrix.json`; five CPU lanes and two EGL lanes then run
without fail-fast cancellation between matrix entries. `CI required` runs even
when a prerequisite fails. It accepts only `success` for all six groups: source, CPU, EGL, D3D12, DXGI
and raster canvas;
`skipped` and `cancelled` do not count as passes.

Automatic stage acceptance is grouped under `.github/workflows/acceptance.yml`
instead of giving every historical stage its own push/pull-request run. A normal
push to `main`, a `v*` tag push, or a pull request therefore creates three
top-level workflows: `CI`, `API inventory`, and `Acceptance`. The stage-specific
workflow files remain individually dispatchable and reusable: they expose
`workflow_call` plus `workflow_dispatch`, while the `Acceptance` workflow calls
all thirteen and publishes `Acceptance required`. No stage-specific acceptance
workflow has its own `push` or `pull_request` trigger.

This changes orchestration only. The called workflows keep their existing
Linux/Windows matrices, native setup, validators, retained artifacts, and failure
semantics; grouping them does not count as new execution evidence or reduce the
accepted backend coverage.

After the first successful workflow, select **CI required** as the required
status check in the repository's branch protection/ruleset. This delivery does
not change repository settings. A workflow file cannot enable branch protection
by itself, and it is not evidence of a successful run.

The Linux headless acceptance deferred in 0.43 passed both required EGL lanes
in 0.46 Actions run `36620003104` at commit
`808befa8768e672238e3fcdc5288e497a8b2705f`. Both lanes used Mesa llvmpipe
without a display server. This establishes software EGL/OpenGL/Ganesh
functionality, not hardware acceleration. The current
[coverage matrix](PORTABILITY.md) distinguishes that evidence from historical
macOS hardware validation and from the hosted CPU-only lanes.

## Clean installation, not a checkout link

`tools/ci.py` resolves one Racket executable and uses it for every Racket/raco
command. Its identity must match the lane's OS, architecture, CS VM, release and
64-bit pointer size. Python's architecture is not used as a substitute.

The driver verifies the committed source manifest and creates a deterministic
source-only ZIP. Generated/compiled files and native binaries are rejected. It
installs that ZIP into a new Racket user home and addon directory, resolves the
`skia` collection there, and verifies every installed source byte against the
checkout. The source ZIP is then deleted. Working directories are deliberately
outside the checkout and the installed package, with spaces in their paths.

Native and collection-path overrides are removed. Before native installation,
a subprocess imports `skia`, `skia/bitmap` and the non-GUI optional GPU modules
with deliberately nonexistent native overrides, checks that `racket/gui/base`
was not initialized, and runs the pure suite. No import is allowed to require a
working GPU, GUI or installed Skia/HarfBuzz binary.

Existing installers then fetch pinned assets **inside the installed copy**.
No native or compiled cache is restored. The Windows installer verifies the
selected Racket and PE/DLL architecture; Unix installers select their documented
native packages. Downloaded archive hashes are provenance, not independent
signature/authenticity verification. HTTPS/NuGet remains the trust boundary.

The installed package runs `raco setup --check-pkg-deps`, twelve C ABI mirrors
through CMake/CTest (MSVC on Windows; the system C compiler elsewhere), native
symbol resolution and a raster/PNG smoke. The smoke records the actual loaded
library paths, versions and SHA-256 values; libraries outside the installed
package are rejected. CPU lanes run all CPU/native regressions and GPU pure
suites. Unix lanes additionally run exported-symbol audits. Windows uses native
symbol resolution plus the PE checks, not an invented Unix `nm` result.

These C tests are the project's pinned layout/prototype mirrors, **not** proof
that arbitrary newer Skia libraries are ABI-compatible.

## Required Linux EGL lanes

The EGL lanes use the same independently installed package and full
`tools/validate-gpu-headless.py` sequence. Every child process has `DISPLAY`,
`WAYLAND_DISPLAY` and `MIR_SOCKET` removed. No X server, Xvfb or hidden GUI host
is started. Mesa is explicitly requested with `LIBGL_ALWAYS_SOFTWARE=1` and
`GALLIUM_DRIVER=llvmpipe`; diagnostics must actually identify software llvmpipe
and the assembled desktop-GL EGL interface.

The platform is explicitly `surfaceless`, device index zero; the two lanes
select `surfaceless` or `pbuffer` binding surfaces. An EGL pbuffer is not a
window. `GPU_MODE=required`, with no optional initialization escape, is enforced.
The driver rejects skipped checks, incomplete/foreign run identities, wrong
renderer classifications, missing inspections and any window/presentation claim.

The sequence retains CPU regressions, EGL lifecycle, 33 surface cases, 42 image
cases, 32 interop cases, rendering workflows, 42 document cases and actual
PDF/SVG inspection, 20 native cache cases, benchmarks and retained-resource
stress. The 0.45 defaults (three cycles of 180 frames) are not reduced for CI.
Software benchmark timings are not hardware-performance evidence or speed gates.
Physical window presentation remains outside these headless jobs.

## Source manifests

The ordinary local validators still update `SOURCE-SHA256SUMS.txt` **last**, after
all selected checks pass. Commit that file along with changes, including new
workflow files. `tools/update-source-sums.py --check` instead verifies both the
Git source inventory and file contents, without modifying the manifest.

CI sets `SKIA_SOURCE_SUMS_MODE=check`. Installed source archives contain no Git
metadata, so the headless runner additionally uses
`SKIA_SOURCE_SUMS_MANIFEST_ONLY=1`. In that explicit mode every manifest-listed
source byte is verified, but there is no independent Git-inventory claim. The
checkout inventory was checked before archive creation and is checked again at
the end. Runtime native assets and compiled/output files are not source entries.

`.gitattributes` keeps text checkouts at LF on Windows as well as Unix, while
binary fixtures stay binary. Stale, malformed or unsafe manifests fail; CI never
regenerates one to turn an otherwise invalid checkout green. New unignored files
must be included; stage tracked deletions before locally regenerating the file.

## Artifacts and failure behavior

Each lane writes `output/ci-<id>/`: `ci-report.json`, `commands.json`, the job
summary, numbered complete stdout/stderr logs, and native provenance. EGL lanes
also copy the raw diagnostic/inspection JSON, CSV, HTML reviews, and actual
PNG/PDF/SVG files from the installed package before deleting the temporary home.
These files are retained on later failure as well as success. A failed or missing
inspection is not replaced with a fabricated success report.

Actions uploads these directories with `always()` and retains artifacts for 14
days. An action-installation or OS-package-installation failure occurring before
the driver starts is visible in the Actions step log; it need not have a driver
artifact. Native binaries, font files, NuGet archives, compiled Racket files,
credentials and the whole user home are not uploaded.

Commands have a 20-minute default timeout; timeouts fail the job, terminate the
child process group/tree, and preserve logs. Whole-job timeouts are an additional
limit. There are no ignored test exits, `continue-on-error` GPU lanes, or
runtime fallbacks from required EGL to another rendering route.

## Local commands

The usual maintainer sequence remains:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket" bash tools/validate-gpu.sh
python3 tools/update-source-sums.py --check
```

To run only the CI infrastructure regression tests (no native/GPU execution):

```sh
python3 tools/test-ci.py
python3 tools/ci_matrix.py
```

To reproduce an exact installed-package lane, use Python 3.12 or newer, Git,
CMake/CTest, the listed OS dependencies, and the **released Racket pinned in that
lane**. For example, on Linux x64 with Racket CS 9.3 on PATH:

```sh
python3 tools/ci.py --profile cpu --id linux-x64
python3 tools/ci.py --profile egl --id egl-surfaceless
python3 tools/ci.py --profile egl --id egl-pbuffer
```

Other exact ids are `macos-arm64`, `macos-x64`, `windows-x64`, and
`minimum-racket` (CS 8.18). Set `RACKET` to the complete executable path when it
is not on PATH. Development snapshot 9.3.0.2 intentionally does not masquerade
as the matrix's released 9.3. Archive/move an existing `output/ci-<id>` before
rerunning that lane: stale success directories are not reused automatically.
The local source profile is Linux-only because it runs the existing Unix static
installer tests; `test-ci.py` itself is cross-platform.

## Workflow security and maintenance

All external actions are pinned to complete commit SHAs. Checkout credentials
are not persisted; workflow permissions are read-only. Pull requests run on
fresh GitHub-hosted runners and do not use secrets, privileged events or
self-hosted hardware. No package/native/build cache is shared between jobs.
Dependabot proposes action-pin updates for review; native/ABI migrations remain
separate work. Add future self-hosted GPU jobs only with an explicitly reviewed
trusted-code and runner-isolation policy, not automatic execution of fork PRs.

The chosen actions and runner labels were checked against their primary docs:
[runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[setup-racket](https://github.com/Bogdanp/setup-racket/tree/2466913449df77df2bad149d1f2fc4e1ea4795dd),
[Racket package installation](https://docs.racket-lang.org/pkg/cmdline.html),
[package dependency checks](https://docs.racket-lang.org/raco/setup-check-deps.html).
Older versioned inspectors retain their historical baseline-status notes.
The 0.46 `ci-report.json` identifies what the current CI lane actually verified;
a desktop report never certifies a separate Linux run. Updating action pins also
requires refreshing the source manifest before the update can pass CI.

A pinned action does not freeze hosted OS images, NuGet infrastructure or distro
packages. Preserve run metadata when comparing later results.

GPU format/property acceptance (0.73) is a reusable child of Acceptance, not a new push-triggered run. It requires native format/precision checks on Linux Mesa and Windows WARP; Metal remains available through the same local validator.

0.74 advanced layer/drawable/specialized-canvas acceptance is another reusable child of Acceptance, not a fourth automatic workflow. Its native and selected-GPU tests require real output and ownership checks; document inspection requires independent renderers.
