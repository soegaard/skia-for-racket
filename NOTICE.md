# Third-party components

The source ZIP contains original Racket bindings and no native library or font
files. The explicit installer downloads a SkiaSharp native-assets NuGet package.
That package includes Skia and third-party components under their own licenses;
the binding's MIT license does not replace those licenses.

The installer retains the original `package.nupkg`, package metadata, source
URL, and locally computed SHA-256 hashes under `native/<platform>/`.
Review the upstream license and third-party notices before redistributing a
bundle with native binaries. See `docs/SOURCES.md` for upstream repositories.

The package is experimental and is not affiliated with, endorsed by, or an
official binding of either the Skia or Racket projects.


## Unicode data

The mixed-text bidi, Unicode line-breaking, and Arabic joining tables include derived
property assignments from the Unicode Character Database 15.1 and Emoji 15.1
data. Unicode and the Unicode Logo are registered trademarks of Unicode, Inc.
See https://www.unicode.org/terms_of_use.html for Unicode data terms of use.
