# Native distribution preparation

`native-assets.json` locks the six NuGet inputs, component notices, Noto font
inputs, package names/selectors and Linux support dependencies. Technical source
review is recorded in `COMPONENTS.md`; **maintainer redistribution approval and
the complete external platform matrix remain pending**.

The input observer, verified-cache preparer, offline local-fixture builder and
adversarial tests live in `tools/`. Generated ZIPs, NuGet inputs, runtime copies,
receipts and validation logs belong in ignored `output/catalog/` or disposable
temporary directories, never in the source-only package.

Use [the audit](../docs/PACKAGE-PUBLICATION-AUDIT.md) and
[runbook](../docs/PACKAGE-PUBLICATION.md) and
[current validation](../docs/CATALOG-VALIDATION.md). The builder is offline and
bounded, rejects input drift, and emits three platform data packages containing
the pair plus one universal font data package. It preserves all notices through
Racket source/built/binary-library packaging. Pending review permits only an
explicitly labelled `--local-candidate`; the release gate refuses approval.

[prototypes/linux-audit.Dockerfile](prototypes/linux-audit.Dockerfile) prepares
the Debian x86-64 audit environment. Its networking is for acquisition only.
Run `probe-linux-native-packages.py` with Docker `--network none` and read-only
input/tool mounts. Record the actual image digest and system inventory.
