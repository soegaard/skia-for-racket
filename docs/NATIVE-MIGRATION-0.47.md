# Native compatibility and migration report — 0.47

## Decision

**Keep SkiaSharp 3.119.1 as the supported default. Investigate 4.153.1 without
enabling it.** There is a source-confirmed semantic ABI incompatibility, not
merely an overly strict version check. This report distinguishes inspected
upstream source from binary evidence that the new tool produces on execution.

The 0.46 input baseline is `1cd0599a463c00aa50dcdef1a3f1114ca12cdf10`.
The candidate is stable SkiaSharp **4.153.1**, published September 30, 2026,
with SkiaSharp source revision
`4783f51448f9b070dda4f87b83e941c9599e466e` and Skia submodule
`45afab4f1f0921f3feb97f58cf89b136fffa85e6`. The accepted m119 source is
`40f75dc0051d141913c07c20d4c19590c7da0cb7`.

Primary references:

- [4.153.1 release](https://github.com/mono/SkiaSharp/releases/tag/v4.153.1)
- [Exact candidate Skia submodule](https://github.com/mono/SkiaSharp/tree/v4.153.1/externals/skia)
- [Candidate path API](https://github.com/mono/skia/blob/45afab4f1f0921f3feb97f58cf89b136fffa85e6/include/c/sk_path.h)
- [Candidate path-builder API](https://github.com/mono/skia/blob/45afab4f1f0921f3feb97f58cf89b136fffa85e6/include/c/sk_pathbuilder.h)
- [Accepted path API](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_path.h)
- [Candidate surface API](https://github.com/mono/skia/blob/45afab4f1f0921f3feb97f58cf89b136fffa85e6/include/c/sk_surface.h)

## Source-confirmed blocker: paths and builders

The existing wrapper passes an owned path as the destination of
`sk_pathmeasure_get_segment`. In the candidate header that parameter is
`sk_pathbuilder_t*`. The symbol name, number of arguments and machine-level
pointer width do not reveal this difference. Binding it as `_pointer` and
allowing milestone 153 would permit the wrong native object kind to reach the
function. The safe current behavior is rejection, before graphics calls.

The candidate also provides a distinct builder API for movement, relative
movement, curves, shape addition and path extraction. These declarations
establish a migration design requirement; they do not by themselves establish
which legacy aliases are present in each platform's shipped binary.

A future adapter must settle how the existing public mutable-path API maps to
builders, snapshots and detached path values. It must preserve close/reset,
copying, SVG input/output, bounds, fill rules, transforms, boolean operations,
iterators and measurement. In particular, measurement output must use the
correct destination type and be converted under an explicit ownership rule.
This cannot be solved with a symbol-name fallback.

## Compatibility matrix and evidence boundaries

| Area | 3.119.1 / m119 policy | 4.153.1 / m153 investigation |
|---|---|---|
| Default installer selection | Retained | Never selected by default |
| Runtime profile | Supported 64-bit family; required preflight | Rejected before graphics calls |
| CPU and optional GPU export inventory | Original registries retained | Actual binary addresses measured by child process |
| Layouts | 26 wrapper-size checks plus existing C mirrors | No versioned structure passed by investigation |
| Path-measure destination | Existing path contract | Builder destination in reviewed C header; blocker |
| Native package identity | Installation provenance plus observed runtime identity | Exact NuGet id/version and recorded hashes |
| CPU/Ganesh rendering | Existing regression gates remain | Not executed by the candidate tool |
| Graphite | No wrapper support | C API/source feasibility plus optional compiled-backend query |
| Default migration | None | Requires a separate approved implementation and acceptance |

No candidate export counts or platform success are invented in this report.
`native-abi-candidate/report.json` supplies observed counts, missing symbols,
bootstrap version, platform/package hashes, reviewed Graphite build flags and
the actual Racket rejection result. Preserve this JSON alongside its logs.
A failed download or loader probe leaves the investigation failed.

## Centralization delivered

The profile makes the native milestone/pointer-width policy and important
m119 representation contracts explicit. A single default-pin file feeds both
platform installers. CPU and six optional GPU registries share one checked
handle. Layout and required-symbol preflight remain prerequisites to normal
object allocation, while optional inventory does not enable a backend.

The release does not replace every historical `m119` comment or rewrite all
m119 algorithms. Such comments identify pinned implementation assumptions and
must remain until the corresponding code is actually adapted. The new
contract metadata documents those assumptions rather than pretending they
are already portable.

## Requirements before supporting a second profile

First, retain actual candidate reports on every intended OS/architecture and
review changed, removed and new C declarations against the exact candidate
headers and implementations. Review same-name functions as carefully as
missing ones. Then implement path/builder adaptation and audit retained versus
borrowed parameters and failure cleanup across all affected factories.

Next, establish full C and Racket layout/enum/signature agreement for that
profile. Existing encoder, PDF, runtime-reflection, lattice, matrix, codec and
GPU descriptors all need review; a passing m119 mirror is not candidate
layout evidence. Revisit the explicit ICC workaround, string-view reflection
avoidance, lattice element representation and GPU image readback contract.

Only after these adapters exist should an experimental profile become
loadable. Run the full CPU and document suites, encoded roundtrips, text and
font probes, retained graphs, negative lifetime tests, OpenGL/Metal parity,
window presentation, both EGL paths and full cache/release stress against it.
Do not reduce assertions to accommodate candidate changes without documenting
why the underlying contract legitimately changed.

Finally, publish an explicit platform matrix and migration note. Changing the
default pin is a separate decision following that evidence. A negative
candidate-rejection pass in 0.47 is not that approval.
