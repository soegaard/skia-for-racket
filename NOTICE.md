# Third-party components

The source ZIP contains original Racket bindings and no native library or font
files. Catalog installation declares separate native and font data packages.
The developer installer also supports the pinned upstream NuGet archives.
That package includes Skia and third-party components under their own licenses;
the binding's MIT license does not replace those licenses.

The installer retains the original `package.nupkg`, package metadata, source
URL, and locally computed SHA-256 hashes under `native/<platform>/`.
Review the upstream license and third-party notices before redistributing a
bundle with native binaries. See `docs/SOURCES.md` for upstream repositories.

Native data packages retain both original NuGet notice sets plus the pinned
component texts and inventory in `packaging/licenses/` and
`packaging/COMPONENTS.md`. This includes the missing upstream Wuffs notice,
FreeType acknowledgement, Adobe DNG terms, and Linux static compiler-runtime
terms. The separate `skia-fonts-1` package contains unmodified Noto font files,
complete SIL OFL notices and the font name-table copyright records. Binding MIT
licensing does not relicense these assets. Maintainer redistribution sign-off
is pending; local candidate assembly is not permission to publish.

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
