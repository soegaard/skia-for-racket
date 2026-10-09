# Release candidate validation — 0.78d

Package version: **0.78**. Integration baseline:
`705a090d287a8a2887eb2cb4f33b43961626c6e4` (Fix public API fixture reflection).
The maintainer's all-green assumption accepts that starting point only. It is
not a receipt for the newly assembled release candidate.

## One authoritative candidate decision

Run the **Release candidate** workflow manually at the exact candidate ref.
It calls the existing CI, Acceptance, and API inventory workflows from that
same commit. Acceptance receives `regressions: full`. No workflow is fetched
from a moving branch and no earlier independent green run can substitute for
this run's work. Normal push and pull-request workflows continue unchanged in
scope; release validation does not add a fourth automatic full matrix.

The final **Release candidate required** job runs even after a dependency fails.
It verifies the caller's three `needs` results, then independently retrieves the
current attempt's complete GitHub job list with pagination. A frozen policy
expands every local reusable workflow, matrix row, authored step and artifact.
Missing, additional, duplicate, incomplete, failed, cancelled or skipped jobs
fail the decision. An explicitly platform-inapplicable step may be skipped;
that is not permission to skip a job or a required test step.

The job/step list is frozen in `api/release-candidate-policy.json` and documented
in [RELEASE-CANDIDATE-MATRIX.md](RELEASE-CANDIDATE-MATRIX.md). The checker recomputes
the graph and rejects drift. There is no `--write` or auto-approval option.
Introducing a workflow or unsupported expression fails for explicit review.
The graph checks **all** workflow files, not just a hand-selected feature list.

## Required execution and limits

CI retains isolated source-package installation, blocked-native import checks,
aggregate pure tests, native installation and ABI checks, and full CPU execution
on the declared minimum Racket and Linux, Windows and macOS lanes. Its existing
EGL, WARP/D3D12, DXGI and GUI consumer gates remain required.

Acceptance retains all feature workflows: text, fonts, geometry, effects,
integer and float pixels, direct image operations, specialized canvases,
streams/codecs, global/GPU caches and diagnostics, PDF/SVG output, and actual
DC/render-canvas consumers. Feature validation and global regressions both run.
API inventory separately requires pinned upstream/native observation, closed
0.78b scope, frozen 0.78c signatures (headless and GUI), aggregate pure execution,
and the public raster lifetime example on both declared Linux Racket versions.

A release candidate is validated **within those exercised configurations and
existing documented limitations**. Software EGL and WARP are not measurements
of hardware throughput. macOS CPU and Apple SDK ABI checks do not newly certify
physical Metal devices. No physical display, HDR, Vulkan, Graphite, universal
GLES/WebGL host, or every codec/font/backend combination is inferred.

The new aggregator does not itself rerender pixels or independently reimplement
the native/document inspectors. It requires their actual executing jobs and
steps to pass, and retains their evidence. Source availability and a successful
API reflection are not silently promoted to native execution claims.

## Evidence and source package

Every declared evidence upload must exist for the current run and attempt,
be nonempty and unexpired, identify the same commit, and carry GitHub's SHA-256
digest. The gate downloads and verifies each ZIP, validates bounded safe member
names and CRCs, and retains it without extracting or executing its contents.
An optional extra artifact is not evidence for a missing required one.

Metadata retrieval is restricted to the selected repository on api.github.com.
The read token is **not forwarded** to signed artifact-storage redirects.
Downloads, decompression and pagination have hard limits. Missing metadata,
network errors, digest mismatches, unsafe ZIPs and truncated pages fail the gate;
there is no successful fallback to the `needs` summary alone.

After the evidence passes, the gate creates `skia-for-racket-source.zip` from the
checked source manifest, with sorted entries, fixed timestamps and normalized
modes. It records the commit, source-manifest digest, policy digest, archive
digest, job/step evidence, artifact metadata and individually verified evidence
ZIPs. It rechecks the committed source before and after packaging. The native
libraries, compiled code, local caches and generated outputs are excluded.

The resulting artifact is named
`release-candidate-<commit>-<attempt>` and retained for 30 days. Archive it before
expiry when permanent release evidence is required. There is no automatic tag,
GitHub release, package-catalogue upload, branch-protection edit or version bump.

`result.json` reports `release_candidate_validated: true` only after the complete
online gate and packaging succeed. `release_ready` deliberately remains false:
this is not authorization to publish 1.0. Also require the enclosing GitHub job
and workflow to conclude successfully, including evidence upload. An interim
receipt cannot certify its own still-running job or a failed artifact upload.

## Run it

After committing and pushing the implementation, choose **Release candidate →
Run workflow** in GitHub Actions and select the candidate ref. The GitHub CLI
alternative is:

```bash
gh workflow run release-candidate.yml --ref main
```

The workflow uses only `contents: read`; its final job additionally uses
`actions: read` to inspect the current run. No inherited repository secrets,
write token, `pull_request_target` or privileged `workflow_run` is introduced.
The root and reusable workflows have distinct concurrency groups, isolated from
ordinary CI/Acceptance runs.

For a source-only check in a checkout with the validator dependencies installed:

```bash
python3 tools/test-release-candidate.py
python3 tools/validate-release-candidate.py --source-only
```

This command does not contact GitHub or run Racket. Its receipt explicitly says
`source-only`, with `release_candidate_validated: false`. It cannot replace the
manually dispatched workflow. The `--github` mode is restricted to that workflow's
identity and requires a committed, clean checkout matching `GITHUB_SHA`.

## Failures, reruns and maintenance

Use **Re-run all jobs**, or dispatch a new complete run. Re-running only failed
jobs or the final aggregator is deliberately insufficient when it would combine
jobs/artifacts from different attempts. The attempt-specific REST endpoint,
expected job coverage, timestamps and artifact names prevent that reuse.

Read `result.json` and `failure.txt` first. Partial metadata and already downloaded
evidence remain available after failure. A dependency failure is a release
failure, even when unrelated source, API or feature workflows are green.

Review deliberate changes to workflow conditions, matrices, commands and
artifact paths before generating a new policy. Update the explicit frozen
policy, generated matrix documentation, release-scope input ledger and source
manifest together. Preserve the API snapshots unless a separately reviewed API
change actually requires replacing them.

The source/capability audit retains its 0.78b identity; the public API contract
retains its 0.78c identity. This separate 0.78d execution gate combines their
current validations without inventing new capability-family dispositions.

## Reference contracts

GitHub documents same-repository reusable workflows, caller context, nesting,
permissions and concurrency behavior in [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
and [Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations).
Attempt-specific jobs and artifact metadata/downloads are documented in
[Workflow jobs](https://docs.github.com/en/rest/actions/workflow-jobs) and
[Workflow artifacts](https://docs.github.com/en/rest/actions/artifacts).
