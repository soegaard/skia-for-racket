# GPU foundation validation

Patch baseline: `a07aefeef0f91000c5a8683bb3b8835260a75064` (0.37).
The delivered authoring checks are **not** Racket compilation or GPU execution.
No macOS, Linux or Windows GPU configuration is declared live-validated by this
patch alone. Accept each advertised configuration only after its actual probe.

## Apply and validate on macOS

From the repository root, after saving the patch:

```bash
PATCH="$HOME/Downloads/skia-for-racket-0.38.0-gpu-foundation-20260928.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-gpu.sh
```

The default runner requires OpenGL success and, on macOS, early Metal
construction success. It creates a diagnostic GL window: run it in a desktop
session. It compiles all test suites and all optional GPU implementation modules
using the same selected Racket, runs the existing CPU doctors/tests, then runs
three real GL creation/draw/readback/close cycles. The separate macOS Metal
probe repeats device/queue/Ganesh construction and teardown without claiming
rendering success.

The suite adds 64 **source test cases** for pure provider, lifecycle, actual
GC/custodian callback registration, queue, invalidation, identity, copied data,
platform-selection and FFI descriptor checks. They are wired into the ordinary
`run-tests.rkt`, including `--pure`. The new GPU C mirror accompanies the nine
existing stage ABI programs. An executable suite, not this document, determines
actual passing RackUnit counts. GPU symbol resolution has its own registry;
no GPU symbols have been added to the CPU baseline's required binding group.

Python 3.10+ is required by the cross-platform runner and installer. `PYTHON`
selects it. `CC` selects a C11 compiler; a path with spaces is supported but
embedded compiler flags are not parsed. On Windows, LLVM clang or MinGW GCC
can run the same C mirrors. `SKIP_C_ABI=1` explicitly skips them and records
that limitation; it is not a complete ABI validation result.

## Review artifacts

Every run creates a fresh `output/gpu-0.38-*/` directory. Successful GL runs
include `opengl.diagnostic.json`, three `opengl.cycle-N.png` images,
`opengl.inspection.json` and `opengl.review.html`. macOS additionally gets a
construction-only Metal diagnostic, inspection and review. The final
`validation.json` records executed commands, statuses and explicit skips.
Failure writes `validation.failed.json`; it cannot reuse an earlier successful
inspection file from another run.

The inspector checks the entire RGBA sample array, decodes the PNG including
CRC and scanline filters, compares every pixel, checks native target/context
classification, generation changes and zero outstanding child/queue counts at
teardown. It publishes review/inspection artifacts only after success. The
checkerboard in the review must show through the transparent column; the upper
left is red, upper right green, lower left blue, lower right yellow. These are
GPU readbacks, not synthetic reference images. Inspector self-tests use synthetic
fixtures and are a separate form of evidence.

`SOURCE-SHA256SUMS.txt` is regenerated last, only after every selected check has
succeeded. The distributed patch does not pretend to supply a freshly validated
full-repository checksum manifest from an incomplete authoring checkout.

## Targeted commands

```bash
# No GL, Metal, display, or libSkiaSharp needed for the new mock suite.
"$RACKET" -l raco -- make gpu.rkt tests/gpu-pure-test.rkt &&
"$RACKET" -e '(require rackunit/text-ui "tests/gpu-pure-test.rkt") (exit (if (zero? (run-tests gpu-pure-tests)) 0 1))'

# Live required GL probe; compilation does not substitute for execution.
"$RACKET" tools/gpu-doctor.rkt --backend opengl --prefix output/gpu-gl &&
python3 tools/inspect-gpu-probe.py --probe-prefix output/gpu-gl

# macOS device/queue/context ownership diagnostic, not a Metal render test.
"$RACKET" tools/gpu-doctor.rkt --backend metal --prefix output/gpu-metal &&
python3 tools/inspect-gpu-probe.py --probe-prefix output/gpu-metal
```

