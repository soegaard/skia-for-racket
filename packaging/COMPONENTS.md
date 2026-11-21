# Native generation 1 component review

The immutable input lock is `native-assets.json`. Its archive/member sizes and
SHA-256 values came from the six separately acquired NuGet inputs inspected in
Stage A; they were not guessed or accepted by the builder. The NuGet identity,
source repository commit, native machine types, load commands and required ELF
symbol versions were inspected. Fonts additionally match the Git blob SHA-1
reported independently by GitHub before their download. This relies on HTTPS
and exact source identity; it does not assert NuGet signature verification.

Technical review: November 20, 2026, Codex implementation audit. Maintainer
redistribution sign-off is **pending**. That state is retained in the lock,
archives and release gate; local testing is not publication approval.
The maintainer approved retaining the existing four-file `skia-fonts-1`
dependency and OFL notices on November 21, 2026. This fixes the font-package
design decision; it does not change any native redistribution approval flag.

## Source basis and notices

SkiaSharp/HarfBuzzSharp packages identify source
`cc78b5933d23e6383db5d246e70db915770d55d6`. That source selects Skia
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. The exact platform `build.cake`
files and Skia `DEPS`/`BUILD.gn` were reviewed. All original NuGet license and
combined notice files are retained verbatim. They contain historical/tool-only
components and do not accurately enumerate the current library by themselves.

Supplemental source texts in `licenses/` are locked by hash and source URL:

| Component | License basis | Inclusion |
| --- | --- | --- |
| SkiaSharp | MIT, NuGet LICENSE | All |
| Skia / etc1 / skcms | BSD-3-Clause, Skia LICENSE and original notices | All; skcms is within Skia's source/license tree |
| HarfBuzz | MIT-Modern-Variant, pinned COPYING | All; separate HarfBuzzSharp library |
| Wuffs | Apache-2.0, pinned release-C LICENSE | All; GIF/LZW source target and binary decoder strings confirm the missing upstream notice |
| libpng | libpng-2.0, pinned current LICENSE | PNG decoder/encoder |
| libjpeg-turbo | IJG, BSD-3-Clause, Zlib | LICENSE.md and complete README.ijg retained together |
| libwebp / expat / zlib | BSD-3-Clause / MIT / Zlib | Pinned source notices plus original package notices |
| piex | Apache-2.0 | Pinned source LICENSE corrects the historical notice inventory |
| Adobe DNG SDK | LicenseRef-Adobe-DNG-SDK | Complete LICENSE, source/technology licenses, NOTICE and PATENTS retained; acknowledgement in README |
| FreeType | FTL choice | Linux embedded font engine; full FTL and acknowledgement retained |
| SPIR-V Headers / Tools / Cross | MIT / Apache-2.0 / Apache-2.0 | GPU source dependency notices retained conservatively |
| VulkanMemoryAllocator | MIT | Linux/Windows Vulkan-enabled upstream recipe; notice retained conservatively |
| D3D12MemoryAllocator | MIT | Windows D3D12 upstream recipe |
| GCC libstdc++ / libgcc runtime | GPL-3.0-or-later WITH GCC-exception-3.1 | Linux recipe uses static runtime flags; full GPL and runtime exception retained |
| Noto Latin / Arabic / Hebrew / CJK JP | OFL-1.1 | Separate universal `skia-fonts-1` data package, unmodified fonts, complete OFL and name-table copyright records |

ANGLE, ICU, sfntly, legacy Mozilla GIF, imgui, jsoncpp, libmicrohttpd and SDL
remain in the verbatim combined notice. The library targets and platform flags
do not select the corresponding tool-only/disabled runtime components: ICU and
sfntly are explicitly disabled; GIF uses Wuffs. These dispositions do not claim
that merely including a license text incorporates that component. The lock
also records identifiers and rationale for this retained notice superset.

The [detailed follow-up review](REDISTRIBUTION-REVIEW.md) separates exact
binary observations, source-recipe dispositions and unresolved build/permission
questions. `component-build-evidence.json` records twenty primary source
identities and six binary inspections; the lock binds its digest and the builder
ships it in every native package. Windows normal and delayed imports are now
both checked; neither pinned DLL has a delayed import. The Windows license
expression explicitly identifies the unresolved embedded Microsoft runtime
terms instead of treating them as MIT.

The fonts are not installed into system font directories or substituted for the
public system font manager. Executable script tutorials select the declared
files through the existing public `typeface-from-file` API. No font
subsetting, family renaming or binary transformation is performed.

## Remaining redistribution review

NuGet does not attest the exact Linux compiler/runtime build, nor provide a
complete link map. Maintainer review must confirm the selected source graph,
GCC runtime exception applicability, Adobe conditions and Windows toolchain
redistribution terms before publication. The package-level license expressions
describe the candidate component set and are not a claim that the entire
payload is MIT. The release gate must fail while redistribution approval is
false. Nothing here authorizes publication.

## Linux support route

Ordinary Linux's explicit OS baseline includes glibc >= 2.27, fontconfig and a
default Latin font (`fonts-dejavu-core` in CI).
For the real `x86_64-linux-natipkg` target, the Linux native package declares
`draw-x86_64-linux-natipkg-3` and `draw-ttf-x86_64-linux-natipkg` directly, so it
does not rely on the main Skia package being installed first. The lazy Skia
loader opens fontconfig by its absolute Racket-managed pathname, retains the
handle, and materializes the hash-verified configuration template with absolute
declared font/cache paths in Racket's user font cache before Skia's first
font-manager initialization. It sets native `FONTCONFIG_FILE` only when no
native fontconfig override exists. Both aliases and a weak default family rule
are needed by the older natipkg fontconfig; its relative-path/prefix behavior
was insufficient in the load-order probes. Native/source payloads are not
modified. Derived font-cache entries can remain after removal. HarfBuzzSharp remains local/deep-bound and
is never replaced with Pango's HarfBuzz. Full rendering/load-order qualification
and exact support-package inventories are recorded by the catalog validator.
