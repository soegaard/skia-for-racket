# Initial GitHub CI push

The prepared local branch is `codex/catalog-ci`. The maintainer will push it;
the implementation agent does not push, publish packages or dispatch deployments.

From the repository, push only this branch:

```sh
git push -u origin codex/catalog-ci
```

This starts CI, Acceptance, API inventory and Catalog packaging. Central CI's
branch filter explicitly includes this branch, with regression-scope selection
kept in agreement. All ten catalog platform/version lanes remain enabled:
released Racket CS 8.18 and 9.3 on macOS ARM64/Intel, Windows x64, ordinary Linux
x64 and actual Linux natipkg. GitHub execution has not yet occurred for this
prepared commit; a configured workflow is not execution evidence.

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
workflow as part of this initial push.

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
Those receipts identify that earlier candidate, not the new push-preparation
commit. The new changes concern CI retention, branch triggers, tests and
documentation; native payloads, package API and loader behavior are unchanged.

Local preparation runs the source/synthetic suites, the source-only release
audit, collector verification against the retained real candidate, and explicit
comparison of frozen job/artifact requirements. The resulting preparation
receipts are under ignored `output/catalog/push-preparation/`.

After the push, inspect all four workflow results at the pushed commit. Use
the returned failures to guide fixes, preserving actual platform/version and
archive identities. Separate workflow successes are initial qualification
evidence; they do not replace the eventual complete same-attempt release run.
