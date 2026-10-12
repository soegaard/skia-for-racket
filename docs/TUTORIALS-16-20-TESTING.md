# Tutorials 16–20: maintainer checks

This batch adds five independent examples. It changes no public library API,
renderer policy, or native binding. Tutorial 16 has its own small model module;
it does not import files from Tutorial 15.

## Source manifest

After applying the patch, run from the full working checkout:

```sh
python3 tools/update-source-sums.py
python3 tools/update-source-sums.py --check
git diff --check
```

Review and commit the source manifest with the tutorial changes. Regeneration
must use the full checkout, including any other local changes. No public-API
approval command is needed for these documentation-local additions.

## Compile, test, render, and build the five manuals

The batch checker runs real Racket commands. It does not approve snapshots,
rewrite the source manifest, replace a failed image with a placeholder, or
silently skip a failed native operation.

```sh
python3 scribblings/tutorials/check-16-20.py --racket /absolute/path/to/racket
```

The checker inherits `PLTCOLLECTS` and the normal native-library configuration.
For a checkout that is not installed as the `skia` collection, a macOS/Linux
shell can use a temporary collection link:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
collection_root="$(mktemp -d)"
ln -s "$PWD" "$collection_root/skia"

PLTCOLLECTS="$collection_root:" \
  python3 scribblings/tutorials/check-16-20.py --racket "$RACKET"

rm "$collection_root/skia"
rmdir "$collection_root"
```

The checker compiles the example modules (including both GUI examples without
launching them), runs the RackUnit tests, executes five CPU still-image programs,
and builds the five Scribble manuals. Tutorial 17's CPU program saves the first
frame of its animation, not a poster. It checks PNG headers/dimensions and
local HTML image references, including the expected figure-placement count
(6, 12, 7, 5, and 10 respectively; 40 in total). It separately reports machine-local documentation
links and unresolved reference counts; those counts are not rendering failures.
Logs and `validation.json` go into a new directory
under `output/`. A nonzero exit is a failure; an absent Racket executable is not
a passing validation. Native Skia is required for the rendering tests and
figures, but no GPU context or GUI window is created by this batch check.

The source reader tests and navigation model tests do not need native Skia:

```sh
raco test scribblings/tutorials/support/source.rkt \
  scribblings/tutorials/navigation/tests.rkt
```

## Interactive acceptance for Tutorial 17

The shader tutorial's main example is now a real-time window:

```sh
racket scribblings/tutorials/shaders/waves-window.rkt --renderer raster
racket scribblings/tutorials/shaders/waves-window.rkt --renderer gpu
```

Check that the bands travel smoothly, Frequency and Bend sliders redraw even
while paused, Pause/Resume does not advance through paused time, and both the
Close button and native window control stop the animation. On Retina/HiDPI
screens the wave field must retain the same logical proportions. The SkSL
effect is compiled once on the GUI handler thread; each frame creates and
retires a new shader instance. GPU selection uses Metal, Direct3D 12, or desktop
OpenGL according to platform, with no silent CPU fallback.

The headless Scribble build displays fixed-time CPU frames derived from the
same drawing function. It does not launch a GUI or perform GPU rendering.

## Interactive acceptance for Tutorial 16

Run the same program once with each renderer on a compatible desktop:

```sh
racket scribblings/tutorials/navigation/navigate.rkt --renderer raster
racket scribblings/tutorials/navigation/navigate.rkt --renderer gpu
```

Check left-button point dragging, an off-center grab without a jump, Shift-drag
panning, wheel zoom anchored at the pointer, both zoom buttons, Reset view,
Reset curve, Escape during a drag, and native/button window close. Verify that
hit targets stay the same logical size at zoom 0.25, 1, and 4. Verify behavior
at both zoom limits and after moving between displays with different backing
scales. A renderer failure is not a successful CPU fallback.

The CPU adapter deliberately retains the previous tutorial's logical-resolution
bitmap presentation. The GPU adapter draws at the physical framebuffer's density
while mapping geometry back to logical window units. Logical correspondence is
required; byte-identical output and equal raster sharpness are not promised.

## Visual checks

Inspect every new figure, not only the opening image. Check these details:

| Tutorial | Important checks |
|---|---|
| 16 | The coordinate grids map (120, 150) to (280, 270). P1 and hit radii stay fixed during zoom. |
| 17 | Grayscale bands precede the prismatic shader; parameters and crest glow vary separately. Moving the panel origin moves the wave field with its rectangle. |
| 18 | Alpha survives recoloring. Straight/stored red differs, but the alpha byte is unchanged. |
| 19 | Source tags and bytes differ across the valid routes. The reverse conversion gives about 55. |
| 20 | Intersection keeps overlap only. Overlapping-circle XOR keeps both non-shared sides. |

The default typeface may differ across hosts. No figure should depend on one
platform's exact text metrics. The short labels have deliberate breathing room.

The figure and source-listing helpers are local documentation utilities, not new
public Skia APIs. The source helper reads the actual definitions, including local
GUI helpers, and raises if a referenced definition disappears. The evaluators
continue using `scribble/eval`; there is no evaluator-framework migration here.

## Shareable previews and reference links

The standalone Scribble build can still report unresolved links to the package's
incomplete Skia reference and can use local Racket documentation links. The
optional preview flag redirects known installation-document links:

```sh
python3 scribblings/tutorials/check-16-20.py --racket /absolute/path/to/racket \
  --online-doc-links
```

This uses Scribble's `--redirect-main` option. It does not create missing Skia
reference targets or redirect user-scope documentation. The build still runs
locally; the resulting links are followed online when a reader opens them.
See [Running Scribble](https://docs.racket-lang.org/scribble/running.html).

The report's `html_links` field records unresolved and machine-local links even
when rendering succeeds. Inspect them again through the installed/package
manual build. HTML image checks do not certify cross-references, visual
fidelity, GUI interaction, Metal, Direct3D, or OpenGL execution.

## Regression scope after the second rendered review

The focused suites contain 51 named RackUnit cases, plus the three source-reader
assertions. The six new cases check coordinate-diagram arithmetic, panel-local
shader translation, actual straight/premultiplied readbacks, replacement rather
than compositing in a pixmap fill, reverse sRGB conversion, and overlapping-circle
XOR membership. The earlier anchor, padding, snapshot, opacity, and path-hole
checks remain in place.

These are test definitions, not execution receipts. The rendered upload reviewed
for this revision contained the previous 35 figure placements. The three added
diagrams and revised color captions need a fresh local build and visual review.
The CPU/GPU navigation program, its mouse handlers, and its model are unchanged.
