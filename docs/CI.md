# GitHub Actions CI — 0.46

## Workflow and required result

`.github/workflows/ci.yml` runs for pull requests, pushes to `main`, version tags
starting with `v`, and manual dispatch. The source lane publishes the validated
matrix from `tools/ci-matrix.json`; five CPU lanes and two EGL lanes then run
without fail-fast cancellation between matrix entries. `CI required` runs even
when a prerequisite fails. It accepts only `success` for all three job groups;
`skipped` and `cancelled` do not count as passes.

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
`minimum-racket` (CS 8.7). Set `RACKET` to the complete executable path when it
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
