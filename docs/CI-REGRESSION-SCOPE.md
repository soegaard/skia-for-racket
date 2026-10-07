# Global regression scope and feature acceptance

This CI-only change targets `e0d8152ee319e82506d4383129dce732d2fe14b2`
("Clarify F16 layer contract"). Package version 0.74, native pins, rendering
semantics and pixel/document acceptance criteria are unchanged.

## Separate responsibilities

`CI` owns the complete global regression matrix. `Acceptance` owns the retained
feature acceptance jobs: effects, geometry, typefaces, font queries, text blobs,
pixels, images, GPU formats, advanced canvases, DC output and GPU/GUI consumers.
`API inventory` remains separate. There are still three automatic top-level
workflows; no feature workflow regains a push or pull-request trigger.

On a pull request, a push to `main`, or a tag matching central CI's `v*` filter,
Acceptance passes `regressions: none` to its reusable children. Those jobs no
longer run the entire `run-tests.rkt` suite as a prerequisite for testing their
own feature. The central CI jobs and their full regressions are unchanged.

A lightweight `Select regression scope` job uses the same exact trigger
conditions as `ci.yml`, including case and the fact that `v*` excludes slashes.
Other branch/tag pushes retain full regressions, since central CI does not run
for them. Manual dispatch defaults to full, both in the umbrella and in the
individual reusable workflows. The scope job needs only Python and the checked
out source; it does not wait for the global regression matrix.

**Require both `CI required` and `Acceptance required` for acceptance of a
commit.** A green feature-only Acceptance run does not mean global regressions
passed. The API inventory check remains independently relevant. This patch does
not change repository branch protection, rulesets or other settings.

Shared implementation/import errors can still legitimately affect multiple
features. This change removes redundant global-suite prerequisites, not shared
library dependencies, feature tests or error propagation.

## Local commands

The affected standalone validators retain their full-regression default:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

python tools/validate-advanced-canvases.py \
  --racket "$RACKET" \
  --require-gpu --backend metal --require-renderers
```

`--regressions=full` explicitly selects the same behavior. To run just the
selected feature gates:

```bash
python tools/validate-advanced-canvases.py \
  --racket "$RACKET" --regressions=none \
  --require-gpu --backend metal --require-renderers
```

The new option is supported by the effects, geometry-completion, typefaces,
font-queries, text-blobs, integer-pixels, float-pixels, image-operations,
gpu-formats, advanced-canvases, dc-output and dc-closure validators.

`none` omits only global regression execution and, where a validator previously
compiled the complete global test graph, the unrelated global compilation roots.
Feature roots and their transitive implementation dependencies are still
compiled. Source/manifest checks, feature-specific baselines and suites, GPU
captures, ownership checks, document parsing and selected independent renderers
remain required. A failed or missing selected gate is still fatal.

`validate-dc-closure.py` forwards the selected mode to `validate-dc-output.py` and
checks the child's report. The latter still runs the DC-specific
`validate-dc.py` baseline and its own native/document suites in either mode.
GPU DC consumer and render-canvas/reuse validators already run focused baseline
chains; these chains are not removed or treated as global regressions. Their
workflow-level global/pure regression steps become conditional instead.

## Truthful reports

The common helper `tools/validation_regressions.py` records global-suite scope
separately from overall selected-gate success. For feature-only validation:

```json
{
  "regressions_mode": "none",
  "regressions_requested": false,
  "regressions_attempted": false,
  "regressions_completed": false,
  "regressions_passed": false,
  "regressions_status": "not-run"
}
```

For full mode, the status moves from `pending` to `running` and then `passed` or
`failed`. The completed/passed fields become true only after successful global
execution. Parent validators require matching scope and exact boolean fields
in nested reports; a skipped child cannot be represented as a global pass.
Overall `status: passed` means all *selected* gates passed, not that an omitted
global suite or a separate GitHub workflow passed.

## Work avoided and work retained

For a complete normal automatic Acceptance run at this baseline, configuration
inspection identifies 34 redundant full-suite invocations and four additional
pure-suite invocations that are now omitted. This is a count of configured
invocations, not a measured speedup. Runs that fail earlier naturally execute
fewer commands.

Platform/Racket matrices, backend selection, renderer requirements, artifact
names/retention and the feature acceptance calls remain intact. One small
scope-selection job is added; the heavyweight feature job count is unchanged.
No global regressions have been removed from central CI, including those within
its existing installed-package and backend sequences. Therefore this patch does
not claim that the entire repository now runs global tests only five times.

## Checking the change

After applying the patch, regenerate the source manifest and run:

```bash
python tools/update-source-sums.py
python tools/update-source-sums.py --check
python tools/test-validation-regressions.py
python tools/test-dc-closure.py
python tools/test-ci.py
python tools/static-check.py
git diff --check
```

The scope tests exercise the actual validator main functions with native workers
and inspectors mocked: default/full execution, explicit omission, feature and
renderer failures, nested scope forwarding, and forged/missing report rejection.
They also check the reusable workflow inputs, required aggregate, selector
trigger coverage and its real command-line output. These are orchestration tests,
not native rendering or live GitHub Actions evidence.
