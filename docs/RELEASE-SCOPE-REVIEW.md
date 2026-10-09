# 0.78a — Review rationale and maintenance

## Updated baseline includes 0.77c

This source-only review is rebased onto GitHub commit
`3d908fd83ff0f9e2bb2855f538235e6e46e432fd` (Add GPU diagnostics and GL interfaces).
That tree includes 0.77c. Its GPU tracing and retained GL interface helpers are
preserved as **supported-with-limits**, with their source and native declarations
unchanged. This audit does not infer new per-backend execution results from CI,
source availability, or an earlier delivery archive.

The library's numeric package version stays **0.77**. This stage changes the
source catalogue, release decisions, documentation and tests; it adds no public
runtime API, native binding, GPU driver, callback provider or rendering behavior.
The audit milestone in its catalogue and reports is **0.78a**.

## Reviewed outcome

The baseline has 140 capability families, 849 core C declarations, 86 managed
source files, 676 distinct core bindings (607 CPU), and 59 public Racket modules.
The review changes no denominator, native pin, public module or binding set.

| Release decision | Families | Meaning |
|---|---:|---|
| Limited | 91 | Existing support retained within its documented restrictions |
| Equivalent | 34 | Existing Racket operations meet the reviewed user-level need |
| Pending in scope | 2 | Must be implemented or explicitly justified before scope closure |
| Deferred | 6 | Named extended workstreams, outside the proposed core release |
| Excluded | 7 | Explicit safety or non-user-facing scope decisions |

These are family counts, **not a feature-parity percentage**. Existing supported
families are carried forward from the checked catalogue with exact fingerprints;
this is not a new line-by-line/manual review of every managed overload. The
complete declaration and public/source/test-anchor graph must still pass the
existing inventory verifier.

## Corrected false gap: Color4f / packed colors

The `colors.float` record previously called these operations missing:

- `sk_color4f_from_color`
- `sk_color4f_to_color`

The existing public operations already supply the user-level conversion:

```racket
(color->color4f #x80402010)
(color->argb (color4f->rgba float-color))
(color->argb (color4f->rgba float-color #:out-of-range 'clip))
```

`color.rkt` accepts unsigned ARGB integers; `color4f.rkt` normalizes each byte,
keeps unpremultiplied RGB/alpha, and uses an explicit quantization policy in the
reverse direction. Extended RGB needs explicit clipping. This does not perform
color-space conversion or tone mapping. The Racket values are not claimed to be
bit-identical to native binary32 values at every rounding boundary.

The record is now **racket-equivalent**, with concrete public/source/test anchors.
Both native symbols remain **unbound**, and native binding counts remain unchanged.
`tests/release-scope-pure-test.rkt` supplies exhaustive byte values independently
in each channel, packed/string order, transparent RGB, explicit clipping,
nonfinite/range rejection and immutable detached values. This is pure-Racket
execution evidence when run, not a Skia conversion/render test.

## Open small gaps are not disguised as equivalents

`surfaces.null` remains pending for **0.78b**. The existing scoped no-draw canvas
is useful, but a null surface has distinct surface ownership/sizing/snapshot
semantics. Either implement that contract or deliberately exclude it with a
reviewed rationale. Do not claim it is implemented merely because no-draw exists.

`colors.xyz-ops` also remains pending for **0.78b**. The color-space module exports
XYZ-D50 values, not the missing concatenation/inversion helpers. Generic geometric
matrices are not an automatically proven equivalent for that representation.
Ordering, singular input, finite values and detached output need explicit tests.

`gpu.trace` and `gpu.interface-variants` are no longer open gaps: the baseline
contains their **0.77c supported-with-limits implementations**. The audit keeps
GPU-context reports distinct from global-cache reports and total VRAM. Interface
selection requires a matching host and supported native build; owned EGL remains
desktop. In particular, a bound WebGL factory can still be a build-time stub.
The implementation, public exports, all five added bindings, tests, and existing
GPU Acceptance steps are retained rather than reapplied from a delivery archive.

