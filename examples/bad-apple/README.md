# Bad Apple!! vector player

This example plays the SVG-frame data from the pinned `jhancock532/bad-console` revision with
native Skia paths. It starts paused at frame zero, preloads paths on the GUI eventspace handler,
and never parses SVG, JSON, or media while it is drawing.

The source animation and music are third-party material. They are intentionally generated outside
the repository; keep the emitted provenance file with any local asset and review upstream rights
before redistributing it.

## Prepare data

From the repository root, prepare the geometry:

```sh
python3 tools/prepare-bad-apple.py --download
```

This verifies the pinned `frames.js` SHA-256, extracts all 6,568 frame arrays and 19,110 separate
path strings, then writes `output/bad-apple/frames.json.gz`. Use `--frames-js PATH` to prepare an
already-downloaded, hash-verified source instead.

To fetch the matching MP4 for optional sound:

```sh
python3 tools/prepare-bad-apple.py --download --with-audio
```

The tool uses atomic same-directory writes, so a failed download or validation never replaces a
previous valid asset.

## Run

The portable CPU/raster presenter is the default:

```sh
racket examples/bad-apple.rkt --data output/bad-apple/frames.json.gz
```

Request direct GPU presentation explicitly:

```sh
racket examples/bad-apple.rkt --data output/bad-apple/frames.json.gz \
  --renderer gpu --backend auto
```

`auto` follows the library's normal platform choice (Metal on macOS, Direct3D on supported
Windows, and OpenGL on Unix). A requested GPU renderer reports its initialization failure; it is
not silently relabeled as raster.

The player first presents a Skia-rendered splash canvas while it loads and compiles the prepared
paths. It briefly explains the animation, identifies this as a technical demo of third-party
material, and credits the prepared frame source as `jhancock532/bad-console` at its pinned revision.
Select **Start playback** once the scene is ready.

On macOS or Linux, install `mpv` and the optional Racket `unix-socket-lib` package to run the
audio-only adapter:

```sh
racket examples/bad-apple.rkt --data output/bad-apple/frames.json.gz \
  --audio downloads/bad-apple/BadApple.mp4 --sync-offset 0
```

The adapter uses mpv JSON IPC and takes `audio-pts` (falling back to `time-pos`) as the visual
clock when a position is available. `--sync-offset S` adds `S` seconds to that clock; a positive
value advances the animation. Windows named-pipe audio is not implemented, but silent playback is.

Render a zero-based acceptance frame without opening a window:

```sh
racket tools/render-bad-apple-frame.rkt --data output/bad-apple/frames.json.gz \
  --frame 43 --output output/bad-apple/frame-0043.png
```

## Controls

| Control | Action |
| --- | --- |
| Play / Space | Play or resume; replay from zero after the end |
| Pause / Space | Freeze at the current media time |
| Restart / R | Seek to frame zero and play |
| F | Toggle the measured render-FPS readout |
| Left / Right | Pause and step exactly one frame |
| Home / End | Pause at the first or final SVG frame |
| Frame slider | Pause at and preview the selected frame |

Frame labels are zero-based. The source rate is exactly 30/1 fps; frame `i` occupies
`[i/30, (i+1)/30)`. The silent sequence ends at 218.933… seconds. The MP4 audio has a longer tail,
so when audio is active the final SVG frame is held once visual frames are exhausted.

## Rendering and lifetime notes

The same `draw-bad-apple-frame` procedure feeds both presenters. It clears letterboxing, fits the
480 × 360 viewport uniformly, paints white, and then draws ordered winding-fill paths in black.
The raster adapter maintains a physical-size Skia surface and explicitly scales its detached bitmap
into the logical GUI rectangle. The GPU adapter only touches the callback-scoped borrowed frame.

All native paths and paints are created, used, and closed on the GUI handler thread. Closing during
data load or incremental path preparation invalidates queued work and releases any partial paths.
