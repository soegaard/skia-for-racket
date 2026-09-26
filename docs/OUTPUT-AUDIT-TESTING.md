# Validating output capabilities and fallback auditing

Baseline: `15a449bcd3f59961001204a8a35f7d350d5404a8` (runtime effects).
Apply the complete 0.29 patch once to that 0.28 baseline. It preserves the
working ICC/PNG, runtime, and annotation implementations.

```bash
PATCH="downloads/skia-for-racket-0.29.0-output-audit-20260926.patch"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

git apply --check --verbose "$PATCH" &&
git apply "$PATCH" &&
git diff --check &&
RACKET="$RACKET" bash tools/validate-output-audit.sh
```

The selected Racket invokes `raco make` with `-l raco -- make` and explicitly
compiles `tests/*.rkt`. No separate `raco` is chosen from PATH. The script runs
source checks, inspector self-tests, all six existing C ABI mirrors, both native
symbol audits, doctor, the entire suite, the combined probe runner, the output
inspector, and finally `tools/update-source-sums.py`.

Expected results: **728 cases**, comprising **293 pure + 6 lifetime + 429 native**.
The new suites add **30 pure and 28 native** cases. Symbol counts remain
**319 Skia and 27 HarfBuzz**. No new native layouts are introduced.

## Review the reports as well as the pictures

Open `output/output-audit-0.29.review.html` and `output/output-audit-0.29.pdf`.
The default three-page registry exports each callback through an audited PDF,
an audited SVG, and an independent raster drawing. The reference PNGs are not
PDF/SVG rasterizations. They should not be interpreted as proof of serializer
fidelity. Actual rendering and viewer behavior remain separate checks.

| SVG suffix | Required effect images | Report observations |
| --- | --- | --- |
| `.vector.svg` | One 600x340 PNG | Plain vector geometry and explicit runtime fallback. |
| `.filters.svg` | Two 624x364 PNGs | Explicit filters with six-unit padding. PDF uses native expansion for the first panel. |
| `.recorded.svg` | One 600x340 PNG | Runtime facts survive picture recording; outer URL remains document metadata. |

The labels and surrounding geometry remain vector. The PDF contains native
text; default SVG text policy produces outlines. The optional URL has no effect
on pixel appearance and is outside the raster group.

Five JSON files are emitted: `.pdf.audit.json`, `.vector.audit.json`,
`.filters.audit.json`, `.recorded.audit.json`, and `.unsafe.audit.json`.
The last is intentionally blocking: direct runtime and image-filter drawing on
SVG is observed by preflight but no `.unsafe.svg` is published. Other reports
must have no blocking events. A report is an observation of one callback
execution, not a static promise about later executions.

The standard-library inspector validates report schema, recomputed flags,
resolved versus unresolved observations, pixel-size/report consistency,
SVG resource references, embedded PNG sizes/CRCs, and review targets.
It does not execute Racket or compare pixels. Optional PDF inspection requires
`pypdf` and checks page sizes, extractable headings, and image resources:

```bash
python3 tools/inspect-output-audit.py \
  --probe-prefix output/output-audit-0.29 --pdf
```

## Important negative tests

Strict export must reject direct SkSL on SVG/PDF before the offending native
draw. The existing destination must survive a rejected replacement. Clearing
an attachment must remove its risk; copies/getters and already recorded
pictures must retain theirs. Recorder reuse must reset the next recording.
Annotations inside raster groups must report semantic loss, not be silently
classified as resolved. Event-budget exhaustion must not return a partial
nonblocking report. Audit scopes must not leak across failed/nested calls.

## Authoring validation boundary

Racket compilation, native regression execution, the generated Skia probes,
and viewer interaction were **not run** in the authoring environment. Source
structure, patch application/reversal, Python/shell checks, six host-C layout
mirrors, and synthetic inspector tests are separate checks. Existing complete
small code files were verified by Git blob hash; core/native/doctor and large
documentation hunks were checked against fetched source contexts, not an entire
verified checkout. The machine-readable delivery validation record lists the
individual checks. `SOURCE-SHA256SUMS.txt` is intentionally regenerated on the
complete host checkout rather than computed from partial source contexts.
