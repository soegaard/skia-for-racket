# Generation 1 redistribution review

November 21, 2026. This records technical findings for the unchanged
SkiaSharp 3.119.1 / HarfBuzzSharp 8.3.1.2 inputs. It does not approve
redistribution. The maintainer's decision to retain `skia-fonts-1` is settled
and independent of the native review.

Amendment, November 22, 2026: the maintainer selected explicit user acquisition
from NuGet for Windows. No Windows DLL or Windows native package belongs in
this project's distributable archive set. The Windows component/toolchain
findings below remain audit material for possible later bundling; this
amendment does not approve that bundling. macOS/Linux component mapping, GCC
runtime and Adobe dispositions remain pending. Exact linker maps or individual
permission letters are possible evidence, rather than universal requirements
of the reviewed licenses; a final disposition must state its supported basis.

All ten automatic catalog lanes passed at `a37d0f8b` under the original design.
That closes the older execution gaps described below for that candidate, but
does not qualify the changed Windows acquisition path. Both new Windows lanes
must pass their explicit preparation, offline setup and non-bundling checks.

## Evidence and its limits

`component-build-evidence.json` identifies twenty primary source files by
immutable source revision or upstream release, URL and inspected-text SHA-256,
and all six binary members by archive/member SHA-256. The downloaded archives
are independently checked against `native-assets.json`; no native bytes changed.
The source text hashes describe the connector's UTF-8 representation, not Git
blob IDs. NuGet signatures are present and recorded, but have not been
cryptographically verified. Archive hashing is not signature verification.

