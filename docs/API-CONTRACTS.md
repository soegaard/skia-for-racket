# Public API contracts — 0.78c

Package version **0.78**; accepted implementation baseline
`cc6e63c3e14a9059b326f515ee01fd2b582c123f`. The implementation baseline is accepted
on the maintainer's stated all-green-CI assumption; that assumption is not a new
CI receipt. The SkiaSharp **3.119.1 / m119.0**, Racket **8.18**, and draw-lib
**1.22** minimum/pin decisions are unchanged.

This document consolidates the existing contracts. It does not change runtime
behavior, broaden backend support, create a null surface, or declare 1.0 ready.
The [generated public API index](PUBLIC-API.md) records the actual exports and
call boundaries. Feature-specific restrictions in [API.md](API.md), the
[capability catalogue](SKIASHARP-GAPS.md), and the linked feature documents
continue to apply. A disagreement is a documentation defect to resolve, not
permission to bypass a narrower checked runtime contract.

## Stability

**Stable** identifies the export/call-boundary compatibility target for the
reviewed 0.78 public surface. Existing positional calls and keyword spellings
must not change accidentally. It does not mean every Skia backend supports an
operation, every result is deterministic across machines, or all native
allocation behavior is bounded by a Racket parameter.

**Experimental** identifies optional GPU, GUI, unsafe-native ingress, and DC
integration interfaces that still have explicitly narrower lifecycle/backend
contracts. These exports are still in the checked baseline. An experimental
label is not a way to omit a failed import or silently accept an API change.
The module policy is explicit in `api/public-api-policy.json`.

**Private** means implementation modules under `private/`, testing/internals
submodules, and implementation support under `tools/` and `tests/`. Their paths,
representations, raw pointers and internal callbacks are not public APIs.
A public wrapper may legitimately re-export a binding implemented in a private
module: use the public path, not its implementation origin. The two public
`unsafe/` entry points are experimental and unsafe, not secretly private.

The policy is intentionally conservative: a name also exported by an
experimental public module is shown as experimental throughout the generated
index. That prevents a convenience re-export from silently upgrading the
stability label. Exact signature comparison applies to both classifications.

The compatibility gate rejects additions, removals, changed positional arities,
changed keyword sets, variable/syntax changes, and changed reflected value
kinds. Even an additive change therefore requires an explicit snapshot review.
This is a review gate, not a claim that every addition is a breaking change.

The current snapshot has these deliberate boundaries:

- Procedure inputs are reflected, including case-lambda, rest arguments,
  parameters, re-exports, contract wrappers and syntax-backed constructors.
- Macro names and phase/space exports are inventoried. Macro grammars,
  expansions, defaults, result contracts and constant contents are not inferred.
- Class and interface exports are identified without constructing instances.
  Class initialization arguments and method arities remain in their existing
  DC/GUI contracts and consumer tests; this gate does not pretend to reflect
  them by running constructors.

## Ownership

### Owned resources and detached values

Ordinary CPU-owned native resources use the established resource protocol and
have automatic fallback cleanup when they become unreachable. Normal Racket
bindings are therefore valid when the exact release time does not matter. Use
`with-skia`, `call-with-skia-resource`, or `skia-close!` when prompt,
deterministic release matters. Explicit release cancels the fallback cleanup.
An ordinary resource's `skia-close!` is idempotent, but close can still be
rejected while an exclusive borrow or protected use is active. Do not swallow
such a failure and then reuse the resource as if it had closed successfully.
See [resource lifetimes](RESOURCE-LIFETIMES.md) for the public lifetime policy.

Detached values do not become native resources merely because they describe
native data. Colors, copied XYZ-D50 coefficients, image descriptions and bounded
memory-report records can remain useful after the originating operation ends.
A detached description is not a proof that an associated native object is live.
Do not call `skia-close!` on arbitrary immutable values.

Native dependency retention is operation-specific. Factories that snapshot or
retain their inputs document that fact; a Racket variable reference alone is
not a universal promise that explicitly closing an input wrapper is harmless.
Do not turn every "uses an input" relationship into an ownership transfer.

### Borrowed canvases, pixel views and callbacks

A canvas obtained from a surface borrows the surface's lifetime. PDF/SVG page
canvases and specialized no-draw/other callback canvases have their documented
page/scope lifetimes. A GPU canvas additionally requires the correct active
context/lease. A still-reachable Racket canvas object may already be invalid.

Pixel/pixmap/raster-buffer views are exclusive scoped borrows where documented.
They must not escape their callback. Closing or mutating the backing owner while
borrowed is not made safe by garbage collection. Copies and independent image
snapshots are the routes for retaining data beyond a borrow.

A callback's return is not a license to retain its borrowed target. Error and
continuation-exit paths must retire the same lease as normal return. The existing
resource/state scopes protect their own restoration floors; callers must not
restore past a protected scope to get around that policy.

### GPU ownership and completion

GPU resources retain exact context/generation affinity. Use the owning Racket
thread and the active context scope required by the operation. A resource from
one context is not interchangeable with a same-sized resource from another.
Raw external resource ingress through `unsafe/` retains its explicit native
object-validity and producer/consumer synchronization obligations.

Flush, submission, waiting, and CPU readback are distinct operations. A flush
alone does not promise completion; a memory/extension diagnostic is not an
implicit synchronization or transfer request. Keep normal-frame transfers
explicit. Healthy release-and-abandon and lost-host abandonment retain their
different contracts; indeterminate teardown is not blindly retried.

