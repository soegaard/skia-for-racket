# Output capabilities and fallback auditing

Import `skia` or `skia/output-audit`. The pure policy table is also available
as `skia/output-policy` and does not load a native library.

An output audit answers a limited but useful question: **which known backend
risks were encountered while this drawing callback executed?** It is not a
static analyzer, image comparison, exact rasterization predictor, font-embedding
validator, color-management validator, or PDF/A conformance validator.

## Query one capability without drawing

```racket
(output-capability-for 'svg 'runtime-shader)
(output-capability-for 'pdf 'image-filter)
output-feature-names
output-backends
```

The returned immutable `output-capability?` has `backend`, `feature`, `status`,
and `reason` accessors. The table is a conservative policy for the pinned
SkiaSharp 3.119.1 / Skia m119 backend, not a probe of an arbitrary library.
Unknown feature spellings raise rather than silently meaning “supported.”

| Status | Interpretation |
| --- | --- |
| `vector` | Known vector/metadata operation; other attached features are assessed separately. |
| `embedded-raster` | An existing image is embedded. It is not vector geometry. |
| `native-expansion` | The PDF backend may expand or rasterize this feature. Pure vector preservation is not promised. |
| `needs-raster` | Use an explicit raster boundary for the conservative portable policy. |
| `viewer-dependent` | For example, native SVG text relies on viewer fonts and glyph-to-text mapping. |
| `rasterized` | An explicit raster group, or a known operation inside it. |
| `discarded` | Semantics are lost, such as a link authored inside a raster group. |
| `unknown` | Unrecognized provenance or operation. Never treated as support. |

The implementation reserves `unsupported` as another blocking status. Native
expansion does not mean “the whole page will be rasterized”; the report does not
predict exactly how many PDF image objects a backend will create. Conservative
summaries can report operations that later clipping or overpainting makes
invisible. This is a risk detector, not a rendering optimizer.

## Preflight a page

```racket
(define report (analyze-output-page page 'svg))
(output-audit-report-blocking? report)
(output-audit-report-vector-only? report)
(output-audit-report-events report)
```

The source is the same `output-page?` or nonempty page list accepted by
`output->bytes`. A PDF can have several pages; an SVG still requires one.
The normal output options are supported: title, description, text mode, raster
DPI, ID prefix, encoding quality, and PDF/A metadata mode, with the existing
backend restrictions.

**The callback executes exactly once per page.** It receives a real canvas of
the requested backend, so `canvas-annotation-backend` and backend-dependent
branches behave as during that export. Metrics, resource construction, native
SkSL compilation, graphics-state changes, and explicit raster groups still run.
Native target drawing calls are observed but suppressed, and no bytes are
returned or published by the preflight. Ordinary callback side effects are not
rolled back. Callback exceptions and invalid/missing destinations propagate.

It follows that this is not suitable for analyzing hostile or nonterminating
callbacks. It has no timeout, sandbox, whole-program proof, or automatic rewrite.
Analyzing and then exporting is **two separate callback executions**. Use an
audited export when the callback must execute only once overall.

## Export once, receiving both bytes and a report

```racket
(define-values (bytes report)
  (output->bytes/audit page 'svg #:policy 'error))

(define report
  (save-output/audit page "diagram.svg" 'svg
                     #:exists 'replace #:policy 'error))
```

`output->bytes/audit` defaults to `#:policy 'report`. It returns two values:
encoded bytes and an immutable report. `save-output/audit` defaults to the
stricter `#:policy 'error` and returns the report after successful publication.
It resolves the destination before the callback, completes drawing/finalization
before publication, and uses the existing temporary-file/rename writers.
An audit failure does not truncate or replace the destination.

Policies are:

* `report`: collect observations and otherwise preserve the normal exporter.
  Unsupported native behavior is not repaired; the resulting file may omit an
  effect. Use preflight instead to inspect a known-unsafe page without drawing it.
* `error`: stop before a native operation with `needs-raster`, `unsupported`,
  `unknown`, or `discarded` status. Embedded images and native expansion are
  allowed. Viewer-dependent text is reported, not rejected.
* `vector-only`: stop at every status other than `vector`, including ordinary
  images, explicit groups, native expansion, and viewer-dependent text.

A policy failure raises `exn:fail:output-audit?`. Its `event` accessor returns the
same immutable event shape as a report. It is not a native-error replacement:
resource lifetime, wrong-thread, invalid argument, and backend errors still use
their ordinary exceptions. “No blocking events” means no **known policy gap was
observed**, not certified visual equivalence.

## Identify operations with labels

```racket
(with-output-label "plot legend"
  (draw-text-layout canvas legend 20 30 ink))

(call-with-output-label "main image"
  (lambda () (draw-image canvas image 0 0)))
```

Labels nest, accept strings of 1–200 characters, and are copied before the body.
The procedure/macro preserve the body's return values. A report event has these
accessors:

