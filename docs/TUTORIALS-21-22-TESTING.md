# Tutorials 21–22: maintainer checks

The bouncing-sprite and Star Squadron tutorials share documentation-local atlas,
clock, and window helpers. No public library API or native bindings are changed.
Both use original Skia-generated artwork. No external asset download is required.



```sh
git diff --check
```

The patch leaves the manifest for local regeneration rather than overwriting
hashes for unrelated local edits. Commit the regenerated manifest with the patch.
No public API approval step is needed. The tutorial index is updated; package-wide
manual registration and Skia reference targets remain a separate integration task.

## Compile, test, render, and build

```sh
python3 scribblings/tutorials/check-21-22.py --racket /absolute/path/to/racket
```

The default run checks its Python helpers, compiles the examples, runs pure and CPU-native tests,
executes
the two CPU snapshot modes, builds both manuals, and checks image references,
PNG dimensions, and 5 + 8 figure placements. It does not open a GUI or certify
GPU execution. The GUI module is compiled, not run, in the default gate.

Add `--gui` to exercise both CPU windows or `--gpu` to exercise CPU and GPU
windows. The window smoke test uses actual render callbacks and the same
Pause, Restart, and Close functions as the controls. It checks the first GPU
atlas's native texture/context metadata and the one-upload counter across
several frames and a restart. It does not inject keyboard events, take a
physical screenshot, time performance, or independently inspect GPU pixels.
A selected failure is a failure, not a skip. See each log and `validation.json`.

The script inherits `PLTCOLLECTS` and native-library settings. For a local checkout:

```sh
(
  RACKET="/Applications/Racket v9.3.0.2/bin/racket"
  collection_root="$(mktemp -d)" || exit 1
  trap 'rm -f "$collection_root/skia"; rmdir "$collection_root"' EXIT
  ln -s "$PWD" "$collection_root/skia" || exit 1
  PLTCOLLECTS="$collection_root:" \
    python3 scribblings/tutorials/check-21-22.py \
      --racket "$RACKET" --gpu --online-doc-links
)
```

The online link option redirects known installation-document links. It does not
supply missing Skia reference targets. The report counts remaining local links
and unresolved markers; image-reference checks do not certify all hyperlinks.

## Manual acceptance

Run each example in both rendering modes on a supported graphical desktop:

```sh
racket scribblings/tutorials/sprites/balls.rkt --renderer raster
racket scribblings/tutorials/sprites/balls.rkt --renderer gpu --count 300
racket scribblings/tutorials/squadron/squadron.rkt --renderer raster
racket scribblings/tutorials/squadron/squadron.rkt --renderer gpu
```

Check these behaviors:

- The ball atlas has eight distinct cells. Source rectangles have transparent
  gutters and rotating highlights remain inside the visible circular sprite.
  Balls bounce at all four walls. There are no ball-to-ball collisions.
- GPU upload count becomes one after the first frame, stays one after Restart,
  and remains zero in CPU mode. No per-frame upload or CPU readback is intended.
  The counter measures explicit application calls, not driver memory residency.
- The game's player responds to arrows and A/D, held Space has a cooldown, and
  repeated P key events do not repeatedly toggle pause. Focus loss clears keys.
- Both enemy types animate, guards take two hits, enemies dive along mirrored
  curves and rejoin their own formation slots, and enemy shots can hit the player.
- Score increases once per destroyed enemy. Invulnerability prevents several
  immediate life losses. Game over freezes play. Restart restores three lives
  and score zero without replacing the atlas. Clearing a wave starts another.
- Pause/Resume and both native/button close controls work under load. Minimize,
  restore, resize, and move between displays of different pixel densities.
  Scene proportions stay fixed; equivalent logical placement is required, not
  byte-identical CPU/GPU pixels or equal sharpness of the CPU bitmap bridge.

The new game uses deterministic initial state and a fixed step. The live GUI
is not a deterministic input recorder. Excess elapsed time beyond 0.1 seconds
per update is discarded; this is deliberate bounded catch-up, not exact wall-time
simulation under unlimited load. Collision uses a swept projectile against an
enemy's current circular bound, not a full moving-shape time-of-impact solver.

## Visual documentation review

Inspect all 13 figure placements. The introductory game frame is an explicitly
constructed illustrated state, not a captured live session. Both atlases are
actual returned images shown at 2x with nearest sampling; checkerboards and
cell annotations are drawn separately. The dive-path diagram compresses only
the vertical coordinates, as its caption states; sampled sprite headings
come from the actual uncompressed path. The hit/miss figure compares
projectile segments against circular bounds. The two new status crops
show wave-clear and game-over overlays from the real renderer. Check title, legend, score,
lives, and control labels for clipping on platform-default fonts.

The tutorials use the existing persistent Scribble evaluators and source-listing
helper. Rendering failures must not be replaced by stale images or placeholders.
The shared helpers are part of the example files, not additions to the Skia API.
