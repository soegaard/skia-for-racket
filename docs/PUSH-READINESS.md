# GitHub CI test branch

The test branch is `codex/catalog-ci`. The maintainer pushed `487ff148`, `d75b82d4`
and `170546e3`;
the implementation agent does not push, publish packages or dispatch deployments.
The follow-up fixes below require another maintainer push and fresh CI results.

From the repository, push only this branch:

```sh
git push origin codex/catalog-ci
```

This starts CI, Acceptance, API inventory and Catalog packaging. Central CI's
branch filter explicitly includes this branch, with regression-scope selection
kept in agreement. All ten catalog platform/version lanes remain enabled:
released Racket CS 8.18 and 9.3 on macOS ARM64/Intel, Windows x64, ordinary Linux
x64 and actual Linux natipkg. The first push passed CI, Acceptance, API inventory
and all four macOS catalog lanes. At `d75b82d4`, both ordinary Linux lanes and
natipkg 9.3 also passed; Windows reached rebuilding and natipkg 8.18 stopped
during catalog preparation. See the [second run](CATALOG-VALIDATION.md#second-github-push).

That commit makes Racket command output explicitly UTF-8, installs ordinary
Linux Racket into a self-contained directory instead of copying `/usr`, rejects
system prefixes before runtime copying, and uses a generated Latin fixture for
the fallback regression instead of assuming a system CJK font. Natipkg acquisition
can try a locked official mirror after transport failure, verifies the same
existing SHA-256 before executing either installer, and retains acquisition
failure receipts. No native pin, font package or public API changed.

Commit `170546e3` preserves nested ZIP member names on Windows, retains bounded
preparation-failure evidence and prepares the machine-independent pkg-build
runtime using the upstream bootstrap and `-MCR` startup profile. Both natipkg
versions must run again under that complete profile. The new runtime marker is
written only after successful bootstrap and a real `net/url` import check.
Normal package installation still runs with documentation enabled; the runtime
bootstrap does not replace package setup or any release gate.

At that commit, CI, API inventory and all macOS/ordinary Linux catalog lanes
passed. Acceptance's Windows WARP lane encountered a Racket download timeout
before project tests. Windows catalog validation reached binary-lib editable
source retention; both natipkg versions bootstrapped successfully but their
copied runtime caches used the old absolute path. See the
[third run](CATALOG-VALIDATION.md#third-github-push).

The next follow-up uses native metadata paths for the same editable file set
and relocates each owned natipkg cache subtree for its copied runtime, with
strict per-environment evidence. All ten native lanes and the failed Acceptance
lane still require fresh GitHub execution at the next pushed commit.

These corrections do not turn earlier failed lanes into passes. Inspect fresh
results at the new pushed commit. No Racket package server submission occurred.

## Artifact and publication behavior

Automatic catalog jobs still assemble, reproduce, install and test the exact
candidate archives. Their asset job verifies archive SHA-256, Racket checksums,
matching individual/aggregate receipts and clean committed source identity,
then uploads six JSON files containing receipts/digests. It does not upload
the native/font/source ZIPs, DLLs, dylibs, shared libraries, fonts or input NuGets.
Per-lane catalog uploads remain bounded logs and JSON receipts. Existing
CI/Acceptance rendering outputs remain required test evidence.

The collector uses a fixed receipt allowlist. It ignores other files, refuses
archive/checksum/receipt drift and cannot produce a release-qualified result.
Its generated `artifact-digests.json` explicitly records receipt-only retention
and `catalog_candidate_validated: false`.

The called workflow uses GitHub's documented caller `github.workflow` context.
Only the explicitly dispatched `Release candidate` caller selects the original
native/font/source archive upload. This preserves the full release gate's
77 jobs, 84 required artifacts and exact-byte archive checks; a receipt-only
artifact cannot substitute for the required archive set. Do not dispatch that
workflow as part of this test-branch push.

The push creates no GitHub Release, package catalog entry or package registry
upload. GitHub Pages deployment and the complete Release candidate workflow
remain manual. No tags, deployment, publication or account/repository settings
change is part of this operation.

## Review and evidence status

The [upstream search](UPSTREAM-LICENSING-SEARCH.md) and its
[evidence index](UPSTREAM-LICENSING-EVIDENCE.json) are included for review.
The GCC exception provides a documented permission route for the ordinary
build/use being tested; an individual permission letter or exact linker map
is not a general prerequisite for starting CI. Actual build provenance,
component mapping and Windows/DNG redistribution decisions remain part of
the final release review. Approval flags are unchanged and cannot be set by
successful CI alone. The approved four-font package and native pins are unchanged.

The earlier clean local candidate `71a51735` passed both complete Mac ARM64
validators (83 commands each; DrDr 19.471 s and 17.915 s). Its source ZIP was
`244405bd38eda38b60770727fb90d643679fddf9442dfaa5e2caaa17031bdfa0`.
Those receipts identify that earlier candidate, not subsequent commits. The
first GitHub candidate `487ff148` used source ZIP SHA-256
`93f6edd5e00b196d8da6bcc006ac0f54fb421ad409ebc9aab41f936cf8133c86`.
Its four macOS catalog receipts each completed all 83 commands. The subsequent
follow-up must be checked at its own commit; native payloads, package API and
loader behavior are unchanged.

Local preparation runs the source/synthetic suites, the source-only release
audit, collector verification against the retained real candidate, and explicit
comparison of frozen job/artifact requirements. The resulting preparation
receipts are under ignored `output/catalog/push-preparation/`. First GitHub
attempt artifacts, hash checks, logs and follow-up diagnostics are under
`output/catalog/github-first-run-20261121/`.

After the push, inspect all four workflow results at the pushed commit. Use
the returned failures to guide fixes, preserving actual platform/version and
archive identities. Separate workflow successes are initial qualification
evidence; they do not replace the eventual complete same-attempt release run.
