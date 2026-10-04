# DC compatibility boundary — 0.64

This stage closes bounded font-name translation gaps and declares the remaining
compatibility boundary. It does **not** certify a universal replacement for
`bitmap-dc%`, `record-dc%`, Cairo/Pango, or every Racket GUI consumer.

## Font descriptions

All font requests now consult `the-font-name-directory` using the font ID,
weight and style. This includes an explicit `font%` face: `get-face` no longer
bypasses a `set-screen-name` mapping. Mappings are read when preparing a new
measurement/drawing request; a captured document command keeps its copied request.
The installed Racket version's `get-screen-name` result is authoritative. This
adapter does not replace that resolver or assume it returns an assigned name
verbatim. Tests compare against its observed public result using private test IDs.

A name without a comma is a literal family name. A name containing a comma is
parsed by Racket's Pango library, following the font-name-directory convention:

```racket
(require racket/class racket/draw skia/dc)

(define f
  (make-font #:face "Arial, Bold Italic 72"
             #:size 18 #:size-in-pixels? #t))
(send dc set-font f)
(send dc draw-text "office / á" 12 12 #t)
```

The built-in `'script` family is a concrete beneficiary: Racket's macOS/Windows
defaults contain comma-style italic descriptions, previously rejected by this DC.

Here `font%` supplies size 18, not 72. Its default `'normal` weight and style
allow the description's bold/italic modifiers to apply. A non-`'normal`
explicit weight/style overrides that part of the description, as in Racket.
Numeric weight 400 is an explicit override, not the default `'normal` symbol.
`"Arial Bold"` without a comma remains a literal family name, not a parsed
bold request. `"Arial,"` means the ordinary Arial family.

The supported description subset is **one explicit family**, normal variant,
weight, normal/oblique/italic style, and the nine Pango stretch classes. Stretch
is translated to Skia's width classes 1 through 9, for both primary typeface
selection and the glyph-existence fallback request. Size always comes from the
public `font%` pixel-size accessor. Backing scale is not folded into font size.

This does not guarantee the requested face exists. Skia's existing platform
matching and per-glyph fallback policy still applies. There is no new family
cascade, synthetic font stretching, universal font metric identity, or font cache.

## Parser and ownership boundary

`private/dc-font-name.rkt` is the checked translation layer. Plain family names
need no parser. Comma descriptions lazily load `dc-font-name-native.rkt`, which
uses the **Racket-supplied Pango library and the same named FFI lock as
racket/draw**. It allocates a description, copies its fields, and frees it on
all exits. It does not create a Pango layout/font map, shape text, draw pixels,
or acquire a Skia/GPU context. Actual text still uses Skia and HarfBuzz.

The adapter introduces eight description-related Pango calls, not new Skia or
HarfBuzz symbols, and adds no package/native-library dependency. Existing
`racket/draw` imports may already load Racket's support libraries; this is not a
claim that requiring a drawing module loads no native code at all.

Names are copied and bounded by `current-skia-byte-limit`, including their UTF-8
terminator, before native parsing. The parsed request contains no native pointer.
Description parsing does not perform installed-font lookup. The private bridge
uses a synchronous, break-protected lifetime and frees on conversion failure too.

## Explicit exclusions for the 1.0 compatibility surface

The following are deliberately unsupported, rather than indefinitely described
as "almost implemented":

| Feature | Boundary / alternative |
|---|---|
| Pango family cascades | An ordered list is not equivalent to Skia's fallback policy. Select one family. |
| Non-normal variants, gravity, variable axes | Rejected; their semantics are not silently dropped or rewritten as OpenType features. |
| Combined or grapheme tabs / hard breaks | Use the library's paragraph layout API, or position single-line DC calls explicitly. |
| Native Cairo-handle brushes | Use public bitmap stipples, gradients or ordinary brushes. No native Cairo surface is imported. |
| Persistent GPU DC | GPU callback DCs expire. Use the explicit persistent raster API when required. |
| Document pixel reads, copy, erase | Use `draw-dc-raster-group` for a bounded isolated pixel operation; include its needed backdrop. |
| Automatic CPU fallback for GPU failures | Not supplied. Renderer selection and failures remain explicit. |

Unsupported descriptions reject before Skia drawing. Pango can know newer fields
that this adapter does not: any explicit field beyond family/style/variant/weight/
stretch/size is rejected by the field-mask check. This is conservative, not a full
Pango grammar implementation. The parser's own grammar remains version-specific.

The single-line separator rejection includes TAB, CR, LF, VT, FF, NEL, LINE
SEPARATOR and PARAGRAPH SEPARATOR. VT/FF no longer slip into a multiline text
layout. Character mode still removes control/format characters; other combining
and bidi behavior is unchanged. Offset selection happens before NUL truncation,
and the selected, truncated span is checked for separators.