See [GPU context controls](GPU-CONTEXT-CONTROLS.md),
[GPU diagnostics](GPU-DIAGNOSTICS.md), [raster buffers](RASTER-BUFFERS.md), and
[stream contracts](STREAMS.md) for detailed lifetimes and partial-result rules.

## Errors

Wrong argument types/ranges and malformed options use the existing checked
argument errors, commonly `exn:fail:contract?`. State, expired-lease,
wrong-owner, unsupported operation and native failures may use other
`exn:fail?` subtypes. This stage does not introduce one universal exception
class or retrospectively change those distinctions.

Where exported, typed availability predicates and fields are preferable to
matching the exact human-readable error message. Do not interpret a native
factory's presence or a successful import as evidence that a backend/device is
usable. Missing libraries, unsupported builds and invalid host contexts remain
real failures at their documented boundaries.

A documented `#f` result is different from an exception. For example,
`xyz-d50-invert` returns `#f` on native inverse failure/nonfinite output, whereas
malformed inputs raise. Concatenation rejects nonfinite results rather than
returning a matrix full of infinities. Singular operands are permitted for
multiplication. See [XYZ-D50 and null-surface decisions](SMALL-GAPS.md).

A cancelled/incomplete codec operation or partially written output is not a
successful full decode/publication. Existing session/result states and poisoned
stream rules remain authoritative. No API stability label upgrades a partial
result, creates a transaction around external port I/O, or promises rollback
that the underlying operation does not provide.

## Output

### Raster and numerical representation

Raster storage format, alpha representation and color-space metadata are
separate properties. Existing explicitly RGBA-oriented helpers keep their
conversion meaning. A representable pixel format is not necessarily renderable
on every surface/backend. Float color/pixel support does not imply HDR display
presentation or universally identical rounding.

XYZ-D50 concatenation/inversion is matrix arithmetic. It does not decode a
transfer function, transform encoded image samples, apply alpha, tone-map, or
reinterpret metadata. Use the documented sample-conversion operation for a
color-space conversion. Existing quantization and clipping choices remain
explicit.

### PDF and SVG

Representation and execution are separate. A GPU operation used to produce a
bounded fallback does not make that fallback vector output. PDF/SVG publication
must retain the established preflight, provenance and policy decisions. Strict
export may reject an operation that a raster surface can draw.

A raster fallback must be explicitly supported and bounded by its contract; it
is not a blanket way to mark unsupported vector output as passed. Text-as-text
versus outlined glyphs is likewise an explicit output policy. Font/backend
availability, retained dependencies, links and destinations keep their current
restrictions.

The excluded null-surface factory stays excluded. `call-with-nodraw-canvas` is a
scoped diagnostic alternative, not a surface snapshot implementation or a
PDF/SVG target. Its successful execution is not image-rendering evidence.

See [output auditing](OUTPUT-AUDIT.md), [shared output guidance](OUTPUT-GUIDE.md), and
[color output](COLOR-OUTPUT.md), together with the exact capability records.

## Examples

`examples/public/value-basics.rkt` uses public modules without native libraries
or a display. `examples/public/raster-lifetime.rkt` demonstrates an owned
surface, copied pixels, and rejection of a canvas after its owner closes. It
runs separately after pinned native installation.

The importer audit examines literal imports in every existing example. Direct
private implementation paths and testing/internals submodules are forbidden.
Some historical examples intentionally share test scene/data fixtures or
launch diagnostics; the audit records those development dependencies in its
receipt instead of advertising them as public Skia APIs. The new
`examples/public/` tutorials do not have those dependencies or computed module
imports. This source check is not a security sandbox or proof about arbitrary
computed imports/macros.

## Evidence

The two committed snapshots are captured from the exact accepted implementation
using real Racket reflection during the guarded installation step. No signatures
are guessed from source spelling, copied from a synthetic fixture, or fabricated
for a missing module. GUI imports have a separate fresh-process observation;
headless imports must not instantiate `racket/gui/base`.

The runtime gate compiles the aggregate test runner, runs the reflection fixture
suite and the aggregate pure suite, executes the public value example, and
compares every policy module's observed exports. Both Skia/HarfBuzz library
overrides name nonexistent files during these checks. Exported procedures are
not applied to discover their signatures. Module initialization and
syntax-backed identifier expansion are real Racket execution, not a claim of
zero side effects from arbitrary third-party code.

`--source-only` and `--headless-only` produce explicitly partial receipts. Only
a complete run verifies both snapshot groups. No signature check sets
`rendering_executed` or `release_ready` to true. Existing CPU/GPU/document and
consumer acceptance, and the final **0.78d release gate**, remain necessary.

### Maintainer commands

```bash
python3 tools/test-public-api.py
python3 tools/validate-public-api.py --source-only
python3 tools/validate-public-api.py --racket /absolute/path/to/racket
# Linux without a display, after installing Xvfb and GTK runtime dependencies:
xvfb-run -a python3 tools/validate-public-api.py --racket "$(command -v racket)"
```

Neither validator has an automatic approval option. Intentional future API
changes require reviewing the snapshot diff, this policy, generated index,
release-scope inputs, and source checksums together. Rerun the actual reflection
checks on the supported Racket/platform matrix. Do not regenerate the source
manifest merely to erase evidence of an unreviewed semantic/API change.

### Reflection references

Racket's Reference describes `module->exports` and `dynamic-require` under
[Module Names and Loading](https://docs.racket-lang.org/reference/Module_Names_and_Loading.html),
and positional/keyword introspection under
[Procedures](https://docs.racket-lang.org/reference/procedures.html).
The reflection implementation deliberately accounts for value-like bindings in
the syntax export list. Return-value arity inference and class instantiation are
not used as substitutes for documented contracts.
