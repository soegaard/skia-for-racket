# Portability and evidence — 0.49

## New required DXGI presentation lane

0.49 adds `Required DXGI presentation / D3D12 WARP` on `windows-2022`.
It runs the complete isolated Windows CPU/package path, Windows SDK and Racket
layout checks, the 28 shared presenter cases and actual swap-chain readback,
rotation, resize and stress tests. The `dxgi` job is an additional dependency
of `CI required`; it does not replace the offscreen `d3d12` job.

The accepted 0.48 starting point is commit
`b24dc1c2ea6c5dd6d763ff6a6794e7bf87fe8a4e`, CI run `36715835971`.
0.49 acceptance remains pending until its own required Windows run passes.
A usable desktop is required; lack of one fails this lane rather than silently
skipping it. Buffer pixels and successful Present calls do not certify screen
pixels or hardware acceleration. See [DXGI contracts](GPU-DXGI.md).

The following records the retained offscreen/CPU/EGL scope and earlier evidence.

## New required D3D12 lane

0.48 adds `Required D3D12 WARP / Windows x64 / Racket 9.3` on
`windows-2022`. It runs the isolated CPU/native package path followed by actual
SDK/call-ABI checks and D3D12 offscreen surface/image/cache/stress validation.
It is a separate required job in `CI required`, not a replacement for Windows
CPU or either Linux EGL lane. Its adapter is explicitly Microsoft WARP.

The accepted starting point is 0.47 commit
`00661e2485daaf7d1f015baa4e06e287b121c20c` (CI run `36704037723`). New D3D12
acceptance was established by run `36715835971` at the 0.48 baseline above. A WARP pass
establishes software functionality, not hardware acceleration, performance or
physical display output. See [D3D12 contracts and reproduction](GPU-D3D12.md).

## Retained CPU/EGL matrix and historical acceptance

Configuration alone is not a passing result. The required 0.46 acceptance run
`36620003104` at commit `808befa8768e672238e3fcdc5288e497a8b2705f` completed
the `CI required` aggregate successfully. The table names the automated lanes
that produced that evidence; future platform claims still require a passing run
and inspection of its retained artifacts.

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

The Linux EGL gate deferred in 0.43 passed both **required** 0.46 CI jobs in
run `36620003104`: surfaceless and explicit pbuffer, both using Mesa llvmpipe
with no display server. The jobs remain required; future failures must be
investigated rather than changed to `optional`, ignored, or replaced by a
hidden-window run.

## Limits of a passing run

A Linux llvmpipe pass establishes software OpenGL/Ganesh behavior through EGL:
context ownership, rendering, retained images, external GL boundaries, bounded
PDF/SVG fallbacks and cache/release stress. It does not establish hardware GPU
performance. Host-observed benchmark samples remain diagnostic data only.

Hosted macOS/Windows CPU jobs intentionally do not create GPU contexts or windows.
They compile optional modules and run their pure tests, but report live GPU
coverage as `not-run`. They do not replace the maintainer's full Metal/OpenGL
hardware and physical-window checks. These remain available through
`tools/validate-gpu.sh` and `examples/gpu-presenters.rkt`.

Linux ARM64, Windows ARM64, musl Linux, BSD, Wayland host interoperation, hardware
EGL device selection and 32-bit Racket are not in this required matrix. Nor does
this stage add Vulkan, Graphite or a different native ABI. Direct3D WARP has
the separate offscreen gate above, not a swap-chain/presentation gate. The pins
remain SkiaSharp 3.119.1 (Skia ABI 119.0) and HarfBuzzSharp 8.3.1.2.

The recurring macOS `Context leak detected, CoreAnalytics returned false`
message is not claimed fixed by adding CI. Tracked-resource checks and physical
platform diagnostics are separate evidence.

See [CI operation and reproduction](CI.md) for artifact contents and checks.
