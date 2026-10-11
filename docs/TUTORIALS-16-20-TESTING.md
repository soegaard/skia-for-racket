# Tutorials 16–20: maintainer checks

This batch adds five independent examples. It changes no public library API,
renderer policy, or native binding. Tutorial 16 has its own small model module;
it does not require an uncommitted copy of Tutorial 15.

## Source manifest

After applying the patch, run from the full working checkout:

```sh
python3 tools/update-source-sums.py
python3 tools/update-source-sums.py --check
git diff --check
```

The patch intentionally leaves `SOURCE-SHA256SUMS.txt` for that local update.
The maintainer may already have Tutorial 15 and its index changes applied; a
manifest made from the older public HEAD would not describe that working tree.
Review and commit the regenerated manifest with the new tutorials. No public-API
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

The checker compiles the example modules (including the GUI module without
launching it), runs the RackUnit tests, executes five CPU still-image programs,
and builds the five Scribble manuals. It checks PNG headers/dimensions and
local HTML image references. Logs and `validation.json` go into a new directory
under `output/`. A nonzero exit is a failure; an absent Racket executable is not
a passing validation. Native Skia is required for the rendering tests and
figures, but no GPU context or GUI window is created by this batch check.

The source reader tests and navigation model tests do not need native Skia:

```sh
raco test scribblings/tutorials/support/source.rkt \
  scribblings/tutorials/navigation/tests.rkt
```

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
| 16 | Header and point labels never overlap; the anchor is fixed across zoom. |
| 17 | Straight bands become curved; parameter changes alter the pattern. |
| 18 | The source, duotone, and stamped snapshots differ; alpha is visible. |
| 19 | Linear 128 converts to roughly sRGB 188; both preview ramps are sRGB. |
| 20 | Tabs are trimmed, holes reveal the checkerboard, and the rim connects. |

The default typeface may differ across hosts. No figure should depend on one
platform's exact text metrics. The short labels have deliberate breathing room.

The figure and source-listing helpers are local documentation utilities, not new
public Skia APIs. The source helper reads the actual definitions, including local
GUI helpers, and raises if a referenced definition disappears. The evaluators
continue using `scribble/eval`; there is no evaluator-framework migration here.

The standalone Scribble build can still report unresolved links to the package's
incomplete Skia reference and can use local Racket documentation links. Inspect
cross-references again through the eventual installed/package manual build.
HTML image checks do not certify those cross-references, visual fidelity, GUI
interaction, Metal, Direct3D, or OpenGL execution.
