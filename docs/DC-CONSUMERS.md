# Real drawing consumers — 0.56

## Scope

This stage exercises actual `pict` and `plot/no-gui` libraries against the
persistent CPU `skia-dc%`. It deliberately uses the drawing subset accepted in
0.55. It does not add gradients, stipples, hatches, arbitrary path ink bounds,
associated-region utility queries, new alignment modes, or a GUI canvas.

The minimum stays **Racket 8.18 / draw-lib 1.22**. `pict-lib` and `plot-lib` are
now explicit package dependencies because the installed examples and required
validation modules use them. `skia/dc` itself does not import either consumer,
instantiate a GUI, or switch to a reference drawing context. The production
renderer and native pins are unchanged. Only the current-stage metadata and
deferred-feature diagnostics change in the production DC modules.

This is **a bounded compatibility corpus**, not certification of every pict,
plot renderer, or `bitmap-dc%` method. Unsupported drawing features still raise
`exn:fail:skia-dc:unsupported`. A successful corpus run does not change those
capabilities or permit silent Cairo fallback.

## Ordinary usage

```racket
#lang racket/base
(require racket/class
         (prefix-in rd: racket/draw)
         (prefix-in p: pict)
         (prefix-in plot: plot/no-gui)
         skia/dc)

(define target
  (new skia-dc% [width 640] [height 360] [smoothing 'smoothed]))
(dynamic-wind
 void
 (lambda ()
   (send target clear)
   (define picture
     (parameterize ([p:dc-for-text-size target])
       (p:hc-append 12 (p:colorize (p:disk 32) "navy")
                       (p:text "Skia" (rd:make-font #:size 18 #:family 'swiss)))))
   (p:draw-pict picture target 20 20)
   (plot:plot/dc (plot:function sin -3 3) target 20 80 600 250
                 #:title "sin(x)" #:x-label "x" #:y-label "y")
   (call-with-output-file "consumers.png"
     (lambda (out) (write-bytes (send target get-png-bytes) out))
     #:exists 'replace #:mode 'binary))
 (lambda () (send target close)))
```

The example uses the existing general-affine `'smoothed` mode; it does not
claim to fix the deferred rotated/sheared `'aligned` and `'unsmoothed` cases.
Run `racket examples/dc-consumers.rkt [output-directory]` for the exact corpus.

## What the corpus exercises

`tests/dc-consumer-fixtures.rkt` uses public library calls, not a substitute
pict implementation, custom plot renderer, or a pre-rendered plot bitmap.

The pict combines colored rectangles, a mutable Racket bitmap, actual text,
horizontal composition, rotation, scaling, and an overlapping group faded
with `cellophane #:composite? #t`. The plot calls `plot/dc` directly with a
labeled blue function, red point markers, title, axes, tick labels, and legend.
Its coordinate limits and styles are explicit.

Sixteen native RackUnit cases exercise direct rendering, 2x backing scale,
selected-object/state restoration, destination clipping, repeated replay and
pen-lock release, actual upstream procedure/datum replay, and encoding Skia
snapshots after their DC has closed. The 0.55 replay/alpha suites and both
older exact pixel oracles remain required and unchanged.

The new suite runs from `tools/dc-consumer-doctor.rkt`, called by the existing
`tools/dc-doctor.rkt`. Thus `tools/validate-dc.py` now runs **124 pure + 109
native DC cases**, plus the existing 24 alpha-controller subchecks. The new
sixteen consumer cases are not duplicated in `run-tests.rkt`; that runner
continues to cover the established 0.53–0.55 suites. The installed-package DC
gate is where the real-consumer corpus and its retained pixel checks are
mandatory.

## Evidence and tolerances

For each consumer the doctor retains four 320×240 images: direct Skia,
recorded procedure into Skia, recorded datum into Skia, and direct reference
`bitmap-dc%`. All six Skia consumer images are encoded from snapshots after
their owning DC closes. The two reference images are explicitly reference
renderings, not a fallback used by `skia-dc%`.

The independent standard-library Python inspector requires every image and
checks every one semantically. Pict solid/bitmap/group interiors must match
analytical colors within **two 8-bit channel units**; navy text must produce
actual ink in its expected region. In particular, overlapping shapes faded
individually fail the group-opacity probe.

For the plot, the doctor records the data rectangle's two DC-coordinate
corners. The inspector independently interpolates known function and point
coordinates and looks for the correct colored ink within **three pixels**.
It also requires title ink. This is an externally defined semantic probe,
not an exact geometry/antialiasing proof or an independently implemented plot
layout engine. The actual target's reported layout is an input to that probe.

The procedure and datum images from the **same recording** must agree within
two channel units throughout the image. They cannot both pass merely by being
identically blank: all semantic probes run first. Direct/reference differences
are measured and retained, with **no numeric equality acceptance threshold**.
They require manual review in `dc.review.html`.

Do not compare a directly laid-out Skia plot with one laid out by `record-dc%`
as if their metrics were necessarily identical. Each direct/reference plot
uses its own target's font metrics. Both replay forms use the recorder's
layout. The reference and Skia text rasterizers can differ. Neither universal
pixel identity nor text-metric equivalence is claimed.

`dc-consumers.json` records the sixteen-case result, execution identity,
current evidence-directory identity, capture names and plot layouts. A missing
or failed child report, wrong identity, missing/incorrect image, or reduced
case count fails the parent DC gate. Failure logs and partial evidence remain
available. `dc.inspection.json` contains the consumer checks and reference
difference statistics; `dc.review.html` includes all **sixteen** old/new PNGs.

The source fingerprint includes the new fixtures, native suite, doctor,
inspector and example. The source manifest remains the independent complete
package inventory. Requiring this stage's test data never substitutes for
running the actual native acceptance gate.

## Validation commands

From a prepared checkout with the declared Racket packages and the existing
Skia/HarfBuzz native libraries:

```sh
python3 tools/test-dc.py &&
python3 tools/test-ci.py &&
"$RACO" make dc.rkt tools/dc-doctor.rkt examples/dc-consumers.rkt run-tests.rkt &&
python3 tools/validate-dc.py --racket "$RACKET" &&
python3 tools/update-source-sums.py --check &&
git diff --check
```

`python3 tools/test_dc_consumers.py` runs the consumer inspector's synthetic
unit tests separately. Those fixtures test rejection and tolerance logic;
they are not native rendering evidence. The existing `test-dc.py` entry point
also discovers those tests, so no new optional CI lane is needed.

Existing CPU/minimum-version CI executes the expanded gate from an isolated
installed package. GPU jobs, rendering workloads, native libraries and
workflow permissions remain unchanged. A feature-branch push alone is not a
configured workflow trigger: open a pull request or explicitly run the CI
workflow for that branch. No required lane is waived.

## Following stages

0.57 addresses extended styles and remaining DC compatibility. 0.58 introduces
the raster `skia-canvas%`; 0.59 supplies its GPU-backed/scoped DC mode. This
stage intentionally does not pull any of those features forward.
