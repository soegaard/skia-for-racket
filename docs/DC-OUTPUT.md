# Shared DC authoring for PDF and SVG — 0.63

## Scope

`skia/dc-output` adapts the existing `dc<%>` drawing subset to the existing
Skia output-page and PDF/SVG writers. The same drawing procedure can be called
from a raster/GPU paint callback, an output DC, or Racket's `record-dc%` and its
public replay procedures. It is not a replacement PDF/SVG serializer and does
not render the whole page to a bitmap to obtain a document.

The module is explicit: `(require skia/dc-output skia/output)` (or `skia` for
the ordinary output/export/audit utilities). `skia` does not re-export the DC
bridge, avoiding a cycle through the native renderer and changing no require-
time GUI/GPU initialization policy. No new native symbols or native pins.

## Public API

### `make-dc-output-page`

```racket
(make-dc-output-page width height draw
  #:unit 'pt #:margins 0 #:background #f
  #:smoothing 'smoothed #:policy 'prefer-vector
  #:on-report void)
```

Returns an ordinary `output-page?`. `draw` accepts one `dc<%>` argument.
The page constructor delegates physical units, margins, page background and
content clipping to `make-output-page`. Width/height of the content DC are
positive logical lengths, at most 32768; fractional lengths remain fractional.
`get-size` reports the content box, not the outer page or its point size.
Font geometry and all other lengths use these logical units; this bridge does
not reinterpret font% point-to-pixel sizing or impose platform-independent
font metrics. Use explicit pixel-sized fonts when specifying logical sizes.

The page background paints the outer page, including margins. Separately,
each fresh DC starts with its normal white DC background; `set-background`
and `clear` control the content DC. There is no implicit DC clear.

`#:policy` is `prefer-vector` or `require-vector`. `on-report` receives one
immutable DC-output report after successful replay, with the DC already
closed. Captured user callbacks run once per page *per export*. Exporting the
same page twice runs it twice. A preflight followed by export also runs twice,
as documented by the pre-existing output-audit API.

### `call-with-output-dc`

```racket
(call-with-output-dc canvas width height draw
  #:policy 'prefer-vector #:background "white" #:smoothing 'smoothed
  #:text-mode (current-text-output-mode)
  #:raster-scale (current-raster-output-scale))
```

The receiver must be a live PDF, SVG or CPU raster canvas with an affine 2D
transform. GPU targets and arbitrary picture-recording receivers reject;
use `gpu-dc` for ordinary GPU authoring. The existing page transform and clip
are preserved. Public DC transforms, clipping and metrics stay local.

Returns an immutable hash with `schema`, `stage`, `backend`, `command_count`,
logical dimensions, selected text/representation policies, `dc_expired`,
`groups`, `native_groups`, and `raster_groups`. Group entries use the existing
`output-group-report->jsexpr` representation, including bounds, pixel sizes,
features, labels and execution details. Nested reports can describe nested
operations; counts are not a census of driver or allocator activity.

### Predicates, capabilities and budgets

`skia-output-dc?` recognizes the callback-scoped document DC, even after it
expires. `output-dc-capabilities` is a declaration, not a runtime probe.
`current-output-dc-command-limit` defaults to 100000 positive commands per
capture, including commands in groups later discarded. Queue payloads also
have a conservative `current-skia-byte-limit` budget. Completed alpha trees
may be counted more than once. This is not a measurement of all Racket/native
memory. Large vector dimensions alone allocate no full-page RGBA backing.

The existing DC alpha controller retains its conservative area/depth byte
check, even though this renderer records command groups instead of allocating
pixel layers at `start-alpha`. A large vector-only page can therefore succeed
while a large/deep alpha group is refused. Fallback allocation is checked again
by the output-group machinery. Fallback in this DC bridge is CPU-only; the
lower-level opt-in GPU output executor is not a new option on this adapter.

## Ownership and failure behavior

The implementation captures immutable production-renderer requests, not raw
pointers or a second public recording format. It closes the real DC and releases
selected pen/brush/region locks before replaying into the native output canvas.
Saved DCs remain expired. Cross-thread/future use, nested document capture,
and continuation reentry are rejected.