The exact closure gates are in `api/release-scope-policy.json` and the generated
`docs/RELEASE-SCOPE.md`.

## Accepted limitations are not silently strengthened

The retained native-stream and explicitly buffered font/codec APIs are not
long-lived live-Racket-port-backed typefaces/codecs. Their old `planned_stage:
0.75b` metadata is cleared, without broadening their existing restrictions.
The typeface title is corrected so it no longer promises live-port construction.

The scaled/subset codec family means **negotiation queries**, not arbitrary
subset pixel decoding. Incremental/scanline/full-image APIs retain their own
separate limits. No new decoder fallback is introduced by this review.

## Deferrals and exclusions

Vulkan remains G1/G2; migration to a newer native pin remains U1. Variable axes
and palette cloning remain U2; Graphite remains U3. Numeric HDR transfers and
physical HDR presentation remain distinct H1 items. XPS is X1 and is not treated
as equivalent to PDF. These six deferred families retain their exact original
native-ABI availability classifications.

Seven deliberate exclusions remain explicit: unrestricted annotation payloads,
raw bitmap aliasing, raw pixmap addresses/reset, arbitrary adopted texture
ownership, unrestricted image-storage callbacks, unsafe SKData memory, and .NET
implementation glue. Missing raw-pointer APIs are not an incentive to weaken the
Racket ownership and interop contracts. Each exclusion has a policy rationale and
a condition for reconsideration.

## What is machine checked

`api/release-scope.json` contains one sorted decision for every family, a semantic
fingerprint of each capability, and the exact source/checker/policy input hashes.
The verifier also calls the existing catalogue, production-file discovery,
all-registry binding, public-anchor and generated-inventory checks.

It rejects unknown or duplicated families, changed limits/public anchors,
unreviewed source changes, false completion of missing features, unplanned
in-scope gaps, anonymous deferrals, changed native comparison/minimum versions,
and stale generated reports. The seven excluded and all missing/future families
require explicit policy entries; no catch-all can make a new residual gap pass.

The workflow also runs the new pure Racket suite. Its receipt distinguishes
source checks, requested/performed pure execution, and native/rendering work
(which this audit does not perform). Existing API inventory continues to verify
pinned upstream checkouts and observe native symbols independently; existing CI
and Acceptance retain their regression and backend-execution responsibilities.

## Commands

```bash
python tools/validate-release-scope.py
python tools/validate-release-scope.py --racket /path/to/racket
python tools/validate-release-scope.py --write
python tools/validate-release-scope.py --require-no-open-gaps
```

`--write` writes only the generated Markdown after the already frozen review
passes. It cannot repair changed catalogue/source hashes by approving them.
The final command intentionally fails on this baseline's two pending families.
A green ordinary audit means **all gaps are accounted for**, not all gaps closed.
Even a future no-open-gaps success is not a 1.0 release approval: 0.78c and 0.78d
remain independent gates.

## Intentional updates to the review

When a later stage is implemented, first review its changed capability contracts,
source anchors, public API and native execution evidence. Update the explicit
policy and its target/resolution, then capture a new reviewed ledger in that
stage's integration with a newly identified baseline. Review the JSON diff; do
not just regenerate checksums until it passes. The initial-capture helper in
`release_scope.py` is for such explicit integration, not an auto-approval CLI.

The rebased 0.78a installer accepts only the exact 0.77c baseline above. It does
not undo, reapply, or replace that implementation. Use this replacement bundle
instead of the original 0.78a bundle targeting 0.77b; do not stack both installers.
Future source changes require a deliberate review update, not automatic approval.

## Scope boundaries still outside 0.78a

This stage does not freeze exported procedure arities/keywords (0.78c), run fresh
GPU/document performance or pixel suites (existing Acceptance and 0.78d), verify
physical HDR output, or reflect every C# overload. It does not change repository
branch-protection settings, create a 1.0 tag, or claim complete Skia/Cairo parity.
