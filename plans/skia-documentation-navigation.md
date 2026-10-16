# Skia documentation navigation implementation plan

## Purpose and scope

Implement a shared navigation band and visual identity for the Skia Reference, future Guide, and Tutorials. A reader arriving at any chapter or tutorial through a direct link must be able to identify the documentation collection and switch collections immediately.

This is the handoff for the implementation thread, based on the approved design recommendation. It specifies implementation work, not completed functionality. Repository inspection was against `04d2552` on 2026-10-16; refresh the checkout and overlapping documentation changes before implementation.

### Agreed design

- Keep the order **Reference, Guide, Tutorials** wherever the band appears.
- Each available collection name is an ordinary link to its index.
- Tutorials has a separate disclosure button that opens grouped tutorial shortcuts. Clicking its label still navigates to the tutorial index.
- Give each collection a signature color, but distinguish the active collection with text/shape as well as color. Inactive sections receive small accents, not equally dominant colored panels.
- Keep existing chapter contents, previous/next links, search, API links, and tutorial next-step navigation.
- Treat the narrow right-edge color wash as an optional, separately testable enhancement. It must never extend behind text, code, or figures.

### Defaults resolved for implementation

1. **Guide availability:** until an actual Guide index is registered and rendered, omit its visible item. Reserve its identifier and color centrally. Do not ship a dead link, an empty Guide, or a clickable “coming soon” destination. Test the future three-item state with a synthetic fixture. When the Guide is available it occupies the middle position.
2. **Header position:** start with a band in normal page flow near the top of the documentation layout, preceding the page's reading content. Do not make a fixed or sticky header part of the first release. Sticky positioning would require additional anchor and focus-obscuring tests.
3. **Site landing page:** use the same available destinations, but no active collection. “Skia Documentation” is a neutral landing page, not a fourth collection.
4. **No JavaScript:** collection links remain usable. Hide the enhancement-only disclosure button and its panel if initialization does not complete; the Tutorials index still provides every lesson.
5. **Print:** suppress the navigation controls and edge wash. Preserve document titles, content, figures, and existing printed section information.

Out of scope: writing the Guide, changing public Skia APIs, replacing Scribble, reorganizing tutorial content, adding a search service, changing published manual URLs, publishing/deploying the site, or changing the manual deployment policy. This task produces and verifies the implementation; deployment requires a separate request.

## Current repository and integration points

| Existing source | Relevant behavior and required treatment |
| --- | --- |
| [Manual registration](/Users/soegaard/Dropbox/GitHub/skia-for-racket/info.rkt:13) | Registers a multipage Reference, a tutorial index, and 22 separately named single-page tutorial manuals. Preserve these identities and output names. No Guide is registered. |
| [Reference root](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/reference.scrbl) | Includes 13 groups and 71 leaf chapters. The header must reach every generated page, including group and index pages, not just this root. These counts are source structure, not an assumed HTML-page count. |
| [Tutorial index](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/index.scrbl) | Organizes lessons into eight learning routes. Keep the pedagogical routes intact. |
| [Tutorial catalog](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.json) and [catalog reader](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.rkt) | Already contain lesson IDs, titles, manual module paths, and route membership. Use these as menu inputs rather than copying lesson lists into JavaScript or every manual. |
| [Tutorial reader helpers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/reader.rkt) | Already create cross-document links with `seclink` and `#:doc`. They do not load native graphics. Preserve that property. |
| [Quick tutorial](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/quick/quick.scrbl) | Lives outside the normal tutorial subdirectory. Resolve it through catalog metadata, not a guessed path convention. |
| [Render driver](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference-render.rkt) | Preserves document identity and the `top` tag during standalone rendering. A solution added only here would miss ordinary `raco setup`; keep both build paths working. |
| [Reference checker](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-reference.py) and [link/site helpers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference_support.py) | The fresh-render mode currently renders only the Reference's selected companion manuals, not all 22 lessons. Site relocation recognizes a limited set of manual names. Shared navigation expands the link surface significantly. |
| [Review packaging](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference_review.py) | Hashes selected inputs and distinguishes partial bundles from complete-site checks. New shared imports/assets must be included wherever required; do not relabel partial evidence as a complete build. |
| [Pages workflow](/Users/soegaard/Dropbox/GitHub/skia-for-racket/.github/workflows/pages.yml) | Builds installed manuals, copies an explicit asset list and manual list, and then relocates/checks links. New assets must survive this collection step. Publishing is deliberately manual. |
| [Static landing page](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/pages-index.html) | Is copied separately to the site's root index. It will not acquire the shared header merely by changing Scribble manuals. |

