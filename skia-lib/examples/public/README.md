# Public-API Examples

These small programs exercise the package through public modules only. They
complement the larger [example suite](../README.md) with focused checks of value
operations, ownership, and Racket Draw interoperability.

[value-basics.rkt](value-basics.rkt) needs neither native Skia nor a display.
The raster and bitmap examples require the installed native library.

## Files

- [racket-draw.rkt](racket-draw.rkt) — Exercises bitmap interoperability using only the package's public modules.
- [raster-lifetime.rkt](raster-lifetime.rkt) — Contrasts a borrowed surface canvas with detached pixel data after cleanup.
- [value-basics.rkt](value-basics.rkt) — Checks public color-value arithmetic without loading native Skia or a display.
