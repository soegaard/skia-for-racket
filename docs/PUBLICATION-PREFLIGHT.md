# Publication preflight — revised Git package split

Nothing in this implementation authorizes a push, new public repository, tag,
release upload, catalog registration, or account/repository-setting change.
The maintainer has accepted redistribution of the unmodified
[SkiaSharp project](https://github.com/mono/SkiaSharp) binaries with notices.
The pinned native pair and the Windows direct NuGet exception are unchanged.

The successful baseline is `7693d907` / Release candidate run `45096827302`,
attempt 2, November 23, 2026. It qualified the old unsplit package. The new
`skia` / `skia-lib` / `skia-doc` boundaries require fresh evidence.

The five proposed sources, native tree, local checks and subsequent public
Git-fetch procedure are in [the publication runbook](PACKAGE-PUBLICATION.md).
There is no ZIP-host, GitHub Release or archive-branch decision to make.
No separate font package is proposed.

Before a full manual gate, review the implementation and its explicit workflow/
release-scope review, commit it, and run the Release candidate workflow at that
exact commit. This validation workflow does not publish packages. Check its
final same-attempt source/native receipts and ten catalog lanes; do not reuse
old-layout evidence or substitute source-only checks.

After that validated candidate is ready, the maintainer still needs to:

- Authorize publication of the prepared `skia-libs` repository and source layout
  on their intended default branches, then confirm their public commit IDs.
- Complete the prepared fresh anonymous Git-source installation check. Local
  copied-directory and rebuilt-archive installation are different evidence.
- Confirm the catalog account/contact and current availability of all five
  names, then explicitly authorize catalog registration using the five Git URLs.

These are later external actions. This chat's implementation phase performs
none of them. Existing catalog/repository name observations are historical;
name availability must be checked again at registration time.