No custom shared navigation stylesheet or script was found in the documentation sources. Names such as `doc-site.css` and `doc-site.js` already belong to the generated documentation asset set: do not overwrite them with Skia's new files.

## Architecture

Use a small shared documentation component, ordinary HTML links, scoped CSS, and a dependency-free JavaScript disclosure controller. Rendering must supply the navigation markup, destinations, and active state; JavaScript only enhances interaction. Do not fetch a catalog or header at runtime, infer the collection from a URL substring, or use client-side routing.

### Proposed files

These names are proposed new files, not existing interfaces. Keep the shared layer independent of native Skia, GUI, GPU, and tutorial evaluation modules.

| Proposed file | Responsibility |
| --- | --- |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-catalog.rkt` | Collection records, availability, module-path targets, output directory identities, and grouped tutorial-menu derivation. Read the existing tutorial catalog; do not duplicate its titles/manual paths. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-navigation.rkt` | Construct semantic navigation content and attach the shared assets/collection metadata using Scribble. Expose a small root-level integration API once the insertion spike is verified. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/skia-doc-nav.css` | Scoped band, active state, menu, responsive layout, focus treatment, and print rules. Optional edge-wash rules remain independently switchable. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/skia-doc-nav.js` | Initialize the disclosure, toggle state, close behavior, and keyboard handling. No URL generation, native work, dependencies, remote assets, or inline event handlers. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-navigation-test.rkt` | Native-free metadata, document construction, and synthetic single-/multipage rendering tests. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-documentation-navigation.py` | Parse built HTML; validate header coverage, active state, menu inventory, links, local assets, and relocation. Report the checked build scope explicitly. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-documentation-navigation.py` | Positive and negative fixtures for the new checker. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/render-documentation-navigation-fixture.rkt` | Small native-free preview covering Reference, Tutorials, neutral landing, and a synthetic available Guide. Can instead be a test submodule if that avoids unnecessary machinery. |

An automated browser smoke script may be added using the repository/environment's available browser tooling. A frontend framework, package manager, downloaded icon/font set, and new production JavaScript library are not necessary.

### Collection records

Each collection record should have a stable ID, visible label, enabled/available flag, index module path when available, expected output-directory identity, and signature-color key. The rendering call also receives a tutorial ID when applicable. Keep current-page identity separate from collection identity.

Reference targets `(lib "skia/scribblings/reference/reference.scrbl")`; Tutorials targets `(lib "skia/scribblings/tutorials/index.scrbl")`. Both use their actual `top` target through Scribble. Do not manufacture a Guide module path or public URL while it is absent. A future Guide record must supply a real module and registration before becoming enabled.

Validate duplicate IDs, missing enabled destinations, unknown tutorial IDs, and invalid route membership at build/test time. Explicitly disabled Guide metadata is valid; a supposedly enabled but missing Guide is a build error, not silently omitted navigation.

## Required Scribble integration spike

Complete this before modifying all tutorial roots. The goal is to prove the mechanism, not produce a throwaway mockup that bypasses the real renderer.