## Machine-readable declaration

`skia/dc` now exports:

```racket
(skia-dc-compatibility)        ; ordinary persistent CPU raster DC
(skia-dc-compatibility 'gpu)  ; frame-scoped GPU DC
(skia-dc-compatibility 'pdf)  ; callback-scoped document DC
(skia-dc-compatibility 'svg)
```

These immutable reports enumerate every `dc<%>` member and supported positional
arities (excluding the receiver), checked no-ops, lifetime, document-specific
pixel-operation boundaries, and shared exclusions. They are **declarations**, not
capability probes or evidence that a driver/export has run. The older
`skia-dc-capabilities` and backend-specific reports keep their historical scopes.
This additive query does not rename existing methods or remove existing exports.

`'raster` describes the ordinary `skia-dc%`, not every scoped operation that might
use CPU storage. The portable render-canvas API still requires callback-only
`get-dc`; persistent raster access remains the explicit `get-raster-dc` method.

Document lifecycles and `flush` methods on the DC are checked no-ops; use the
owning output API or canvas to finalize/present. Font metrics, antialiasing,
hairlines, platform emoji and color fidelity have no universal Cairo/Pango or
cross-device byte-identity guarantee. Inputs remain constrained to checked finite
coordinates, alpha in [0,1], supported public object types, and the documented
allocation limits; method arity coverage is not full argument/semantic equivalence. PDF/SVG retain 0.63's conservative alpha
and patterned-paint fallbacks, text-mode choices, and annotation-loss checks.

## Acceptance and integration

`dc-closure-pure-test.rkt` contains 35 cases. It compares the entire declared
method set with the installed `dc<%>` and all accepted arities with the actual
production class, exercises pure font-field translation, font-directory mapping,
byte limits, single-line boundaries and lifetime checks. No Skia allocation is
performed by this suite; actual comma parsing belongs to the native suite.

`dc-closure-native-test.rkt` contains 22 cases. It exercises actual Pango parsing,
Skia pixels/metrics, font-directory updates, non-normal width, described versus
explicit-font equivalence at 1x/2x, recording procedure/datum replay, text under
alpha/clipping, rejected input leaving pixels unchanged, bitmap optional argument
semantics, and native/outlined PDF/SVG export with expired DC references.

Both suites are integrated into `run-tests.rkt` (native only without `--pure`).
The existing real `pict` fixture now expresses the same selected family using a
trailing-comma description. Existing CPU, GPU, frame, GUI and PDF/SVG consumer
oracles therefore exercise the new path without changing expected scene content
or weakening pixel checks. No new GPU readback is introduced.

The new validator first compiles the actual example and new modules and requires
the focused suites. It then runs the **complete 0.63 document acceptance**, which
also runs the full regression and existing DC validator. Optional gates are
mandatory when selected:

```bash
PYTHON="$HOME/.venvs/skia-dc-output/bin/python"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$PYTHON" tools/test-dc-closure.py
"$PYTHON" tools/validate-dc-closure.py --racket "$RACKET"
"$PYTHON" tools/validate-dc-closure.py --racket "$RACKET" \
  --require-renderers --require-gui
"$RACKET" examples/dc-closure.rkt
```

Use the existing `tools/dc-output-requirements.txt` inspector environment.
`--require-renderers` requires Poppler (`pdftoppm`) and librsvg (`rsvg-convert`) on
PATH. `--require-gui` adds the full 0.62 GPU-staging/unified-canvas acceptance:
Metal on macOS, EGL/OpenGL on Linux, and Direct3D on Windows (WARP is explicit).
`--backend` and `--adapter` are valid only with `--require-gui`.

Results are stored in a fresh `output/dc-closure-0.64-*` directory. Start with
`validation.json`, then `documents/documents/review.html`; GUI/reuse evidence,
when selected, is under `gui/`. These gates do not certify physical screen pixels,
PDF/A conformance, or overall memory/performance bounds.

The existing **DC document output** workflow now runs the 0.64 wrapper with
independent renderers on Racket 8.18 and 9.3. Ordinary native CI includes the new
native cases. The other three workflows retain their selection and existing
consumer oracles. No branch protection or `CI required` aggregation is changed.

The next stage is 0.65 API/package/documentation stabilization, not more backend
expansion. Acceptance of 0.64 still requires successful Racket/native/host runs;
Python/source checks alone do not establish it.

## Upstream references

The rules above follow Racket's documented font-name-directory convention and
public DC interface, not a reimplementation of Pango rendering:

- https://docs.racket-lang.org/draw/font-name-directory___.html
- https://docs.racket-lang.org/draw/dc___.html
- https://github.com/racket/draw/blob/master/draw-lib/racket/draw/unsafe/pango.rkt
- https://github.com/racket/draw/blob/master/draw-lib/racket/draw/private/dc-intf.rkt
