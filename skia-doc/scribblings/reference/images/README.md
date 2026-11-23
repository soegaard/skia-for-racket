# Generated Reference images

The PNG files in this directory are generated artifacts, not hand-edited artwork.
They are rendered from the real Skia API by:

```sh
racket tools/render-reference-images.rkt
```

The generator renders each scene at 2x device resolution. The Reference displays
the image at half scale so that the logical dimensions match the documented
example while remaining crisp on high-density displays.

After regeneration, run:

```sh
python3 tools/validate-reference-images.py
```

Normal Scribble builds consume the committed PNG files and do not execute Skia.
