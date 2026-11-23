# Native binary redistribution

The native packages redistribute unmodified binaries from the
[SkiaSharp project](https://github.com/mono/SkiaSharp). Original licenses and
third-party notices are included. The pinned versions are SkiaSharp 3.119.1
and HarfBuzzSharp 8.3.1.2.

On November 22, 2026, the project maintainer approved this licensing basis,
relying on the SkiaSharp project for its upstream binary licensing. The
component inventory, supplemental notices and source research remain available
as supporting records.

This covers the macOS/Linux native packages. On November 23, 2026, the maintainer
requested the equivalent Windows x86-64 native package. It redistributes the
same pinned SkiaSharp/HarfBuzzSharp DLLs and retains their original notices.
Raw NuGets and native libraries remain excluded from the three source packages;
DLLs belong only to `skia-native-win32-x86_64-1`. The optional direct NuGet
installer remains a developer route. The four approved fonts belong to
`skia-doc`, retaining their unchanged files, OFL notices and copyright records.

All ten catalog lanes passed at `cc9bb58545c55297b6c050cc77eb0b268e638247`
on Racket CS 8.18 and 9.3, including the direct Windows acquisition route and
real Linux natipkg. The exact receipts are recorded in the catalog validation
record. This establishes the tested transitive dependency qualification.

The unsplit candidate at `7693d907` passed the full manual Release candidate
gate (run `45096827302`, attempt 2, November 23, 2026). The revised source
package boundaries and managed Windows route require a fresh run. Native-library bytes, pins and the
approved upstream licensing basis remain unchanged. Any repository or catalog
publication still requires separate authorization.