A callback exception or escape emits none of its captured DC drawing commands.
Unfinished alpha groups are discarded, just as on the canvas DC. The enclosing
output page may already have emitted its independently configured background.
A native failure during replay aborts normal byte/file exporters; this is not
rollback for a caller-managed live document with earlier content. The normal
save-output functions finish bytes before publication and check destinations
before invoking authoring.

### Text and vector preservation

Use the existing `output->bytes`, `save-output`, `output->bytes/audit` and
`save-output/audit` settings. Their default auto mode selects native PDF text
and outlined SVG text. Explicit native SVG remains viewer/font dependent.
The DC bridge reuses Skia/HarfBuzz shaping, including its current text subset,
and does not substitute Cairo/Pango drawing.

Ordinary geometry, finite `clear`, intersection clips, bitmap embedding, and
supported text remain native. An identity brush-local shader map is omitted:
it changes no samples but otherwise adds unnecessary serialization-risk
provenance to a plain linear gradient. Nonidentity shader maps are unchanged.

The conservative existing output-policy table decides other cases. In
particular, `layer` is not promised vector-only on PDF and is not generally
preserved by SVG. This implementation therefore rasterizes an isolated alpha
group on both document formats under `prefer-vector`, or rejects it under
`require-vector`. It does not claim native vector PDF transparency groups.
Radial gradients, transformed shaders, stipples and hatches can likewise need
bounded fallback. Surrounding text and shapes are not included in that image.

Automatic subgroup bounds are the declared DC content extent, not tight ink
bounds. Consequently an alpha image can have page-sized dimensions while
containing only that isolated subgroup. This is not a whole-page screenshot.
Native text in a raster-needed group is rejected by existing policy instead of
silently becoming pixels. Keep labels outside that group or select outlines.
`require-vector` also rejects existing bitmap content; it means vector-only,
not merely “do not introduce new rasterization.”

### Explicit bounded raster operations

A document has no readable destination pixel backing. `copy`, `erase`,
`snapshot`, `get-rgba-bytes`, `get-png-bytes`, and `get-pixel-size` reject.
Use `output-page->image` for an explicit page preview. For a pixel-dependent
subgroup, use:

```racket
(draw-dc-raster-group dc x y width height
  (lambda (local-dc)
    ;; Put all required source/backdrop pixels INSIDE this group.
    (send local-dc set-pen "black" 1 'transparent)
    (send local-dc set-brush "red" 'solid)
    (send local-dc draw-rectangle 0 0 20 12)
    (send local-dc copy 0 0 20 12 8 0))
  #:scale 2 #:label "copied-decoration")
```

The child is an isolated transparent CPU DC. Its logical size is width/height;
its initial matrix maps to `ceil(width*scale)` by `ceil(height*scale)` pixels.
Scale uses the existing finite range 1/1024 through 1024.
It closes on all exits and cannot be resumed. The parent's selected drawing
state is not replaced. It cannot inspect already emitted document backdrop.
`require-vector` rejects before this child callback runs.

The helper also works on ordinary raster/GPU DCs via an explicit bitmap input
bridge. On document replay it uses an explicitly audited raster output group;
this can entail an additional bounded raster pass over the already captured
image, but never reruns the user callback. It is not a zero-copy optimization.
Annotations inside this helper reject rather than silently lose interactivity.

### Annotations and color-management boundaries

```racket
(dc-annotate-url! dc x y width height "https://example.org/diagram")
(dc-define-destination! dc "detail" x y)
(dc-link-destination! dc x y width height "detail")
```

Helpers capture the current logical transform/clip and emit through the real
live document annotation scope. Forward cross-page PDF links, duplicate and
unresolved name checking, and SVG views/root links reuse existing machinery.
Annotations inside isolated alpha groups reject. On ordinary raster/GPU DCs
these helpers validate arguments and otherwise do nothing. These extra helper
calls are not part of Racket's recorded-datum format; apply them to the receiving
document after ordinary recorded drawing replay.

