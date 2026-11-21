# Upstream licensing search — native generation 1

Research date: November 21, 2026. Candidate baseline: `71a51735406955a3ef8c204363d1af83e6fda463`.
Native inputs remain SkiaSharp 3.119.1 / HarfBuzzSharp 8.3.1.2. This is a
research supplement to [the redistribution review](../packaging/REDISTRIBUTION-REVIEW.md),
not a redistribution sign-off. No maintainer was contacted and nothing was pushed or published.
That search did not change the lock, approval flags, workflows or previously
validated candidate archives. Later CI preparation is documented in
[push readiness](PUSH-READINESS.md).

## Findings

| Question | New evidence | Disposition |
| --- | --- | --- |
| Which release and publisher? | NuGet catalog records for all six inputs name Microsoft, declare MIT and record publication on September 23, 2025; the GitHub tag resolves to the locked source commit | Release identity and published license claim verified; component-specific conditions still apply |
| Is there an exact upstream component manifest? | The pinned `cgmanifest.json` exists, but its Skia/HarfBuzz/DNG revisions differ from the source tree selected by this release | Cannot use it as an exact native inventory |
| Are the upstream notices preserved? | All six NuGet combined notices equal the pinned source notice after CRLF-to-LF comparison | Confirmed; that notice omits GCC runtime, Windows CRT and Wuffs material, so the supplemental review remains necessary |
| Is the GCC exception the right license text? | Debian GCC 8.3.0-6 explicitly identifies libgcc and libstdc++-v3 as GPLv3-or-later with Runtime Exception 3.1; GCC 8.3 source files carry that notice | Compiler-family licensing basis established; exact linked objects/build provenance remain unconfirmed |
| Is there a Windows downstream distribution route? | Visual Studio 2019 terms explicitly provide for third-party distributors, subject to conditions | A documented conditional route exists; its applicability and obligations for the producing build still need review |
| Are Windows static SDK libraries covered? | SDK packages 10.0.19041.4/.5 link to a Windows 10 SDK license; its linked REDIST list covers static `.lib` output, including UCRT | SDK permission text located; it does not establish the producing build's complete VC runtime terms |
| Are Adobe terms missing? | All five pinned DNG license/notice/patent texts are already present, with the required acknowledgement | No additional missing DNG text identified; distribution conditions remain a maintainer decision |

The [evidence index](UPSTREAM-LICENSING-EVIDENCE.json) records source URLs,
representation and SHA-256 values. Raw responses, original Microsoft legal
documents and extracted text are in ignored `output/catalog/licensing-search-20261121/`.
NuGet signatures have not been cryptographically verified. Published author/license
metadata and exact archive hashing are distinct from signature or build attestation.

## Release and build records

