# 0.78b — Review rationale and maintenance

## Baseline and scope

This integration starts at GitHub commit
`4a6082274e06456aa385fa9337c31528f2f44a4a` (Update release-scope).
It preserves the 0.77c GPU diagnostics and retained GL interfaces, the owned-EGL
CI probe correction, and the deliberate review-ledger update. No GPU driver,
callback provider, ownership guard, or native dependency is replaced.

The numeric library package version is **0.78** and the inventory/review stage
is **0.78b**. The pinned comparison stays SkiaSharp 3.119.1 / m119; the minimums
stay Racket 8.18 and draw-lib 1.22. The capability-family denominator and public
module set are unchanged. Only `colors.xyz-ops` and `surfaces.null` receive new
capability decisions. See [the generated counts and decision map](RELEASE-SCOPE.md)
rather than treating binding counts as a feature-parity percentage.

## The two resolved decisions

`colors.xyz-ops` is now **supported-with-limits**. The two formerly unbound C
functions are implemented as `xyz-d50-concat` and `xyz-d50-invert` in the existing
color-space module. They use immutable, detached row-major vectors, checked
binary32 inputs, separate input/output buffers, explicit multiplication order,
finite-result handling, and native inversion failure as `#f`. No encoded-pixel
color conversion follows merely from matrix arithmetic. The new suites specify argument and native acceptance checks; only an actual
successful run establishes Racket/native execution evidence.

`surfaces.null` is now **intentionally excluded**, not supported or equivalent.
The pinned native null surface has no image snapshot and unknown image info;
its canvas is a no-draw canvas. The public alternative remains the existing
`call-with-nodraw-canvas` for callback-scoped diagnostic authoring. That borrowed
canvas is not an image surface, produces no output, and expires on return/error.
A persistent storage-less surface needs a concrete consumer and separate
ownership, snapshot, format, and output-audit decisions before being added.
The factory remains unbound. [Detailed contracts, rationale, tests, and pinned
sources](SMALL-GAPS.md) explain this boundary.

The checked ledger therefore has no **pending in-scope** family. This is policy
closure, not a claim that an excluded factory was implemented. Deferred work
and supported-with-limits restrictions remain visible.

## Earlier reconciliations retained

The `colors.float` family remains **racket-equivalent**: `color->color4f` accepts
packed ARGB through the existing color API, while `color4f->rgba` and
`color->argb` supply the explicit quantizing reverse direction. Extended RGB
requires an explicit clipping policy. The two native packed-color convenience
functions remain unbound. Their pure tests do not claim Skia binary32 parity,
color-space conversion, or tone mapping.

The GPU memory-dump and retained-interface families remain supported-with-limits.
Context-local reports are not process memory or total VRAM. Owned EGL is desktop
OpenGL; GLES/WebGL selection still requires a matching host and an exercised
native build. Existing GPU tests and required acceptance steps are retained.

Native file/buffered typeface and codec entry points are not silently promoted
to long-lived live-Racket-port-backed consumers. Scaled/subset codec support
remains negotiation queries, not unrestricted scaled/subset pixel decoding.
Existing incremental, scanline, and full-image contracts remain distinct.

## Deferrals and exclusions

Vulkan remains G1/G2; native-version migration remains U1; variable axes and
color palettes remain U2; Graphite remains U3; numeric HDR and physical HDR
presentation remain separate H1 questions; XPS remains X1, not a PDF equivalent.
The earlier exclusions for unrestricted annotations, raw aliases/pointers,
arbitrary texture/storage ownership, unsafe data memory, and managed .NET glue
are unchanged. The null-surface exclusion is additional and explicit.

No new capability family, native-ABI upgrade, public pointer API, graphics
backend, or source-to-runtime evidence promotion is hidden in this review.

## Machine-checked maintenance

`api/release-scope.json` freezes one sorted decision and capability fingerprint
per family together with exact source/checker/policy hashes. The verifier still
checks complete production-source discovery, all binding registries, public
anchors, catalogue classification, and deterministic generated reports. Changed
source, test, policy, or checker inputs require deliberate review; updating
`SOURCE-SHA256SUMS.txt` alone is not approval.

The 0.78b installer accepts only the exact, clean starting commit above. It
validates the old inventory and review, applies narrowly scoped changes in a
temporary local source checkout, regenerates the two reviewed decisions and
hashes, and runs source regression checks before applying a standard Git patch.
It is a one-time stage integration, not an ongoing auto-approval command.
Unrelated capability decisions and historical evidence remain unchanged.

```bash
python3 tools/validate-release-scope.py --check --require-no-open-gaps
python3 tools/validate-release-scope.py --racket /path/to/racket --require-no-open-gaps
python3 tools/validate-small-gaps.py --racket /path/to/racket
```

The no-open-gaps gate should now pass its source-policy checks. It does not say
that the native or rendering tests ran. The focused validator independently
requires the new Racket/native suites unless explicitly asked for `--source-only`.
The `--write` switch on the release-scope verifier still writes only Markdown
after the frozen review passes; it cannot approve input drift.

## Remaining release gates

**0.78c** must stabilize public exports/signatures and documentation.
**0.78d** must establish current isolated installation, supported-platform and
minimum-version execution, CPU/GPU/document and real-consumer acceptance, and
one authoritative mandatory-lane release decision. No 1.0 tag, branch-protection
change, physical HDR verification, or complete Skia/Cairo parity is claimed.

## 0.78c integration — public API stability

The separate 0.78c public API baseline starts from `cc6e63c3e14a9059b326f515ee01fd2b582c123f`. The maintainer supplied an all-green-CI assumption for that implementation baseline. No production drawing/binding module or capability-family decision is changed. The source/capability catalogue keeps its 0.78b identity; the public API policy and real reflected snapshots carry their own 0.78c identity. The snapshots, checker, fixtures, examples and contract documents are added to this frozen review input set deliberately. A current `tools/validate-public-api.py --racket ...` full pass is required, not inferred by this source-only ledger. Release readiness remains the independent 0.78d decision.

## 0.78d integration — one current execution gate

The candidate coordinator starts from `705a090d287a8a2887eb2cb4f33b43961626c6e4`, accepted under the maintainer’s all-green assumption. It changes no Racket implementation, public signature snapshot or capability-family decision. Its explicit exhaustive workflow policy, checker, tests and documentation are new frozen review inputs. The 0.78b and 0.78c audit identities remain intact. Only a fresh complete **Release candidate** run can validate this candidate; the source ledger continues to report `release_ready: false`. No publication permission is implied.
