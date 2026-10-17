# Tutorial Support

These modules connect the manuals to real examples without introducing a second
implementation of their drawings. Catalog/reader/copier modules are native-free;
figure rendering and sprite ownership helpers load the drawing APIs they need.
The GUI host delays toolkit initialization until its explicit `gui` submodule.

## Metadata and Reader Integration

- [catalog.json](catalog.json) is the authoritative tutorial metadata, including
  source sets, subject categories, and separate suggested reading routes.
- [catalog.rkt](catalog.rkt) loads and validates that metadata and resolves safe source paths.
- [reader.rkt](reader.rkt) builds tutorial links, prerequisites, category/route
  listings, source downloads, and copy-and-run instructions.
- [examples.rkt](examples.rkt) copies exactly the catalog's source set into a
  new destination without overwriting existing work.
- [source.rkt](source.rkt) extracts definitions from actual example source
  without evaluating it.

## Figures

- [figures.rkt](figures.rkt) turns actual drawings and images into presentation picts.
- [accessible-figures.rkt](accessible-figures.rkt) requires meaningful alternative
  text and connects previews to the finished evaluated figure.
- [accessible-figures-test.rkt](accessible-figures-test.rkt) tests this behavior
  using Racket picts without native Skia.
- [early-figures-smoke.scrbl](early-figures-smoke.scrbl) exercises early tutorial
  figure integration; [reader-smoke.scrbl](reader-smoke.scrbl) exercises reader helpers.

## Shared Sprite-Tutorial Support

- [sprite-math.rkt](sprite-math.rkt) supplies pure timing, viewport, and atlas math.
- [sprite-assets.rkt](sprite-assets.rkt) owns the CPU atlas and context-bound GPU upload.
- [sprite-window.rkt](sprite-window.rkt) hosts rendering, input, timing, and cleanup
  in a lazily selected GUI submodule.
- [sprite-figures.rkt](sprite-figures.rkt) builds annotated previews of the actual atlas.

The complete clients are [Sprites](../sprites/README.md) and
[Star Squadron](../squadron/README.md); these helpers are documentation-local,
not additions to the public Skia library.