The [v3.119.1 release](https://github.com/mono/SkiaSharp/releases/tag/v3.119.1)
was published September 23, 2025. Its body links a changelog and has no attached
assets or build attestation. The tag resolves to
`cc78b5933d23e6383db5d246e70db915770d55d6`, matching all six NuGet source records.
Their publication times span 21:29:14–21:29:50 UTC on that date. The NuGet catalog
entries are indexed in the evidence JSON. No PDB, SBOM, build manifest or
provenance member was found among the six package archive member names.

The [current retrospective release notes](https://github.com/mono/SkiaSharp/blob/main/documentation/docfx/releases/3.119.1.md)
say September 12, 2025 and were generated October 31, 2026. That date is recorded
separately from the actual NuGet/GitHub publication timestamps; the notes are not
an exact native build record. Their Windows interop fix concerns WinUI and does
not establish the licensing of the selected classic Win32 DLLs.

The pinned [packaging pipeline](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/scripts/azure-pipelines-package.yml)
consumes a `SkiaSharp-Native` pipeline resource. Native recipes can also reuse
prior artifacts by build ID. Thus the NuGet source revision alone does not
identify the native-producing build.

Public Azure queries for September 2025 returned zero builds, both with and
without the release-branch/definition filters. A separate query found current
retained builds, confirming that the public service responds; public definitions
4 and 64 identify SkiaSharp complete/managed-only pipelines. The queried release
branch returned no builds. These results do not establish whether historical
records expired or were produced elsewhere. The DevDiv definition 10789 linked
by the pinned README redirects anonymous requests to sign-in. No authentication
or access change was attempted. GitHub exposes no status/check-run links for
the exact release commit in the queried endpoints.

## Component manifest and notices

The pinned [component manifest](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/cgmanifest.json)
contains, among other entries:

| Component | Manifest revision | Release source selection |
| --- | --- | --- |
| mono/skia | `acad4805dfadf801d6ea62a93652c70a3fbbe10e` | `40f75dc0051d141913c07c20d4c19590c7da0cb7` |
| HarfBuzz | `be97e9d678017d4ec66625fa2b17ef3485552cad` and `6af6c1114a3495584ac4197c62592741c407b5a2` | `2b3631a866b3077d9d675caa4ec9010b342b5a7c` |
| DNG SDK | `96443b262250c390b0caefbf3eed8463ba35ecae` | `c8d0c9b1d16bfda56f15165d39e0ffa360a11123` |

The source-selection column follows the inspected submodule and pinned Skia
DEPS, already identified in `packaging/component-build-evidence.json`.
The manifest also lists old tool/disabled dependencies, so counting its entries
would not establish the linked library inventory.

The pinned [combined source notice](https://github.com/mono/SkiaSharp/blob/cc78b5933d23e6383db5d246e70db915770d55d6/External-Dependency-Info.txt)
matches all six archived notices after newline comparison. The original NuGet
notice bytes remain unchanged. This supports the existing conservative notice
superset and supplements; it does not close the exact incorporation mapping.

## GCC runtime basis

[Debian GCC 8.3.0-6's copyright record](https://sources.debian.org/src/gcc-8/8.3.0-6/debian/copyright/)
expressly covers both runtime families with GPLv3-or-later plus Runtime Exception
3.1. The corresponding GCC release's
[libgcc source notice](https://github.com/gcc-mirror/gcc/blob/releases/gcc-8.3.0/libgcc/unwind-dw2.c)
and [C++ allocation-runtime notice](https://github.com/gcc-mirror/gcc/blob/releases/gcc-8.3.0/libstdc%2B%2B-v3/libsupc%2B%2B/new_op.cc)
agree. Its exception text matches the retained text ignoring final newlines.
These sources correspond to the compiler-family string observed in both pinned
ELF images; they do not identify every linked runtime object.

The [FSF's exception FAQ](https://www.gnu.org/licenses/gcc-exception-3.1-faq.html)
explains that static and dynamic combinations receive the same conditional
permission. Separate distribution of the GNU library itself has different GPL
requirements. The exception permits qualifying compilation without GCC-derived
work and excludes incompatible processing of GCC intermediate representations.
The reviewed Clang/GCC recipes are consistent with the ordinary eligible route;
that is an inference from recipes, not proof of the actual NuGet compilation.

**Narrowed gap:** the GNU permission text and compiler-family license basis are
available. The remaining factual question is which native build/runtime inputs
produced these binaries and whether its actual compilation satisfies the exception.

## Windows terms located

The Visual Studio license directory embeds Word documents that the normal page
text extractor does not expose. The original files were downloaded and their
WordprocessingML text was read in document order:

- [Visual Studio 2019 Enterprise/Professional terms](https://visualstudio.microsoft.com/wp-content/uploads/2019/03/VS_2019_ENU.1033.docx),
  EULA ID `VS_2019_ENU.1033`: section 4 contains downstream distribution permission
  and conditions concerning functionality, recipient protection, indemnification,
  trademarks and excluded source licenses.
- [2019 diagnostic/build-tools terms](https://visualstudio.microsoft.com/wp-content/uploads/2019/03/VS_2019_DiagnosticBuildTools_ENU.1033.docx)
  address development/build-device use. They do not supply the same redistributable
  code section and are not a substitute for the producing compiler/runtime terms.
- [Visual C++ 2015–2022 runtime end-user terms](https://visualstudio.microsoft.com/wp-content/uploads/2021/09/Visual-C-Runtime-2015-2022-License-1.docx)
  grant installation/use rights. That document alone does not provide the needed
  redistribution grant for an upstream-produced library.

Both [SDK 10.0.19041.4](https://www.nuget.org/packages/Microsoft.Windows.SDK.CPP/10.0.19041.4/License)
and [10.0.19041.5](https://www.nuget.org/packages/Microsoft.Windows.SDK.CPP/10.0.19041.5/License)
point to `https://aka.ms/WinSDKLicenseURL`. At inspection it resolved to
[the Windows 10 SDK RTF](https://download.microsoft.com/download/0/F/F/0FF2B061-47DD-4F55-89B6-FD1D8C44F14D/sdk_license.rtf),
EULA ID `WIN10SDK.RTM.AUG_2018_en-US`. It provides downstream distribution and
linked-library output permissions subject to its distribution requirements.
The linked [SDK REDIST list](https://learn.microsoft.com/en-us/legal/windows-sdk/redist),
updated October 21, 2024, expressly includes static libraries under `um` and
`ucrt`, including x64. The SDK link is mutable; this captures its observed text,
not proof of the agreement attached to the exact build machine's installation.

[Microsoft's runtime documentation](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features?view=msvc-170)
separates the SDK's UCRT from compiler-specific vcruntime/startup and C++ libraries.
Consequently the SDK grant alone does not settle every component embedded by `/MT`.

**Narrowed gap:** there are explicit conditional downstream and static-library
permission routes. Confirm the actual producing toolchain/SDK, which grant
applies to its embedded components, and the obligations third-party distributors
must pass to recipients. This search establishes no need for the project
maintainer personally to purchase Visual Studio merely to redistribute these
upstream binaries; it also does not give a blanket Windows clearance.

The historical [SkiaSharp static-CRT discussion](https://github.com/mono/SkiaSharp/issues/136#issuecomment-436342647)
confirms the deployment design. Its 2018 comments do not attest the 2025 payload's
terms. Forum opinions about general CRT licensing were not treated as grants.

## Adobe and remaining decisions

The pinned DNG software grant, patent scope, notice requirements and commercial
product clause are already documented in the redistribution review and shipped
texts. No new waiver or alternative license for this exact DNG revision was found.
The maintainer still needs a disposition on the applicable terms. Upstream
SkiaSharp maintainers cannot change Adobe's terms by approving our packaging.

An exact linker map or an individual written permission is not itself a
general requirement stated by these licenses. Here build records, component
manifests or an upstream attestation are ways to substantiate this project's
inventory/provenance review. Available terms and missing build facts remain
separate questions. No approval flag is changed merely because a source exists.

## Focused request prepared for upstream — not sent

> We are preparing Racket data packages containing the unmodified Linux x64,
> universal macOS and Windows x64 libraries from SkiaSharp.NativeAssets 3.119.1
> and HarfBuzzSharp.NativeAssets 8.3.1.2. Their NuGet source commit is cc78b593.
> Could you point us to the native-producing build IDs and component/runtime
> inventory or build records? The release's cgmanifest names older revisions,
> and the public release has no build assets or attestation. For Windows, which
> VC runtime/SDK redistribution terms apply to these DLLs, and which notices or
> recipient terms must an onward distributor preserve? For Linux, confirmation
> of the actual Clang/GCC runtime build route would support our Exception 3.1 review.

The six archive and selected-member hashes are in `packaging/native-assets.json`
and were rechecked during this search. The evidence index binds that unchanged
lock digest. There is no new platform execution, release qualification or publication
approval in this research; the previously recorded execution gaps remain open.
