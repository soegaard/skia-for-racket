# DC styles and compatibility — 0.57

This stage extends the persistent CPU `skia-dc%` from the locally applied 0.56
consumer stage. It does not add GUI canvases or change the closed Ganesh layer.
Racket 8.18 and draw-lib 1.22 remain the minimum. The pict/plot consumers,
recorded procedure/datum replay, ownership and alpha-group rules are retained.

## Gradients and repeating bitmaps

Pass ordinary Racket `linear-gradient%` / `radial-gradient%` values to
`make-brush`. Rendering uses existing Skia linear/two-point-conical shaders.
Stops are validated and stably sorted; repeated offsets retain their order.
Zero stops give transparent paint and one stop gives constant paint. Negative
radii, nonfinite coordinates, invalid stop colors and oversized data are rejected.
Some degenerate radial configurations can still be rejected by Skia; this is
not a promise of equality for every degenerate Cairo gradient.

```racket
(require racket/class racket/draw skia/dc)
(define dc (new skia-dc% [width 320] [height 200] [smoothing 'smoothed]))
(define gradient
  (new linear-gradient% [x0 0] [y0 0] [x1 320] [y1 0]
       [stops (list (list 0 (make-object color% 240 60 40))
                    (list 1 (make-object color% 30 70 230)))]))
(send dc set-pen "black" 1 'transparent)
(send dc set-brush (make-brush #:gradient gradient))
(send dc draw-rectangle 0 0 320 200)
;; Read output or take a snapshot, then explicitly close the DC.
(send dc close)
```

Bitmap stipples work for both brushes and pens. Their physical source pixels
and backing scale are kept distinct from destination backing scale. Color
bitmaps retain color/alpha; monochrome black bits use the selected color.
An opaque monochrome brush uses the current DC background for white bits;
solid leaves those bits transparent. No loaded mask is implicitly applied.

Each drawing operation snapshots bitmap pixels and gradient stop colors anew.
Selecting and locking a brush does not freeze its separately mutable bitmap or
gradient color objects. There is no cross-call cache that can ignore mutation.
The existing byte limit checks explicit buffers and hatch tiles; it is not a
bound on all process or native-driver allocations.

A brush transformation specifies the pattern's coordinate system independently
of the current drawing transform, matching Racket's replacement semantics.
Source backing scale is accounted for once. Singular pattern transformations
are rejected before a new selection replaces the old one. Gradient source takes
precedence over stipple when both are supplied. A transparent selection suppresses
drawing, including patterned/gradient drawing, as in the pinned implementation.

## Hatches, legacy styles and dashes

All six hatch brushes are implemented with repeating 12×12 Skia tiles:
horizontal, vertical, crossed horizontal/vertical, both diagonals and crossed
diagonals. Intersecting lines are submitted as one stroked path so alpha is not
applied independently at each crossing. Edge antialiasing can differ from Cairo.

`xor` is a legacy solid alias, not a bitwise XOR operation. `panel` is also a
solid brush alias. `hilite` uses black at 0.3 opacity when no pattern overrides
its source; DC opacity is applied once. Monochrome bitmap `xor` uses `solid`
semantics. These names must not be mapped to a Porter–Duff XOR blend mode.

The `xor-*` pen names follow the pinned draw implementation's solid rendering.
Ordinary dot/dash patterns retain Racket's narrow/wide intervals and fixed
phase (2 for dot/simple dash; 4 for dot-dash). The pinned Racket implementation
keeps dash intervals on stippled pens, even though the general documentation
suggests stipples override the pattern. The implementation follows that actual
source behavior. This boundary is explicit rather than silently inventing
cross-version semantics.

## Alignment and path bounds

`aligned` and `unsmoothed` geometry now accept finite nonsingular affine
rotation, shear and reflection. Snapping uses the same effective row norms as
the pinned Racket implementation; smoothed geometry remains unsnapped.
This does **not** certify universal edge, hairline, dash or text pixel identity.
A singular drawing transform still produces no geometry.

`get-path-bounding-box` accepts `path`, `fill` and `stroke`. Native Skia queries
use curve extrema, filled-path simplification and stroke-to-outline conversion,
respectively. Stroke bounds use the current width, cap, join, miter and dash
settings. A zero-width stroke yields zero extents. The current clip and raster
target size do not restrict these geometric bounds. Results are logical
geometric bounds after the implemented alignment policy, not a claim to exactly
reproduce Cairo's transformed-bound approximations or sampled antialiasing ink.

One m119 C entry point is added to the existing lazy symbol inventory:
`sk_paint_get_fill_path`. Its five arguments are paint/source/destination and
a nullable cull-rectangle plus an explicit identity matrix; all owning handles are locked during
the call. No native library pin or native layout changes.

## Region utilities: a query-only Cairo boundary

The public Racket `region%` implementation internally calls its associated DC's
private `in-cairo-context` member for utilities such as `is-empty?`. A scratch
Cairo recording context now supplies that query environment, with the target's
logical extent, current clip and transformation. It is destroyed on both normal
return and exception; a continuation cannot resume with a destroyed context.

**This is not a Cairo drawing fallback.** The scratch context never receives
Skia pixel storage and is never copied or composited into the output. Actual
paths, text, images, patterns and alpha groups are drawn by Skia. Importing the
DC can load Racket's existing Cairo support, just as public `racket/draw` already
does. Region's upstream caching and geometric-query approximations remain; this
is not a replacement implementation of `region%` or a general public Cairo DC.

Native Cairo-handle brushes are still explicitly unsupported: use public bitmap
stipple input. Combined-text tabs/hard breaks and Pango-description parsing are
still deferred. General drop-in compatibility and GUI persistence are not
claimed by this stage.

## Validation and delivery boundary

The required installed-package DC gate adds 24 pure and 40 native cases. The
pure suite invokes 45 standalone production math checks. Existing 124 pure /
109 native cases and all old oracles remain; totals are now 148 pure /149 native,
plus the 24 alpha-controller and 45 style-math subchecks.

Four additional 64×64 captures cover direct drawing, recorded procedure, recorded
datum and `bitmap-dc%` reference. Each must pass independent color/pattern probes
(maximum three channel units). The three Skia paths agree within two channel
units across the full image. General reference edge differences are measured,
not hidden behind a universal pixel-equality claim. The documented bitmap
backing-scale rule is checked on direct/procedure/datum Skia paths. The pinned
`bitmap-dc%`/Cairo reference can repeat a HiDPI stipple's physical surface
instead of its logical drawing-unit period; that single backend-specific
pattern is retained for review but is not allowed to redefine the public
backing-scale contract.

The combined review retains 20 PNGs. Missing reports, missing images, reduced counts, native errors or failed
probes fail the existing required gate.

Authoring reader/model-expansion and Python tests are not host acceptance.
Run `tools/validate-dc.py` with the real installed drawing packages and Skia,
then the full regression command and existing CI, including Racket 8.18.
0.56's unreviewed local status is not retroactively turned into a CI pass.

The next planned stages are 0.58 raster `skia-canvas%` and 0.59 GPU-backed canvas.