1. Build a native-free fixture containing a root, nested parts, a contents/group page, an index, and a second single-page manual. Exercise real cross-manual `top` links and assets.
2. Identify a shared source-level integration that works under both the existing render driver and ordinary `raco setup`. Prefer composition of document/style helpers; a narrowly scoped document decorator or language wrapper is acceptable if a simpler root-level hook cannot cover every emitted page. Document why it is needed before expanding its use.
3. Emit one navigation landmark per actual HTML page. Determine page boundaries from Scribble's rendering model, not by assuming every section is a page. Do not insert a header before every subsection and hide all but one with CSS or JavaScript.
4. Preserve original tags, tag prefixes, section numbering, index terms, part relationships, and document-source identity. Adding navigation must not rename headings or alter existing API anchors.
5. Attach CSS/JavaScript via supported asset properties and runtime paths. `css-addition`/`css-style-addition` and `js-addition` provide asset integration; they do not themselves insert body navigation. A title/content wrapper on an ancestor also does not automatically wrap children rendered onto separate pages. Check both cases explicitly. [Scribble structures and HTML properties](https://docs.racket-lang.org/scribble/core.html)
6. Preserve the default/manual styles and installed-document body behavior. Avoid replacing Scribble's whole HTML prefix, global stylesheet, or existing body ID just to add a collection class. The prefix configures document output, not a resolved cross-document navigation template. [Scribble output configuration](https://docs.racket-lang.org/scribble/config-style.html)
7. Verify the header is available with JavaScript disabled, ordinary links resolve, and non-HTML rendering does not leak raw HTML/JavaScript or duplicate navigation throughout a PDF. Prefer omitting the web navigation in non-HTML output.

The spike passes only when raw HTML contains the correct static links and exactly one header on each emitted page. If a prototype works only by injecting the entire header after page load, or only by running a separate postprocessor on published output, it has not satisfied the installed-document requirement.

Do not import private Scribble implementation modules as a shortcut. The locally inspected runtime is Racket 9.3.0.2 and Pages uses 9.3; avoid silently imposing a newer runtime requirement on a package whose base dependency currently starts at 8.18. Verify the chosen public hooks against supported build environments.

## Navigation and interaction specification

### Band and active state

The band contains a named navigation landmark such as `aria-label="Skia documentation"`, with a list of collection destinations. Use real anchor elements. These are links between documents, not an ARIA tab interface; do not use `tablist`, `tab`, or `tabpanel` roles.

Apply an explicit collection marker such as `data-skia-doc-section="reference"` to an appropriate page wrapper and the header. The marker must exist before JavaScript runs. Any identifier is acceptable if consistent and tested; do not overwrite Scribble's existing IDs. Emit a stable tutorial ID separately when on a tutorial.

The active collection has a strong underline/border, stronger label weight, and the signature color. It remains an index link. Use `aria-current="page"` when the link is actually the current index; use `aria-current="location"` for the collection indicator on a descendant page. Mark the actual current tutorial in the shortcut list with `aria-current="page"`. The neutral landing page has no active collection.

Retain or add a keyboard-accessible skip link to the reading content with a stable target. Its destination must not overwrite a generated heading anchor. Keep the global band visually distinct from Scribble's chapter navigation and sidebar.

### Tutorial shortcut grouping

Use catalog route order to form menu groups. Learning routes intentionally repeat prerequisites such as Images; a shortcut menu should list each tutorial once. Traverse routes in order and assign each lesson to its first occurrence, omitting empty groups. Verify every catalog tutorial appears exactly once; an uncategorized lesson must be reported instead of quietly disappearing.

With the current catalog, the derived groups are:

| Group | Tutorial IDs |
| --- | --- |
| Start with drawing | `quick`, `clock`, `logo`, `images`, `poster` |
| Text and printable documents | `text`, `shaping`, `paragraph`, `pdf-svg` |
| Effects and reusable drawings | `effects`, `pictures`, `vector-raster` |
| Windows and interactive drawings | `gpu`, `animation`, `interaction`, `navigation` |
| Pixels and color | `pixels`, `color-spaces` |
| Programmable paints | `shaders` |
| Constructed geometry | `path-ops` |
| Sprite animation and games | `sprites`, `squadron` |

These rows are acceptance expectations for today's catalog, not a second production data source. Read link labels and paths from the catalog. Keep the full route lists on the tutorial index unchanged. Put “All tutorials” first in the panel. Allow long titles to wrap; do not make important distinguishing words available only through hover tooltips.

### Disclosure behavior

Use a separate button adjacent to the Tutorials link, with a visible downward chevron, an accessible name such as “Show tutorial shortcuts,” `aria-expanded`, and `aria-controls` referencing a unique panel ID. Keep the expanded state synchronized with visibility. [W3C disclosure pattern](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/) The panel contains headings and ordinary link lists, not an application-style ARIA menu.

- Clicking the label navigates; clicking the button toggles. Modified clicks and opening links in new tabs remain native browser behavior.
- Enter/Space activate the button. Opening leaves focus on it; Tab reaches “All tutorials,” then the lesson links in reading order. Links use normal Enter activation; do not capture Space or arrow keys as custom menu navigation.
- Escape from the open navigation closes the panel and restores focus to its button.
- Clicking outside closes without stealing focus. Moving keyboard focus outside closes without returning focus to the button. Focus movement within the panel does not close it.
- Closed links are absent from the tab sequence and accessibility tree. The expanded attribute and visibility stay synchronized.
- No focus trap, hover-only behavior, automatic focus on page load, or persisted open menu across document changes. Initialization is idempotent.

This follows the ordinary-link-plus-disclosure pattern rather than application menus. Verify actual keyboard and screen-reader behavior; the published example is guidance, not production code to copy untested. [W3C disclosure navigation with top-level links](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/examples/disclosure-navigation-hybrid/)

Render menu links and markup during the documentation build. Initialize handlers before revealing the enhancement button. If the script is absent or fails, leave the collection links and tutorial index available; do not strand users behind a nonfunctional control. Use a locally copied classic script or another explicitly file-compatible mechanism, with no runtime `fetch` or module imports that break `file:` viewing.

## Visual specification

### Signature colors and contrast

Start with these color tokens; they are implementation defaults, not a requirement to preserve a particular shade after visual review.

| Collection | Accent | Contrast against white |
| --- | --- | --- |
| Reference | Blue `#245DB0` | Approximately 6.43:1 |
| Guide | Teal `#006B5E` | Approximately 6.43:1 |
| Tutorials | Purple `#7540A8` | Approximately 6.87:1 |

The ratios above are calculated for these exact solid colors on `#FFFFFF`, not a claim that all hover, tinted, or dark-theme combinations pass. Keep normal text on neutral surfaces; test actual computed combinations. Normal-size text must meet at least 4.5:1. [W3C text contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

Define shared CSS variables for all collection accents plus neutral surface, text, border, hover, and focus colors. Scope selectors under `skia-doc-*` classes or explicit collection markers. Do not globally restyle all links, code tokens, figures, headings, or Racket manuals.

Give inactive items only a small accent; the active item receives a roughly 3-pixel underline plus weight or another unmistakable shape change. Signature colors supplement the words and active-state shape; they are not the sole indicator. [W3C use-of-color guidance](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)

In forced-colors mode, use system colors and a visible border/underline, remove the decorative wash, and preserve focus indicators. Do not disable forced-color adjustment globally. A new dark theme is not part of this task; do not introduce a white rectangle that becomes unreadable if the existing environment supplies a dark surface.

### Dimensions and responsive behavior

- Start with a compact band around 44–52 CSS pixels high at ordinary desktop scale, allowing growth when text wraps or is enlarged. Do not impose a fixed height that clips labels.
- Use balanced sections within the documentation layout, not three enormous full-screen colored tiles. Preserve the same order with two or three enabled items.
- Aim for roughly 44 by 44 CSS pixels for the disclosure target. Verify target separation and minimum sizing, including the adjacent Tutorials link. [W3C target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- On a wide viewport, the tutorial panel can use two columns of groups, provided visual and DOM reading order agree. On narrow viewports use one column and a bounded scrollable panel. Keep all content within the viewport; provide a `vh` fallback if using dynamic viewport units.
- At 320 CSS pixels, retain the text labels and usable controls. Prefer natural wrapping to shrinking the type or replacing everything with unlabeled icons. No new page-wide horizontal scrolling.
- The panel should overlay content only while open and stay above it; the band itself occupies normal flow. Ensure text selection, code scrolling, existing sidebar controls, and heading permalink buttons still work.
- If sticky behavior is later added, verify focused elements and deep-linked headings are not covered. This is a separate acceptance gate, not solved by choosing a high z-index. [W3C focus visibility guidance](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)

### Optional right-edge wash

Implement only after the core navigation passes, in a separate change that can be omitted without affecting behavior.

Use the current collection color at low opacity in a narrow decorative strip, approximately 12–24 CSS pixels wide, fading inward to transparent. It may remain fixed while the document scrolls, but it must occupy genuinely unused viewport margin. Do not narrow the reading column merely to create room for it. Disable it when the margin is unavailable, on narrow screens, in print, and in forced-colors mode. The neutral landing page has no collection wash.

The strip must not overlap the scrollbar or content, intercept pointer events, add a focus stop, animate, tint transparent images, or alter their backgrounds. Do not apply a gradient to the document's entire background. Compare three captures—no wash, narrow wash, simple solid edge—and retain the least distracting effective treatment. If it adds little beyond the header, leave it off and record that outcome.

## Cross-document links, builds, and publication

### Preserve real document targets

Use module/tag references for links inside Scribble. Resolve them in the build rather than hard-coding public URLs or assuming every page has the same relative depth. Keep ordinary `<a href>` destinations in the final HTML so new-tab navigation, `file:` viewing, and offline browsing work.

Cover three environments explicitly: standalone editing previews, installed package documentation, and a staged static site hosted under a project subpath. An absolute site-root URL such as `/skia-reference/` would be wrong for many project deployments; a checkout `file:` URL would be wrong after publication.

Do not change existing manual directory names, tags, or API anchors. If the future Guide is enabled, add its exact known directory to the allowlists in site relocation and review packaging. Do not broaden those functions to rewrite arbitrary external links or infer undocumented API destinations.

### Fresh rendering must account for the larger link graph

The existing full Reference check resolves only its selected tutorial links. Every new header will expose the index and all tutorial shortcuts, and tutorial headers link back to the Reference. Make this new graph explicit:

1. Separate navigation destinations from API coverage and the existing curated editorial-link inventory. Do not replace that inventory with 22 invented “covered” API records.
2. Add a full navigation render/check route using the registered manuals and catalog. Prefer the actual installed `raco setup` build for full-site acceptance. If extending the fresh renderer, generate real cross-reference information for every enabled destination, combine it, and perform final resolution before declaring success.
3. Keep fast partial previews available. Their report must list unavailable companion destinations and say that complete navigation has not been checked. Do not suppress warnings, substitute `href="#"`, fabricate targets, or silently point at a stale installed manual to make the preview appear complete.
4. Revisit the partial-preview exception documented in [Reference Development](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md:639): “three outgoing tutorial links” will no longer describe the expanded navigation surface. Replace the fixed-count assumption with explicit build-scope evidence.
5. Keep API binding checks and their real xref evidence intact. New header links must not accidentally satisfy checks intended for editorial links in the reading content; distinguish navigation landmarks from content links where necessary.

### Asset staging and the site root

Extend the asset-copy step in the [Pages workflow](/Users/soegaard/Dropbox/GitHub/skia-for-racket/.github/workflows/pages.yml) to carry the new CSS/JavaScript at the actual locations emitted by Scribble. Check the generated paths first; assets may be shared at the documentation root or copied under manuals. Do not assume one layout and test only the other.

Update the separately copied [landing page](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/pages-index.html) to use the same metadata and styles. Prefer generating its navigation from the shared catalog in the staging step. If the source template retains a small static scaffold, add a parity test so available collections, labels, order, and targets cannot drift. No active-state label belongs on this neutral page.

Extend review/source hashing and archive inputs to include the actual new shared dependencies and assets. Preserve existing statements about partial bundles. A complete HTML bundle must include every navigation target and both assets; a partial bundle must state its limitation. Verify extraction/relocation without relying on the original checkout.

The source-inventory workflow checks [SOURCE-SHA256SUMS.txt](/Users/soegaard/Dropbox/GitHub/skia-for-racket/SOURCE-SHA256SUMS.txt). Refresh it through [the existing generator](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/update-source-sums.py) at the appropriate final integration point. Because it includes non-ignored files and other work may be active, inspect the inventory rather than blindly incorporating unrelated transient output. Preserve manual deployment triggers and permissions; do not dispatch publication as a test.

## Validation plan

### Native-free unit and rendering tests

Test collection order with Guide disabled and enabled, enabled-but-missing Guide failure, neutral landing state, duplicate IDs, unknown lesson IDs, route validity, complete menu coverage, first-occurrence grouping, and authoritative labels/module paths. Assert that requiring/building the navigation component alone does not load Skia native libraries or initialize GUI/GPU state.

Render synthetic fixtures under both single-page and multipage output. Assert exactly one header on every emitted page, no duplicate HTML IDs, correct active state, valid index destinations, unchanged original tags, and locally included assets. Verify a nested section that stays on its parent's page does not acquire an extra header. Include a synthetic Guide without creating a production Guide placeholder.

The HTML checker should detect missing headers on a deep page, wrong active collection, missing/duplicate lessons, bad disclosure IDs, dead targets, missing assets, and stale machine-local links after relocation. Include negative fixtures for each. Enumerate emitted HTML and destination metadata dynamically; do not assume there are exactly 71 Reference output files.

### Browser and accessibility checks

Run representative pages from each available collection, a deep Reference API anchor, the neutral landing page, and the synthetic Guide. Check desktop widths around 1440 and 1024, a narrow 320-pixel viewport, a short landscape viewport, 200% text enlargement/zoom, and 400% zoom/reflow. Record which browser/OS combinations actually ran; test at least Chromium and one additional engine when available.

Verify label navigation, modified/new-tab clicks, the separate disclosure, all close paths, forward/reverse tab order, visible focus, touch activation, long menu scrolling, and current tutorial indication. No focus may be stranded in a hidden panel. Test JavaScript disabled, script load failure, CSS disabled, forced colors, and print preview. The static links must still be meaningful without the enhancement.

Inspect at least one transparent image, a color-space comparison, a wide code block, and a conceptual diagram to ensure the new styles do not alter their backgrounds or layout. Test navigation through both an HTTP server under a non-root project path and local `file:` pages. Check console errors and failed asset requests. Use a screen reader to confirm landmark names, current-location announcements, disclosure state, and list/group reading order; automated accessibility checks alone do not establish that result.

### Full build and relocation acceptance

- Run the existing Reference source, binding, and installed-link checks plus the new navigation checks. Do not weaken old checks to accommodate the header.
- Build all registered manuals. Current tutorial evaluation may require native CPU dependencies; that is separate from the navigation component's native-free requirement. Record any existing unrelated failure separately.
- Stage the same assets/manuals as Pages without deploying, apply the existing relocation step, and rerun the new checker on the staged tree.
- Crawl every internal header/menu link and local CSS/script reference from every generated page. All must remain inside the intended staged documentation set and exist. Preserve legitimate external Racket documentation links.
- Move or copy the staged result to a second temporary location and test again, including `file:` browsing. Full-site output must contain no checkout paths, stale installation paths, or Skia-local redirect dependencies that the existing staging policy should have relocated.
- Confirm stable API anchors and existing sidebar/search/previous/next behavior. Record screenshots and a machine-readable report with pages checked, available collections, tutorial count, environment, missing destinations/assets, and whether a complete site was checked.

## Work sequence and handoff checkpoints

| Phase | Work | Exit criterion |
| --- | --- | --- |
| 1 Baseline and insertion spike | Refresh overlapping work; run focused existing tests; build synthetic single-/multipage fixtures; select the smallest public-hook integration. | Both standalone and installed builds emit one static, correctly linked header per page. Record the chosen mechanism before rollout. |
| 2 Shared metadata and markup | Add collection records, catalog-derived groups, Guide availability, neutral landing state, and semantic links/controls. | Native-free tests cover present/future states and all 22 current tutorials exactly once. |
| 3 Visual band and disclosure | Add scoped styles, provisional colors, active indicators, keyboard/touch behavior, and no-script/print fallbacks. | Browser interaction and responsive checks pass without the gradient. |
| 4 Root integration | Apply the shared integration to the Reference, tutorial index, Quick, and every catalog tutorial; preserve existing reader helpers and anchors. | A crawl of actual output finds full coverage and correct active state. |
| 5 Build and packaging | Extend complete-render evidence, staging, root landing, relocation, archives, and asset inventory checks. | Installed and relocated complete-site builds have no broken navigation/asset targets; partial previews are honestly labeled. |
| 6 Optional edge accent | Compare no wash, narrow wash, and solid edge; implement only if useful. | No content/scrollbar interference, correct collection color, and narrow-screen/print/forced-color suppression. Core remains complete if omitted. |
| 7 Final verification | Rerun existing and new checks, review screenshots, refresh relevant inventory, and document usage. | Deliver focused diffs, test evidence, remaining limitations, and instructions for enabling the future Guide. No deployment performed. |

Suggested commits follow those boundaries: shared component/tests; integration/styles/interaction; build/staging verification; optional edge treatment. Avoid combining this with ongoing conceptual-figure edits or API repairs. Use the shared component in future manuals rather than copying markup.

## Commands and build notes

The available local Racket at inspection time is `/Applications/Racket v9.3.0.2/bin/racket`. Use the equivalent configured runtime elsewhere. Existing focused commands, run from the repository root, include:

```sh
SKIA_DOC_RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$SKIA_DOC_RACKET" -l raco -- test \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference-render.rkt \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/reader-test.rkt
python3 -B /Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-reference.py
```

After creating the proposed tests, run their Racket and Python entry points too. Document the actual commands for the new fixture and navigation checker rather than claiming currently nonexistent flags are already supported.

Use fresh validation/output directories outside the checkout, as required by the existing Reference checker. The installed-build and site-check recipes are in [Reference Development](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md:1692) and the Pages workflow. A full `raco setup` can write installed documentation state; use an isolated package/user-home environment for reproducible staging tests and preserve the user's existing installation.

## Definition of done

The implementation is ready when all currently published documentation pages have the shared band; Reference and Tutorials navigate correctly; Guide is absent until real and can be enabled centrally; every current tutorial appears once in the grouped shortcuts; active state is understandable without color; keyboard, touch, no-script, narrow-screen, and print behavior are verified; and the same links/assets work in installed and relocated static output.

The optional gradient is not a completion blocker. A correct compact navigation band with an unobtrusive active indicator is the primary deliverable. Include a short integration note explaining how to register the Guide, how menu groups are derived, how to run the checks, and which browser/accessibility checks were actually completed.