The NuGet metadata points to SkiaSharp
`cc78b5933d23e6383db5d246e70db915770d55d6`, whose submodule selects Skia
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. Its
[library targets](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/BUILD.gn#L3521)
are `SkiaSharp` (`skia` plus `modules/skottie`) and the separate HarfBuzz subset
translation unit. Windows builds HarfBuzz through its own project.
Recipes, default arguments and ELF compiler strings agree, but do not prove
the complete arguments, archive inputs or linked object graph of a particular
NuGet build. Azure permits selecting prior external-build artifacts. A retained
exact build log/link map or upstream attestation remains necessary to close that gap.

## Component dispositions

The per-component platform/disposition entries are in the locked inventory.
These describe the reviewed source recipes, with any conservative notice
retention called out. They are not a reconstructed link map.

| Component family | Recipe evidence and disposition |
| --- | --- |
| Skia, skcms, skottie | Library target and Skia-owned sources; all three platforms |
| HarfBuzz | Separate library on all platforms; disabled inside Skia by explicit flags |
| PNG, JPEG, WebP, zlib, Wuffs | Bundled codec defaults and library dependencies; system codec flags disabled; GIF uses Wuffs |
| DNG, piex | DNG decoder dependencies and `skia_use_piex=true`; Windows explicitly enables DNG; other native defaults enable it |
| FreeType, expat | Linux bundled FreeType/font-manager route; expat notice retained conservatively on other platforms where bundled flag alone does not establish incorporation |
| Vulkan allocator, SPIR-V headers | Linux/Windows Vulkan recipes; retain notices; macOS uses Metal |
| D3D12 allocator | Windows Direct3D recipe only |
| SPIR-V Tools/Cross | Tool/test and optional validation dependencies; retain notices conservatively, do not assert runtime incorporation from the notice alone |
| GCC runtimes | Linux static-link flags and observed compiler strings; conditions below remain open |
| Microsoft runtime | Windows static CRT recipe/project; applicable redistribution terms remain open |
| ANGLE, ICU, sfntly, old GIF, SDL, imgui, jsoncpp, microhttpd | Disabled/replaced or tool-only under the reviewed defaults; original upstream notices remain verbatim |

[Skia defaults](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/gn/skia.gni)
disable Dawn, AVIF and JPEG XL. Their DEPS entries alone do not establish
incorporation of abseil/highway or their codec trees. FreeType's
[WOFF2/Brotli dependency](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/third_party/freetype2/BUILD.gn)
is conditional on WebAssembly, outside these targets. Perfetto's BUILD.gn
dependency is in the `trace` test/tool target. The official release configuration
disables development-only SPIR-V validation. Do not infer absence of every
vendored source from these defaults: unknown additional build arguments and
the exact final link graph are the remaining evidence gap.

## Linux compiler runtimes

The [x64 Docker recipe](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/scripts/Docker/debian/amd64/Dockerfile)
uses Debian 10 and Clang 13. Both pinned ELF `.comment` sections contain
`GCC: (Debian 8.3.0-6) 8.3.0` and
`Debian clang version 13.0.1-6~deb10u4`. Both library link recipes specify
`-static-libstdc++` and `-static-libgcc`; neither imports a dynamic libstdc++
or libgcc. Compiler strings do not identify every linked runtime object.

The retained [GCC Runtime Library Exception 3.1](https://github.com/gcc-mirror/gcc/blob/releases/gcc-12.2.0/COPYING.RUNTIME)
applies to runtime files carrying the GPL-plus-exception notice. Its permission
depends on independent modules and eligible compilation of all target code.
Compilation without GCC-derived work can qualify, so use of Clang does not
itself defeat the exception. Use of noncompatible software on GCC intermediate
representations does not qualify. The complete GPL and exception texts are
already shipped. Their release-12.2 source is a license-text reference, not a
claim that these binaries used GCC 12.2.

**Next evidence:** identify actual runtime archives/headers, their notices,
compiler/link arguments and any GCC-derived optimization/plugin path in the
NuGet build. Upstream build provenance or an upstream attestation can supply
this; the maintainer must review its applicability to redistribution. The
exception is not a blanket relabeling of the payload as MIT.

## Adobe DNG

All five exact pinned texts (`LICENSE`, `LICENSE.source_code`,
`LICENSE.technology`, `NOTICE`, `PATENTS`) are retained in source and native
packages. Their source is
[the selected Android DNG revision](https://android.googlesource.com/platform/external/dng_sdk/+/c8d0c9b1d16bfda56f15165d39e0ffa360a11123/).
The native README and source `NOTICE.md` prominently acknowledge:

> This product includes DNG technology under license by Adobe Systems Incorporated.

The source license allows distribution subject to retained notices and other
conditions. It restricts documentation redistribution to unmodified copies;
this package ships the supplied notices, not a modified Adobe manual. Section 5
contains a commercial-distribution indemnification obligation and section 6
restricts trademark/endorsement use. The patent grant concerns compliant DNG
implementations and essential claims, with termination conditions; it is not
an unrestricted patent assurance for other uses.

**Maintainer decision:** accept the applicable Adobe distribution conditions
and assess any commercial-distribution and patent-use implications for this
distribution. Notice preservation alone does not make that decision.

## Windows runtime and SDK

The [Skia Windows recipe](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/native/windows/build.cake)
selects toolset 14.2 by default and `/MT` for release. The
[HarfBuzz project](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/native/windows/libHarfBuzzSharp/libHarfBuzzSharp.vcxproj)
uses v142, Windows SDK 10.0.19041.0 and `MultiThreaded` for release.
Azure contains LLVM and internal MSVC paths. These defaults do not identify
which precise build/toolchain/license produced the two NuGet members.

[Microsoft documents `/MT`](https://learn.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library?view=msvc-170)
as the static runtime option. Neither pinned PE imports a VC runtime DLL;
both delay-import directories are empty. Skia imports KERNEL32, USER32, ole32,
FONTSUB, d3d12 and D3DCOMPILER_47; HarfBuzz imports KERNEL32. Linker version
fields are 14.0 and 14.29 respectively; these fields are not complete compiler
or SDK provenance. Dynamic `LoadLibrary` calls and OS DLL dependencies still
require clean-machine execution. No VC redistributable installer or Windows
system DLL is bundled or downloaded at runtime.

[Microsoft's redistribution guidance](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170)
requires checking applicable Visual Studio terms and distributable-code lists.
Static CRT inclusion is a licensing question even when no external VC DLL is
required. **Next evidence/decision:** obtain the producing toolchain version,
applicable runtime/SDK terms and upstream redistribution basis; maintainer
reviews downstream permission and any required notice. The Windows candidate
license expression therefore identifies an unresolved Microsoft runtime
license reference; the release gate remains closed.

## Transitive resolution and platform limits

Static load commands establish necessary conditions, not qualified OS minima.
Linux Skia needs glibc symbols through 2.27 and fontconfig; HarfBuzz through
2.14. There is no ELF RPATH/RUNPATH. Ordinary Linux explicitly stages OS
fontconfig and DejaVu. Real natipkg declares both Racket draw-native and TTF
packages, opens the managed fontconfig path, and derives a verified font/cache
configuration before the first font manager. Full support-package inventories
and actual resolved paths must come from the validator on a native x64 runner.
The earlier QEMU diagnostics do not establish complete execution or throughput.

Both macOS dylibs contain ARM64 and Intel slices, declaring 11.0 and 10.13 load
minima respectively, and OS framework/libc++ dependencies. Local ARM64 passes
do not qualify Intel or older OS releases. Windows 2022 and Ubuntu 24.04 are
the configured CI environments; no older Windows/distro execution claim is
made. Racket CS 8.18 and 9.3 must pass on every existing target. Linux ARM64,
musl and 32-bit remain outside scope.

The complete locked dependency snapshot and validator receipts are required
in addition to these observations. All three review flags remain false until
their actual obligations and external qualification evidence are resolved.