`REQUIRE_HARDWARE=1` makes the combined GL run reject software/unclassified
renderer strings. The direct doctor flag is `--require-hardware`. Neither is a
hardware attestation or a benchmark. A software GL run may validate functionality
but does not establish hardware acceleration.

## CPU-only CI and unavailable backends

```bash
RACKET="$RACKET" GPU_MODE=optional bash tools/validate-gpu.sh
RACKET="$RACKET" GPU_MODE=off bash tools/validate-gpu.sh
```

`optional` permits only typed initialization unavailability to be skipped.
Wrong-context, drawing, readback, inspection and destruction failures still fail.
`off` explicitly omits live GPU probes while keeping ordinary CPU and pure
foundation validation. Both record skips; neither meets a required GPU release
gate. CPU native libraries remain required by the combined runner. Run
`run-tests.rkt --pure` for the ordinary no-native-libraries test mode.

Do not use `--optional` to disguise a misconfigured release job. A missing
display/server, GUI package, GL interface or driver is an explicit unavailable
step, not evidence of a successful GPU implementation. Linux's Racket host is
GLX/X11 or XWayland, not native Wayland or headless EGL.

## Windows readiness

Use Windows x64 Racket and Python. The loaders now select
`native/win-x64/libSkiaSharp.dll` and `libHarfBuzzSharp.dll`. Existing
`RACKET_SKIA_LIBRARY` and `RACKET_HARFBUZZ_LIBRARY` overrides are retained.

```powershell
$env:RACKET = 'C:\Program Files\Racket\Racket.exe'
$env:PYTHON = 'python'
.\tools\install-native-windows.ps1 -Racket $env:RACKET -Python $env:PYTHON
.\tools\validate-gpu.ps1 -Racket $env:RACKET -Python $env:PYTHON
```

The explicit installer downloads pinned `SkiaSharp.NativeAssets.Win32` 3.119.1
and `HarfBuzzSharp.NativeAssets.Win32` 8.3.1.2 from NuGet over HTTPS. It verifies
package identity/version, exact RID/member, ZIP integrity of extracted members,
PE x64 machine type and DLL flag before replacement. It extracts only fixed
members, never runs code from an archive, and retains archives/manifests/hash
records for provenance. It validates every selected package before changing an
installed DLL; replacements are individually atomic, not a cross-package
transaction. Stop active applications before reinstalling loaded Windows DLLs.

Offline archives are accepted with `-SkiaArchive` and `-HarfBuzzArchive`; the
Python installer also accepts separately obtained expected SHA-256 values.
Recorded hashes alone are not independent authenticity checks.

A loader error is preserved in full. Windows error 193 commonly indicates an
architecture mismatch; 126 can mean a dependent DLL is missing even when the
named library exists. Check the selected interpreter architecture and dependent
libraries with an installed PE dependency tool or `dumpbin /dependents`; obtain
any missing runtime from its official vendor, not a random DLL-download site.
Windows ARM64 automatic selection is not added or advertised in this stage.
The old `static-check.py` contains Unix-only shell/installer smoke tests and is
explicitly skipped on Windows; the new source/installer checks and complete
Racket compilation/test suites still run. This skip is recorded, not presented
as a passed Unix installer check. Actual Windows package installation, DLL
dependency resolution and GL execution were not available in the authoring
environment.

## Evidence and acceptance

The implementation bundle's `authoring-validation.json` records exactly which
source, Python, C and patch-context checks were run. Two small modified baseline
files were verified against their Git blob hashes; larger loader/document
changes were checked against fetched affected contexts. This is not equivalent
to applying/compiling/testing a full native checkout.

Before declaring 0.38 accepted on a configuration, require the unchanged CPU
suite, new pure suite, ABI checks and a genuine GL target/readback pass with the
actual OS/architecture/provider/renderer recorded. On macOS also inspect the
Metal construction/ownership path. No performance result, Metal rendering
parity, public GPU image semantics or window presentation claim is made here.
