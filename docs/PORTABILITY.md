# Portability and evidence — 0.46

Configuration is not a passing result. This table names the required automated
lanes, not a claim that they have already executed. Read the `CI required` job
and that run's artifacts before treating a new platform as validated.

| Lane | Runner | Racket CS | Required evidence |
|---|---|---|---|
| Linux x64 CPU | `ubuntu-24.04` | 9.3 | Independent package installation, native CPU regressions, C ABI mirrors |
| macOS ARM64 CPU | `macos-15` | 9.3 | Same CPU/package checks, native ARM64 interpreter identity |
| macOS Intel CPU | `macos-15-intel` | 9.3 | Same CPU/package checks, native x86-64 interpreter identity |
| Windows x64 CPU | `windows-2022` | 9.3 | Same CPU/package checks, fresh PE/DLL validation, MSVC C ABI mirrors |
| Declared minimum Racket | `ubuntu-24.04` | 8.7 | The full CPU/package checks, not merely syntax compilation |
| Linux EGL surfaceless | `ubuntu-24.04` | 9.3 | Complete required headless sequence, no binding surface, Mesa llvmpipe |
| Linux EGL pbuffer | `ubuntu-24.04` | 9.3 | Same sequence with an explicit EGL pbuffer; still no window/display server |

The source/CI-contract lane runs once before this matrix. Python is pinned to
the 3.12 series. Exact runner/interpreter selections are checked by
`tools/ci-matrix.json` and `tools/ci_matrix.py`; `-latest` aliases and automatic
architecture selection are intentionally absent. The Actions image and distro
packages still evolve; reports record their observed identities where available.

## What is already accepted

The maintainer accepted 0.45 commit
`92f6119af3846966075ced0034ceb740e916bdee` after macOS/aarch64 Apple M4 Pro
CPU, OpenGL and Metal regression runs, document inspections, cache tests, and
sustained offscreen/redraw checks. Those historical runs used Racket 9.3.0.2.
The matrix uses the released Racket 9.3, not that development snapshot.

The Linux EGL gate deferred in 0.43 is now wired as two **required** CI jobs.
Until those jobs actually pass, its end-to-end acceptance is pending. A failure
must be investigated and fixed; it must not be changed to `optional`, wrapped
in an ignored exit status, or substituted with a hidden-window run.

## Limits of a passing run

A Linux llvmpipe pass establishes software OpenGL/Ganesh behavior through EGL:
context ownership, rendering, retained images, external GL boundaries, bounded
PDF/SVG fallbacks and cache/release stress. It does not establish hardware GPU
performance. Host-observed benchmark samples remain diagnostic data only.

Hosted macOS/Windows jobs intentionally do not create GPU contexts or windows.
They compile optional modules and run their pure tests, but report live GPU
coverage as `not-run`. They do not replace the maintainer's full Metal/OpenGL
hardware and physical-window checks. These remain available through
`tools/validate-gpu.sh` and `examples/gpu-presenters.rkt`.

Linux ARM64, Windows ARM64, musl Linux, BSD, Wayland host interoperation, hardware
EGL device selection and 32-bit Racket are not in this required matrix. Nor does
this stage add Vulkan, Direct3D, Graphite or a different native ABI. The pins
remain SkiaSharp 3.119.1 (Skia ABI 119.0) and HarfBuzzSharp 8.3.1.2.

The recurring macOS `Context leak detected, CoreAnalytics returned false`
message is not claimed fixed by adding CI. Tracked-resource checks and physical
platform diagnostics are separate evidence.

See [CI operation and reproduction](CI.md) for artifact contents and checks.