Existing output policies, raster preview color-space options and PDF export
settings remain available; this stage adds no new ICC conversion or PDF/A
certification. Public bitmap% input is copied as its public RGBA samples, not
as an original encoded image with its ICC metadata. Native text embedding,
extraction and glyph behavior beyond the tested fixtures are not universally
certified. Accessibility/tagged-PDF generation is not added.

## Example

```racket
#lang racket/base
(require racket/class skia skia/dc-output)

(define (scene dc)
  (send dc set-pen "navy" 2 'solid)
  (send dc set-brush "lightblue" 'solid)
  (send dc draw-ellipse 20 20 120 70)
  (send dc draw-text "Shared authoring" 20 105 #t)
  (dc-annotate-url! dc 20 20 120 70 "https://example.org/diagram"))

(define page (make-dc-output-page 200 150 scene #:background 'white))
(save-output/audit page "diagram.pdf" 'pdf #:policy 'error)
(save-output/audit page "diagram.svg" 'svg #:policy 'error)
```

Use `scene` directly with a raster/GPU DC, or call it from the canvas's
`(lambda (canvas dc) ...)` paint callback. See `examples/dc-output.rkt` for
native documents and an explicit raster preview containing alpha/copy groups.

## Acceptance

The pure suite has 34 cases; the native suite has 22. Both are registered in
`run-tests.rkt` and explicitly rerun by the document validator. The validator
also requires the old DC validator because native drawing helpers are shared.
Existing GPU workflows still run their consumer and frame-reuse regressions.

The fixture worker writes exactly 24 native documents: four native/outlined
vector PDF/SVG variants, mixed vector/raster pages, patterned-style pages,
physical-unit pages, links (two pages for PDF), and pict/plot in direct,
recorded-procedure and recorded-datum modes on both formats.

```bash
# Keep the virtual environment OUTSIDE the source manifest's checkout.
python3 -m venv "$HOME/.venvs/skia-dc-output"
PYTHON="$HOME/.venvs/skia-dc-output/bin/python"
"$PYTHON" -m pip install -r tools/dc-output-requirements.txt
"$PYTHON" tools/test-dc-output.py
"$RACKET" -l raco -- make dc-output.rkt examples/dc-output.rkt
"$PYTHON" tools/validate-dc-output.py --racket "$RACKET"
```

The default gate compiles and executes actual Racket/Skia tests and checks
serialized structure: parsed PDF streams (recursing through Form XObjects),
geometry, text operations/extraction, PNG dimensions in SVG, page sizes,
native links/destinations, authoring-once receipts and strict audit reports.
It does **not** claim independently rendered pixel acceptance in this mode.

Install Poppler's `pdftoppm` and librsvg's `rsvg-convert`, then run:

```bash
"$PYTHON" tools/validate-dc-output.py --racket "$RACKET" --require-renderers
```

Full mode requires both tools and renders all 24 documents at 144 DPI (first
page of multipage PDFs). It checks interior colors, clip boundaries, group
opacity, copy locations, gradient endpoints, pict bitmap/text, and plot probes
based on the actual selected layout. It does not demand universal byte equality
between independent rasterizers. PDF page count and destinations are separately
parsed for every page. Missing renderers, files, text, annotations, markers,
stale tokens, wrong dimensions, unexpected fallback and changed source fail.

Evidence: `output/dc-output-0.63-*/validation.json`, `logs/`, and
`documents/{documents.json,inspection.json,review.html}` plus native documents
and independent PNGs when required. The “DC document output” workflow runs the
full gate on Linux Racket 8.18 and 9.3 without a display server or GPU. Its
failures are not suppressed. The existing CI aggregation and branch-protection
settings are not changed; the new workflow must be checked separately.

Python unit tests generate **synthetic** documents and ink to test the inspector
and runner. Those passing tests do not establish successful Racket compilation,
Skia document generation or native pixel results. Only a successful full native
gate and the actual retained artifacts establish that acceptance.
