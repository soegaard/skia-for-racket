# Release candidate matrix — 0.78d

Generated from the reviewed local reusable-workflow graph. Not a run receipt.

Integration baseline: `705a090d287a8a2887eb2cb4f33b43961626c6e4`. Package version: **0.78**.

**66 required jobs; 73 required evidence artifacts.**

All jobs must finish successfully in one attempt of the Release candidate workflow.
The in-progress `Release candidate required` verifier is the sole exception to the job list below.

| Required job | Hosted runner | Workflow | Evidence artifacts |
|---|---|---|---:|
| API inventory / Pinned capability sources / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/api-inventory.yml` | 1 |
| API inventory / Pinned capability sources / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/api-inventory.yml` | 1 |
| Acceptance / Acceptance required | ubuntu-24.04 | `.github/workflows/acceptance.yml` | 0 |
| Acceptance / Advanced layers and canvases / Advanced layers and canvases / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/advanced-canvases.yml` | 1 |
| Acceptance / Advanced layers and canvases / Advanced layers and canvases / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/advanced-canvases.yml` | 1 |
| Acceptance / Advanced layers and canvases / Advanced layers and canvases / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/advanced-canvases.yml` | 1 |
| Acceptance / Codec size and subset queries / Codec queries / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/codec-queries.yml` | 3 |
| Acceptance / Codec size and subset queries / Codec queries / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/codec-queries.yml` | 3 |
| Acceptance / Codec size and subset queries / Codec queries / Windows / Racket 9.3 | windows-2022 | `.github/workflows/codec-queries.yml` | 3 |
| Acceptance / DC document output / PDF and SVG / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/dc-output.yml` | 1 |
| Acceptance / DC document output / PDF and SVG / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/dc-output.yml` | 1 |
| Acceptance / Direct image operations / Direct image operations / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/image-operations.yml` | 1 |
| Acceptance / Direct image operations / Direct image operations / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/image-operations.yml` | 1 |
| Acceptance / Direct image operations / Direct image operations / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/image-operations.yml` | 1 |
| Acceptance / Effects / Effects / D3D12 WARP / Racket 9.3 | windows-2022 | `.github/workflows/effects.yml` | 1 |
| Acceptance / Effects / Effects / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/effects.yml` | 1 |
| Acceptance / Effects / Effects / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/effects.yml` | 1 |
| Acceptance / Floating-point pixels and colors / Floating-point pixels and colors / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/float-pixels.yml` | 1 |
| Acceptance / Floating-point pixels and colors / Floating-point pixels and colors / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/float-pixels.yml` | 1 |
| Acceptance / Floating-point pixels and colors / Floating-point pixels and colors / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/float-pixels.yml` | 1 |
| Acceptance / Font options and glyph queries / Font queries / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/font-queries.yml` | 1 |
| Acceptance / Font options and glyph queries / Font queries / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/font-queries.yml` | 1 |
| Acceptance / Font options and glyph queries / Font queries / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/font-queries.yml` | 1 |
| Acceptance / GPU DC / GPU DC / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/gpu-dc.yml` | 1 |
| Acceptance / GPU DC / GPU DC / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/gpu-dc.yml` | 1 |
| Acceptance / GPU DC / GPU DC consumers / D3D12 WARP / Racket 9.3 | windows-2022 | `.github/workflows/gpu-dc.yml` | 1 |
| Acceptance / GPU context options and resource control / GPU context controls / Linux EGL / Racket 8.18 | ubuntu-24.04 | `.github/workflows/gpu-context-controls.yml` | 2 |
| Acceptance / GPU context options and resource control / GPU context controls / Linux EGL / Racket 9.3 | ubuntu-24.04 | `.github/workflows/gpu-context-controls.yml` | 2 |
| Acceptance / GPU context options and resource control / GPU context controls / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/gpu-context-controls.yml` | 2 |
| Acceptance / GPU formats and surface properties / GPU formats and surface properties / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/gpu-formats.yml` | 1 |
| Acceptance / GPU formats and surface properties / GPU formats and surface properties / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/gpu-formats.yml` | 1 |
| Acceptance / GPU formats and surface properties / GPU formats and surface properties / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/gpu-formats.yml` | 1 |
| Acceptance / Geometry completion / Geometry completion / D3D12 WARP / Racket 9.3 | windows-2022 | `.github/workflows/geometry-completion.yml` | 1 |
| Acceptance / Geometry completion / Geometry completion / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/geometry-completion.yml` | 1 |
| Acceptance / Geometry completion / Geometry completion / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/geometry-completion.yml` | 1 |
| Acceptance / Global caches and memory statistics / Global caches / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/global-caches.yml` | 1 |
| Acceptance / Global caches and memory statistics / Global caches / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/global-caches.yml` | 1 |
| Acceptance / Global caches and memory statistics / Global caches / Windows / Racket 9.3 | windows-2022 | `.github/workflows/global-caches.yml` | 1 |
| Acceptance / Integer pixel storage / Integer pixel storage / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/integer-pixels.yml` | 1 |
| Acceptance / Integer pixel storage / Integer pixel storage / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/integer-pixels.yml` | 1 |
| Acceptance / Integer pixel storage / Integer pixel storage / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/integer-pixels.yml` | 1 |
| Acceptance / Multi-run text blobs / Text blobs / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/text-blobs.yml` | 1 |
| Acceptance / Multi-run text blobs / Text blobs / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/text-blobs.yml` | 1 |
| Acceptance / Multi-run text blobs / Text blobs / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/text-blobs.yml` | 1 |
| Acceptance / Native streams and buffered ports / Native streams / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/streams.yml` | 1 |
| Acceptance / Native streams and buffered ports / Native streams / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/streams.yml` | 1 |
| Acceptance / Native streams and buffered ports / Native streams / Windows / Racket 9.3 | windows-2022 | `.github/workflows/streams.yml` | 1 |
| Acceptance / Select regression scope | ubuntu-24.04 | `.github/workflows/acceptance.yml` | 0 |
| Acceptance / Typeface resources / Typeface resources / Linux / Racket 8.18 | ubuntu-24.04 | `.github/workflows/typefaces.yml` | 1 |
| Acceptance / Typeface resources / Typeface resources / Linux / Racket 9.3 | ubuntu-24.04 | `.github/workflows/typefaces.yml` | 1 |
| Acceptance / Typeface resources / Typeface resources / Windows / Racket 9.3 | windows-2022 | `.github/workflows/typefaces.yml` | 1 |
| Acceptance / Unified render canvas / Render canvas / Linux Mesa / Racket 8.18 | ubuntu-24.04 | `.github/workflows/render-canvas.yml` | 1 |
| Acceptance / Unified render canvas / Render canvas / Linux Mesa / Racket 9.3 | ubuntu-24.04 | `.github/workflows/render-canvas.yml` | 1 |
| Acceptance / Unified render canvas / Render canvas / Windows WARP / Racket 9.3 | windows-2022 | `.github/workflows/render-canvas.yml` | 1 |
| CI / CI required | ubuntu-24.04 | `.github/workflows/ci.yml` | 0 |
| CI / CPU linux-x64 / Racket 9.3 | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |
| CI / CPU macos-arm64 / Racket 9.3 | macos-15 | `.github/workflows/ci.yml` | 1 |
| CI / CPU macos-x64 / Racket 9.3 | macos-15-intel | `.github/workflows/ci.yml` | 1 |
| CI / CPU minimum-racket / Racket 8.18 | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |
| CI / CPU windows-x64 / Racket 9.3 | windows-2022 | `.github/workflows/ci.yml` | 1 |
| CI / Required D3D12 WARP / Windows x64 / Racket 9.3 | windows-2022 | `.github/workflows/ci.yml` | 2 |
| CI / Required DXGI presentation / D3D12 WARP | windows-2022 | `.github/workflows/ci.yml` | 1 |
| CI / Required EGL pbuffer / llvmpipe | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |
| CI / Required EGL surfaceless / llvmpipe | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |
| CI / Required raster Skia canvas / Linux Xvfb | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |
| CI / Source and CI contracts | ubuntu-24.04 | `.github/workflows/ci.yml` | 1 |

## Evidence boundary

The gate checks workflow identity, every reviewed matrix job and authored step, and every evidence ZIP. It delegates native pixel/document/consumer assertions to the existing executing validators. It does not reinterpret successful source checks as new native rendering, hardware performance, physical-display validation, universal backend support, or permission to publish version 1.0.
