# Third-party components

The native packages redistribute unmodified binaries from the
[SkiaSharp project](https://github.com/mono/SkiaSharp). Original licenses and
third-party notices are included, together with the component notices in
`packaging/licenses/` and the inventory in `packaging/COMPONENTS.md`.

The source ZIP contains the Racket bindings and no native library or font files.
macOS/Linux use separate native data packages. The Windows installer downloads
the pinned upstream binaries directly from NuGet; Windows DLLs are excluded
from our package and release archives.

The separate `skia-fonts-1` package contains unmodified Noto fonts, SIL OFL
notices and font copyright records. The binding's MIT license does not replace
the licenses of these third-party assets.

This product includes DNG technology under license by Adobe Systems Incorporated.
The DNG source, technology, notice and patent terms are retained in
`packaging/licenses/dng-*.txt` and in every native data package.

The package is an independent project and is not affiliated with, endorsed by,
or an official binding of the Skia or SkiaSharp projects.


## Unicode data

The mixed-text bidi, Unicode line-breaking, and Arabic joining tables include derived
property assignments from the Unicode Character Database 15.1 and Emoji 15.1
data. Unicode and the Unicode Logo are registered trademarks of Unicode, Inc.
See https://www.unicode.org/terms_of_use.html for Unicode data terms of use.