```racket
(output-audit-event-page event)       ; one-based page index
(output-audit-event-operation event)  ; underlying wrapper operation
(output-audit-event-scope event)      ; outer-to-inner labels/group IDs
(output-audit-event-feature event)    ; symbolic feature
(output-audit-event-status event)
(output-audit-event-reason event)
(output-audit-event-details event)    ; immutable ordinary-value hash
```

A single draw can produce several events: geometry, shader, image filter, and
blender are distinct observations. High-level paragraph drawing may appear as
its constituent glyph-blob/path calls. The scope label helps identify authored
regions without retaining the callback, source program, or native object.
The report also exposes backend, number of pages, mode (`preflight` or `export`),
and events. `output-audit-report->jsexpr` returns JSON-compatible values.

## Explicit rasterization resolves representation risks, not every semantic risk

```racket
(draw-rasterized canvas 20 40 200 100
                 (lambda (rc) (draw-my-runtime-effect rc))
                 #:scale 2 #:padding 6)
```

The report records a `raster-group` event with its padded local rectangle and
actual pixel dimensions. Known operations within the group receive `rasterized`
status rather than their outer SVG/PDF serialization status. The snapshot drawn
back onto the outer canvas is separately reported as an embedded image.
Unknown operations remain unknown; a raster boundary is not a universal waiver.

Text inside a group becomes pixels. A URL/destination inside the group's raster
canvas is reported as `discarded`, even though normal raster annotation calls
are invisible no-ops. Annotate the receiving document canvas **after** drawing
the group to preserve links. A recorded URL replayed into a raster group is
likewise reported as discarded.

A custom blender needs the correct destination backdrop in the same group.
The audit does not prove that the authored group contains that backdrop, select
padding for a blur, or determine a sufficient DPI. The existing explicit density
and padding controls remain the author's responsibility.

## Resource provenance, copies, getters, and pictures

The package retains small symbolic summaries when it creates native resources.
Paint attachments copy those summaries; setting a shader/filter to `#f` removes
its previous entry, and setting an ordinary blend mode replaces custom blender
provenance. Paint copies and retained-resource getters preserve the relevant
snapshot. Shader/filter composition keeps its children's feature summaries.

These summaries contain no native pointers or strong references to original
child wrappers. They are keyed weakly by the normal lifetime cells, and do not
change the rule that native parents retain the native children they need.
An effect/child closed after successful attachment does not erase the warning
from the still-live paint or shader.

Picture recording gathers a finite feature summary even when no audit is active.
A later `draw-picture` reports that summary, so moving a runtime shader into a
picture cannot hide it from a subsequent SVG audit. Reusing a recorder resets
its summary; already-finished pictures keep their earlier snapshot. The summary
is intentionally conservative: it is not a copy of the whole display list.
Rasterizing a picture first creates an ordinary image and removes its document
interactivity, just as in the existing API. An audit cannot recover semantic-loss
warnings from a snapshot that was already flattened before the observed export;
it sees that snapshot as an existing image. Raster work performed while recording
an image into a picture is likewise already flattened when the picture replays.

The observation layer covers the library's synchronous native call wrappers.
It does not intercept foreign code that bypasses this library or arbitrary raw
FFI mutation. Imported/unrecognized provenance is reported as unknown where it
is encountered. Native pixel/color fidelity, unavailable glyph outlines, exact
clipped area, image profiles, text extraction, and viewer behavior still require
separate checks. Avoid launching unrelated low-level document exports inside an
audited callback: operations executed in that dynamic scope can be included.
An explicitly nested audited export receives its own collector.

## Limits and compatibility

`current-output-audit-event-limit` defaults to 100000 and accepts an exact
positive integer. Exceeding it raises, rather than returning a misleadingly
complete/green report. It is an event-count bound, not a total heap/CPU limit.
Audit collectors reject inherited use from another Racket thread. Separate
audits with separately owned resources are supported; no asynchronous work is
created by the API.

Existing `output->bytes`, `save-output`, and low-level PDF/SVG APIs retain their
normal behavior. Auditing and enforcement are opt-in. Small provenance records
are collected at ordinary resource construction/attachment/recording time so
resources created before an audit can still be described.

## Verification

Run `tools/validate-output-audit.sh` with the same selected Racket executable
used for the repository's existing checks. `examples/output-audit.rkt` is the
single visual registry. It produces three PDF/SVG/reference pages, export reports,
and an intentionally unsafe SVG preflight report without an unsafe SVG export.
The structural inspector checks the generated files and report consistency.
It does not compare pixels or prove that a callback has no side effects.

Policy sources are the pinned `mono/skia` commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`, particularly
`src/svg/SkSVGDevice.cpp`, `src/pdf/SkPDFDevice.cpp`,
`src/pdf/SkPDFShader.cpp`, and the runtime-effect/annotation headers; the existing
`SVG-OUTPUT.md`, `RUNTIME-EFFECTS.md`, and color-output guide record this binding's
chosen boundaries. The generic public Skia PDF limitations page can differ from
the pinned code; this table is deliberately conservative rather than a claim
that every modern Skia build has the same capability set.
