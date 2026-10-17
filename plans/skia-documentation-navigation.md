# Skia documentation navigation implementation plan

## Purpose and scope

Implement a shared navigation band and visual identity for the Skia Reference, future Guide, and Tutorials. A reader arriving at any chapter or tutorial through a direct link must be able to identify the documentation collection and switch collections immediately.

This is the handoff for the implementation thread, based on the approved design recommendation. The original navigation plan was inspected against `04d2552` on 2026-10-16. The tutorial index/menu revision below was checked against `4fbd818` on 2026-10-17.

### Current follow-up: separate the catalog from reading routes

The shared navigation foundation now exists. This follow-up changes the tutorial index, shortcut grouping, shared metadata, and their checks; it does not restart the header implementation. Reuse the existing navigation components and preserve the currently shipped collection band, Guide availability treatment, colors, disclosure behavior, and edge accent. The original foundation requirements below remain integration/regression context, not instructions to replay completed work or reopen those design choices.

The tutorial index at [the local preview](http://127.0.0.1:8765/skia-tutorials/index.html) currently leads with eight learning routes. A subject catalog and a reading route answer different questions:

- **Catalog:** “What can I learn or build?” Every tutorial has one explicit primary subject category.
- **Reading route:** “What should I read first, and what follows?” A pedagogical sequence can reuse tutorials from several categories and overlap other routes.

Make the index catalog-first and use the same explicit subject categories for the dropdown. Keep the existing eight reading routes intact in a separate, later section of the index. Route order and membership must not determine category membership, menu order, or whether a tutorial can be found. This supersedes the original first-occurrence-in-route grouping rule everywhere in this plan.

### Agreed design

- Keep the order **Reference, Guide, Tutorials** wherever the band appears.
- Each available collection name is an ordinary link to its index.
- Tutorials has a separate disclosure button that opens subject-grouped tutorial shortcuts. Clicking its label still navigates to the tutorial index. Index and dropdown share category membership/order, not reading-route structure.
- Give each collection a signature color, but distinguish the active collection with text/shape as well as color. Inactive sections receive small accents, not equally dominant colored panels.
- Keep existing chapter contents, previous/next links, search, API links, and tutorial next-step navigation.
- Treat the narrow right-edge color wash as an optional, separately testable enhancement. It must never extend behind text, code, or figures.

### Original navigation defaults (not reopened by this follow-up)

1. **Guide availability:** until an actual Guide index is registered and rendered, omit its visible item. Reserve its identifier and color centrally. Do not ship a dead link, an empty Guide, or a clickable “coming soon” destination. Test the future three-item state with a synthetic fixture. When the Guide is available it occupies the middle position.
2. **Header position:** start with a band in normal page flow near the top of the documentation layout, preceding the page's reading content. Do not make a fixed or sticky header part of the first release. Sticky positioning would require additional anchor and focus-obscuring tests.
3. **Site landing page:** use the same available destinations, but no active collection. “Skia Documentation” is a neutral landing page, not a fourth collection.
4. **No JavaScript:** collection links remain usable. Hide the enhancement-only disclosure button and its panel if initialization does not complete; the Tutorials index still provides every lesson.
5. **Print:** suppress the navigation controls and edge wash. Preserve document titles, content, figures, and existing printed section information.

Out of scope: writing the Guide, changing public Skia APIs, replacing Scribble, rewriting individual tutorial lessons or their prerequisite/next-step graphs, adding a search service, changing published manual URLs, publishing/deploying the site, or changing the manual deployment policy. Reorganizing the tutorial index is explicitly in scope. This task produces and verifies the implementation; deployment requires a separate request.

## Repository and integration points

The table records the original integration surface, with the tutorial catalog/index requirements updated for this follow-up. Refresh overlapping changes before implementation; do not assume that original build-integration work is still missing.

| Existing source | Relevant behavior and required treatment |
| --- | --- |
| [Manual registration](/Users/soegaard/Dropbox/GitHub/skia-for-racket/info.rkt:13) | Registers a multipage Reference, a tutorial index, and 22 separately named single-page tutorial manuals. Preserve these identities and output names. No Guide is registered. |
| [Reference root](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/reference/reference.scrbl) | Includes 13 groups and 71 leaf chapters. The header must reach every generated page, including group and index pages, not just this root. These counts are source structure, not an assumed HTML-page count. |
| [Tutorial index](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/index.scrbl) | Currently organizes lessons into eight learning routes. Add a subject catalog before those routes; preserve the sequences in a separate Suggested reading routes section. |
| [Tutorial catalog](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.json) and [catalog reader](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.rkt) | Contain lesson IDs, titles, goals, manual module paths, and routes. Add explicit subject categories and short menu titles here; never derive categories from routes or copy lesson inventories into JavaScript/manuals. |
| [Tutorial reader helpers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/reader.rkt) | Already create cross-document links with `seclink` and `#:doc`. They do not load native graphics. Preserve that property. |
| [Quick tutorial](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/quick/quick.scrbl) | Lives outside the normal tutorial subdirectory. Resolve it through catalog metadata, not a guessed path convention. |
| [Render driver](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference-render.rkt) | Preserves document identity and the `top` tag during standalone rendering. A solution added only here would miss ordinary `raco setup`; keep both build paths working. |
| [Reference checker](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-reference.py) and [link/site helpers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference_support.py) | The fresh-render mode currently renders only the Reference's selected companion manuals, not all 22 lessons. Site relocation recognizes a limited set of manual names. Shared navigation expands the link surface significantly. |
| [Review packaging](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference_review.py) | Hashes selected inputs and distinguishes partial bundles from complete-site checks. New shared imports/assets must be included wherever required; do not relabel partial evidence as a complete build. |
| [Pages workflow](/Users/soegaard/Dropbox/GitHub/skia-for-racket/.github/workflows/pages.yml) | Builds installed manuals, copies an explicit asset list and manual list, and then relocates/checks links. New assets must survive this collection step. Publishing is deliberately manual. |
| [Static landing page](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/pages-index.html) | Is copied separately to the site's root index. It will not acquire the shared header merely by changing Scribble manuals. |

The original inspection found no custom shared navigation assets. They have since been implemented as `skia-doc-nav.css` and `skia-doc-nav.js` in the shared support directory; reuse them. Names such as `doc-site.css` and `doc-site.js` belong to the generated documentation asset set and must not be overwritten.

## Architecture

Use a small shared documentation component, ordinary HTML links, scoped CSS, and a dependency-free JavaScript disclosure controller. Rendering must supply the navigation markup, destinations, and active state; JavaScript only enhances interaction. Do not fetch a catalog or header at runtime, infer the collection from a URL substring, or use client-side routing.

### Shared component responsibilities

These were the original proposed component names; the main shared components and checkers now exist. Inspect and extend their current interfaces rather than creating parallel implementations. Keep the shared layer independent of native Skia, GUI, GPU, and tutorial evaluation modules.

| File | Responsibility |
| --- | --- |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-catalog.rkt` | Collection records, availability, module-path targets, output directory identities, and validated subject groups for the tutorial menu. Read explicit categories from the tutorial catalog; do not derive groups from routes or duplicate titles/manual paths. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-navigation.rkt` | Construct semantic navigation content and attach the shared assets/collection metadata using Scribble. Expose a small root-level integration API once the insertion spike is verified. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/skia-doc-nav.css` | Scoped band, active state, menu, responsive layout, focus treatment, and print rules. Optional edge-wash rules remain independently switchable. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/skia-doc-nav.js` | Initialize the disclosure, toggle state, close behavior, and keyboard handling. No URL generation, native work, dependencies, remote assets, or inline event handlers. |
| Test submodules in the shared catalog/navigation modules, plus `/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/reader-test.rkt` | Extend existing native-free metadata and document-construction tests; reuse or extend rendering fixtures as needed. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-documentation-navigation.py` | Parse built HTML; validate header coverage, active state, menu inventory, links, local assets, and relocation. Report the checked build scope explicitly. |
| `/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-documentation-navigation.py` | Positive and negative fixtures for the new checker. |
| Rendering fixtures in the existing test suite, or a dedicated helper if needed | Native-free preview covering Reference, Tutorials, neutral landing, and a synthetic available Guide. Do not create a parallel fixture runner if existing helpers suffice. |

An automated browser smoke script may be added using the repository/environment's available browser tooling. A frontend framework, package manager, downloaded icon/font set, and new production JavaScript library are not necessary.

### Collection records

Each collection record should have a stable ID, visible label, enabled/available flag, index module path when available, expected output-directory identity, and signature-color key. The rendering call also receives a tutorial ID when applicable. Keep current-page identity separate from collection identity.

Reference targets `(lib "skia/scribblings/reference/reference.scrbl")`; Tutorials targets `(lib "skia/scribblings/tutorials/index.scrbl")`. Both use their actual `top` target through Scribble. Do not manufacture a Guide module path or public URL while it is absent. A future Guide record must supply a real module and registration before becoming enabled.

Validate duplicate IDs, missing enabled destinations, unknown tutorial IDs, explicit category coverage, and route validity at build/test time. Category coverage and route validity are separate checks. Explicitly disabled Guide metadata is valid; a supposedly enabled but missing Guide is a build error, not silently omitted navigation.

## Original Scribble integration spike (regression context)

This was the prerequisite for the original rollout. For the current follow-up, reuse the implemented integration and its fixtures; do not repeat the rollout or modify all tutorial roots simply to change grouping. Preserve the guarantees established by the spike:

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

### Explicit subject categories and catalog metadata

Extend the existing JSON catalog to schema version 2. Add an ordered top-level `categories` array. Each record contains a stable `id`, a visible `title`, and an ordered `lessons` array of tutorial IDs. Add a nonempty `menu_title` to each tutorial record for its compact shortcut label. Keep the existing canonical `title`, `goal`, `manual`, prerequisites, next steps, source files, commands, and requirements unchanged.

For example, the category record for images is:

```json
{
  "id": "images-color",
  "title": "Images and Color",
  "lessons": ["images", "pixels", "color-spaces"]
}
```

The `categories` array is the only production source of primary category assignment and ordering. Do not also add a redundant category field to tutorial entries. The existing `routes` array remains a separate source of pedagogical sequences. Export categories through the native-free catalog reader, and resolve their lesson IDs to the authoritative tutorial records in one shared helper used by both the index and menu. Audit all catalog consumers when updating the schema; missing categories must fail validation, not silently fall back to route-derived groups.

Use the following initial categories, ordering, and compact labels. The IDs in the final column identify existing tutorials; the text after each ID supplies its `menu_title`.

| Category ID | Visible category | Tutorials in order: ID — menu title |
| --- | --- | --- |
| `getting-started` | Getting Started | `quick` — Quick Introduction |
| `geometry` | Geometry | `clock` — Transforms and Coordinates; `logo` — Paths and Geometry; `path-ops` — Path Operations |
| `paints-effects` | Paints and Effects | `poster` — Paints and Gradients; `effects` — Effects and Filters; `shaders` — Runtime Shaders |
| `images-color` | Images and Color | `images` — Images; `pixels` — Working with Pixels; `color-spaces` — Color Spaces |
| `text` | Text | `text` — Text and Typography; `shaping` — Shaping and Multilingual Text; `paragraph` — Paragraph Layout |
| `recording-export` | Recording and Export | `pictures` — Record and Replay; `pdf-svg` — PDF and SVG; `vector-raster` — Vector Output and Raster Fallbacks |
| `windows-interaction` | Windows and Interaction | `gpu` — GPU Rendering; `animation` — Animation; `interaction` — Interactive Paths; `navigation` — Zoom and Pan |
| `sprites-games` | Sprites and Games | `sprites` — Sprite Atlases; `squadron` — Star Squadron |

These rows are the initial editorial assignment and acceptance expectations, not another production data source. Every one of the current 22 tutorials belongs to exactly one category. Cross-cutting subjects receive one primary home: for example, Runtime Shaders belongs with paints, PDF and SVG with export, and GPU Rendering with the window/interaction material. Routes and existing next-step links provide other ways through the same lessons.

Require unique, nonempty category IDs/titles, nonempty category lesson lists, known tutorial IDs, no duplicate assignment within or across categories, and complete coverage of the tutorial inventory. Require recognizable, nonempty menu titles and flag duplicate shortcut labels for editorial review. Never silently omit an uncategorized tutorial or create an automatic “Other” group. Adding a tutorial requires an explicit category decision; it does not require adding it to a reading route.

### Tutorial index: catalog first, routes separate

Keep the existing tutorial index manual and its output URL. Reorganize its reading content into this order:

1. **Start here.** A short introduction distinguishes browsing by subject from following a suggested route. Provide a prominent Quick Introduction link with the existing goal describing the moonlit-lake example. This is an entry-point callout, not a route or a replacement for Quick's catalog entry. Also provide simple in-page links to All tutorials, Suggested reading routes, and Running the examples.
2. **All tutorials.** Render the eight categories above, in that order, from shared metadata. Within each category list each assigned tutorial once using its canonical full title and existing one-sentence `goal`. Use ordinary links and compact lists; no new thumbnails, card framework, interactive filters, or copied prerequisite paragraphs are required. The title and goal together should explain the subject and what the reader will make or learn. Category order is for browsing, not an implied mandatory syllabus.
3. **Suggested reading routes.** Place the existing eight route headings, explanatory prose, and ordered lesson sequences here, after the complete subject catalog. Introduce them as optional learning paths; a tutorial can legitimately appear in more than one. Preserve all existing route titles, lesson order, membership, and pedagogical prose during this change. Keep routes on the same index page for this iteration; a separate route manual is not required.
4. **Running the examples.** Retain the existing instructions and their `running-examples` tag, followed by the existing API lookup section. Do not duplicate installation instructions in every category.

Make the sidebar/contents emphasize Start here, All tutorials and its subject categories, Suggested reading routes, and Running the examples. The eight routes must no longer dominate the top-level outline. Use nested route headings and the appropriate Scribble contents depth so the catalog remains easy to scan. Categories should not receive tutorial/route numbering that implies a required reading order; preserve the existing numbering behavior inside individual manuals.

Use stable explicit tags for the new catalog and category sections, such as `all-tutorials` and `tutorial-category-images-color`, and `suggested-reading-routes` for the route section. Before moving route headings, record their currently rendered anchors; preserve existing deep links with explicit tags or compatibility anchors where needed. Do not assume changing heading depth preserves Scribble-generated anchors. Keep the manual's `top` target and all existing lesson/API tags unchanged.

The once-per-tutorial rule applies to the **All tutorials block**, not the whole index: Quick intentionally also appears in Start here, and routes intentionally repeat tutorials. Keep those regions semantically distinguishable in generated HTML so checks can count the catalog without counting route or navigation links.

Update the shared next-step return sentence to “Return to Skia Tutorials to browse all tutorials or choose a suggested reading route.” Preserve each lesson's prerequisites and next-step destinations. Do not rewrite individual lesson titles merely to shorten menu labels.

### Tutorial shortcut menu

Put **All tutorials** first in the panel, linked to the tutorial index's `top` target. Follow it with the same category headings, category order, and tutorial order as the All tutorials block. Display each tutorial's `menu_title`; the index uses its canonical `title` and `goal`. Both obtain their destination from the same tutorial `manual` metadata. Do not split full titles heuristically or hard-code a second label table in the renderer.

The panel is a subject finder, not a syllabus: include no reading-route groups, prerequisite explanations, route numbering, or next-step sequences. Do not add a second route submenu. Readers reach the separate route section through the index. Mark the current tutorial using its stable ID, regardless of its label or category.

Allow titles to wrap and retain distinguishing words; do not rely on truncation or hover tooltips. Keep the existing disclosure semantics, keyboard behavior, and narrow-screen scrolling. A new grouping must not change the Tutorials label into a menu-only control.

Reordering, adding, removing, or overlapping reading routes must leave the catalog and menu unchanged. Category edits intentionally update both surfaces together. Tests must enforce this independence rather than merely checking today's output.

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

The following is original implementation guidance; the current index/menu follow-up leaves the existing edge treatment unchanged. Any future revision should be a separate change that can be omitted without affecting behavior.

Use the current collection color at low opacity in a narrow decorative strip, approximately 12–24 CSS pixels wide, fading inward to transparent. It may remain fixed while the document scrolls, but it must occupy genuinely unused viewport margin. Do not narrow the reading column merely to create room for it. Disable it when the margin is unavailable, on narrow screens, in print, and in forced-colors mode. The neutral landing page has no collection wash.

The strip must not overlap the scrollbar or content, intercept pointer events, add a focus stop, animate, tint transparent images, or alter their backgrounds. Do not apply a gradient to the document's entire background. Compare three captures—no wash, narrow wash, simple solid edge—and retain the least distracting effective treatment. If it adds little beyond the header, leave it off and record that outcome.

## Cross-document links, builds, and publication

### Preserve real document targets

Use module/tag references for links inside Scribble. Resolve them in the build rather than hard-coding public URLs or assuming every page has the same relative depth. Keep ordinary `<a href>` destinations in the final HTML so new-tab navigation, `file:` viewing, and offline browsing work.

Cover three environments explicitly: standalone editing previews, installed package documentation, and a staged static site hosted under a project subpath. An absolute site-root URL such as `/skia-reference/` would be wrong for many project deployments; a checkout `file:` URL would be wrong after publication.

Do not change existing manual directory names, tags, or API anchors. If the future Guide is enabled, add its exact known directory to the allowlists in site relocation and review packaging. Do not broaden those functions to rewrite arbitrary external links or infer undocumented API destinations.

### Preserve the complete navigation link graph

The original Reference-only preview resolved selected tutorial links rather than the complete navigation graph. Shared headers expose the index and all tutorial shortcuts, and tutorial headers link back to the Reference. Preserve complete-site evidence when changing the catalog:

1. Separate navigation destinations from API coverage and the existing curated editorial-link inventory. Do not replace that inventory with 22 invented “covered” API records.
2. Use the existing full navigation render/check workflow with the registered manuals and catalog; extend it only where the revised checks require it. Prefer the actual installed `raco setup` build for full-site acceptance. If extending the fresh renderer, generate real cross-reference information for every enabled destination, combine it, and perform final resolution before declaring success.
3. Keep fast partial previews available. Their report must list unavailable companion destinations and say that complete navigation has not been checked. Do not suppress warnings, substitute `href="#"`, fabricate targets, or silently point at a stale installed manual to make the preview appear complete.
4. Verify that the partial-preview guidance in [Reference Development](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md) distinguishes curated editorial links from complete navigation. Do not use the original “three outgoing tutorial links” inventory as evidence that all shared navigation destinations resolve.
5. Keep API binding checks and their real xref evidence intact. New header links must not accidentally satisfy checks intended for editorial links in the reading content; distinguish navigation landmarks from content links where necessary.

### Asset staging and the site root

Verify that the asset-copy step in the [Pages workflow](/Users/soegaard/Dropbox/GitHub/skia-for-racket/.github/workflows/pages.yml) still carries the shared CSS/JavaScript at the actual locations emitted by Scribble. Check the generated paths first; assets may be shared at the documentation root or copied under manuals. Do not assume one layout and test only the other.

Preserve the separately copied [landing page's](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/pages-index.html) shared navigation integration. Any generated shortcut panel must pick up the same categories and labels. If the source template retains a small static scaffold, preserve parity tests so available collections, labels, order, and targets cannot drift. No active-state label belongs on this neutral page.

Check review/source hashing and archive inputs if this follow-up introduces new dependencies or assets. Preserve existing statements about partial bundles. A complete HTML bundle must include every navigation target and both assets; a partial bundle must state its limitation. Verify extraction/relocation without relying on the original checkout.

The source-inventory workflow checks [SOURCE-SHA256SUMS.txt](/Users/soegaard/Dropbox/GitHub/skia-for-racket/SOURCE-SHA256SUMS.txt). Refresh it through [the existing generator](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/update-source-sums.py) at the appropriate final integration point. Because it includes non-ignored files and other work may be active, inspect the inventory rather than blindly incorporating unrelated transient output. Preserve manual deployment triggers and permissions; do not dispatch publication as a test.

## Validation plan

### Native-free unit and rendering tests

Retain tests for collection order with Guide disabled and enabled, enabled-but-missing Guide failure, neutral landing state, duplicate IDs, authoritative module paths, and the currently shipped Guide treatment. Assert that requiring/building the navigation component alone does not load Skia native libraries or initialize GUI/GPU state.

Add the following catalog/index/menu acceptance tests:

- The initial eight categories contain the 22 current tutorial IDs exactly once. Category membership and order match the editorial table above. Read normal expected labels and destinations from metadata; retain an explicit fixture for the approved initial assignment so an accidental regrouping cannot validate itself.
- Reject missing categories, duplicate/empty category IDs or titles, empty lesson lists, unknown lesson IDs, duplicate assignment within/across categories, missing assignments, and missing/empty `menu_title` values. Report duplicate shortcut labels for editorial review.
- Resolve index titles/goals from `title`/`goal` and menu labels from `menu_title`, using the same lesson IDs and manual destinations. The current tutorial indicator still works when a menu title is changed.
- Reorder routes, change their membership, and add overlapping routes in isolated fixtures: neither catalog nor menu grouping/order changes. A fully categorized tutorial with no route membership still appears in both. Reordering a category or moving a lesson between categories updates both surfaces identically.
- Validate routes independently: existing lesson references must be valid and sequences must remain meaningful/nonempty. Preserve the current eight routes exactly during this migration. Cross-route duplicates are valid; complete route coverage is not a publication requirement. Keep prerequisite/next-step graph validation intact.
- Verify index block order, category headings/order, title/goal rows, and preserved route sequences. Check the catalog region alone for once-per-tutorial coverage; separately allow Quick's Start here callout and repeated route links. Do not count the global navigation as index reading content.
- Verify new catalog/category anchors, preserved old route anchors, the `running-examples` target, and unchanged canonical lesson titles/manual identities. Confirm the sidebar no longer presents the eight routes as the primary top-level tutorial organization.

Render synthetic fixtures under both single-page and multipage output. Assert exactly one header on every emitted page, no duplicate HTML IDs, correct active state, valid index destinations, unchanged original tags, and locally included assets. Verify a nested section that stays on its parent's page does not acquire an extra header. Include a synthetic Guide without creating a production Guide placeholder.

The HTML checker should detect missing headers on a deep page, wrong active collection, missing/duplicate menu lessons, wrong category membership/order, incorrect labels, bad disclosure IDs, dead targets, missing assets, and stale machine-local links after relocation. On the tutorial index, additionally validate the distinct catalog and routes regions, catalog/menu parity, and one title/goal row per catalog tutorial. Include negative fixtures for each, including a page whose menu is correct but whose index catalog is incomplete. Enumerate emitted HTML and destination metadata dynamically; do not assume there are exactly 71 Reference output files.

Update the existing route-based assertions rather than adding tests alongside contradictory rules. In particular, the tutorial source checker currently requires complete route coverage and extracts literal `@tutorial-route[...]` calls from the index. Move the completeness requirement to categories. Preserve a separate check that rendered reading routes match their route metadata; if their rendering helper changes, update the extraction or rendered-output check instead of silently dropping that guarantee.

### Browser and accessibility checks

Run representative pages from each available collection, a deep Reference API anchor, the neutral landing page, and the synthetic Guide. Check desktop widths around 1440 and 1024, a narrow 320-pixel viewport, a short landscape viewport, 200% text enlargement/zoom, and 400% zoom/reflow. Record which browser/OS combinations actually ran; test at least Chromium and one additional engine when available.

Verify label navigation, modified/new-tab clicks, the separate disclosure, all close paths, forward/reverse tab order, visible focus, touch activation, long menu scrolling, and current tutorial indication. No focus may be stranded in a hidden panel. Test JavaScript disabled, script load failure, CSS disabled, forced colors, and print preview. The static links must still be meaningful without the enhancement.

On the revised index, verify that a reader can find Quick immediately, browse Images and Color or Text without interpreting a learning route, and deliberately jump to Suggested reading routes. Compare the dropdown's headings/order with the catalog. Check that the catalog and route headings remain distinguishable in the contents and screen-reader heading list, and that all eight categories and 22 shortcuts remain reachable on a short or narrow screen. Verify old route deep links as well as the new in-page links. Capture the index overview, a catalog category, the separate routes section, and the open dropdown.

Inspect at least one transparent image, a color-space comparison, a wide code block, and a conceptual diagram to ensure the new styles do not alter their backgrounds or layout. Test navigation through both an HTTP server under a non-root project path and local `file:` pages. Check console errors and failed asset requests. Use a screen reader to confirm landmark names, current-location announcements, disclosure state, and list/group reading order; automated accessibility checks alone do not establish that result.

### Full build and relocation acceptance

- Run the existing Reference source, binding, and installed-link checks plus the new navigation checks. Do not weaken old checks to accommodate the header.
- Build all registered manuals. Current tutorial evaluation may require native CPU dependencies; that is separate from the navigation component's native-free requirement. Record any existing unrelated failure separately.
- Stage the same assets/manuals as Pages without deploying, apply the existing relocation step, and rerun the new checker on the staged tree.
- Crawl every internal header/menu link, tutorial catalog/route link, new or preserved index anchor, and local CSS/script reference from every generated page. All must remain inside the intended staged documentation set and exist. Preserve legitimate external Racket documentation links.
- Move or copy the staged result to a second temporary location and test again, including `file:` browsing. Full-site output must contain no checkout paths, stale installation paths, or Skia-local redirect dependencies that the existing staging policy should have relocated.
- Confirm stable API anchors and existing sidebar/search/previous/next behavior. Record screenshots and a machine-readable report with pages checked, available collections, tutorial count, environment, missing destinations/assets, and whether a complete site was checked.

## Work sequence and handoff checkpoints

This is the implementation sequence for the current index/menu follow-up, not a second rollout of the navigation foundation.

### Files to change

| Existing file | Required revision |
| --- | --- |
| [Catalog JSON](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.json) | Add schema-2 categories and all 22 menu titles. Preserve existing tutorial metadata and all eight routes. |
| [Catalog reader](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/catalog.rkt) | Export and validate categories independently of routes; provide or support shared ordered category-to-tutorial resolution. Keep imports native-free. |
| [Shared documentation catalog](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-catalog.rkt) | Replace the route traversal and `seen`/first-occurrence logic in `tutorial-shortcut-groups` with explicit category resolution. Replace route-coverage/group-title expectations in validation and tests. |
| [Shared navigation renderer](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-navigation.rkt) | Render category headings and `menu_title` labels. Preserve real cross-manual links, stable lesson identity, active state, and the existing disclosure markup. |
| [Tutorial index](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/index.scrbl) | Add Start here and the metadata-driven subject catalog; move unchanged routes under Suggested reading routes; preserve practical instructions and old anchors. Adjust heading/contents hierarchy. |
| [Reader helpers](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/support/reader.rkt) and [reader tests](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/reader-test.rkt) | Add native-free catalog rendering helpers as needed and update the return-to-index sentence. Keep route rendering separate from category rendering; preserve source, prerequisite, and next-step behavior. |
| [Tutorial source checker](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/check-3b.py) and [its tests](/Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/test-check-3b.py) | Validate category coverage and independent route integrity; update route extraction if necessary without weakening title, source, command, prerequisite, or next-step checks. |
| [Navigation HTML checker](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/check-documentation-navigation.py) and [its tests](/Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-documentation-navigation.py) | Replace route-derived expected shortcuts; check category/order/label parity, catalog coverage, and separately preserved routes. Include schema-2 fixtures and negative cases. |

Make only small scoped CSS adjustments if the index heading/list layout requires them. No production JavaScript changes should be needed merely to change grouping. Audit other catalog consumers and packaging inputs for compatibility, but do not change lesson programs, manual registrations, URLs, collection colors, Guide behavior, or deployment policy.

### Implementation order

| Phase | Work | Exit criterion |
| --- | --- | --- |
| 1 Baseline | Refresh overlapping work; inspect existing shared components/checkers; record index route anchors, route data, and current screenshots; run focused tests. | The 22 tutorials, eight routes, existing deep links, and any unrelated failures are recorded. |
| 2 Explicit metadata | Add categories/menu titles, update catalog consumers and validation, and replace first-occurrence grouping. Add route-independence tests. | All 22 tutorials resolve exactly once through the approved categories. Route changes cannot affect category output. Missing/invalid assignments fail clearly. |
| 3 Catalog-first index | Add Start here and All tutorials using shared groups; move the unchanged routes below them; preserve anchors and running instructions; update return-link prose. | Generated index has the specified block order and sidebar hierarchy, complete catalog coverage, unchanged routes, and working old/new anchors. |
| 4 Matching shortcuts | Render the same category order/membership in the dropdown with compact labels; preserve All tutorials first and current-tutorial state. | Index/menu parity and ordinary label/disclosure behavior pass, including long labels and narrow screens. |
| 5 Validation migration | Update both Python checkers and their fixtures; add category/route-region checks and negative cases; retain all unrelated guarantees. | No route-derived grouping or complete-route-coverage requirement remains. Correct duplicates in routes/callouts do not trigger catalog duplicate failures. |
| 6 Full build and browser review | Build all manuals and stage/relocate without deployment; crawl navigation, catalog, routes, and assets; run responsive/accessibility regression checks. | Complete-site link checks pass; screenshots show the subject catalog and separate routes clearly; partial evidence is explicitly labeled. |
| 7 Handoff | Record focused diffs, tests, screenshots, limitations, and maintenance instructions; refresh source inventory at the final integration point. | The definition of done below is met and no deployment or unrelated documentation redesign occurred. |

Suggested commits: category schema/helpers/tests; catalog-first index and matching menu; checker/build evidence and maintenance notes. Keep each commit internally consistent by updating affected fixtures with its implementation. Avoid combining this with ongoing conceptual-figure edits or API repairs. Continue using the existing shared component rather than copying navigation markup.

## Commands and build notes

The available local Racket at inspection time is `/Applications/Racket v9.3.0.2/bin/racket`. Use the equivalent configured runtime elsewhere. Existing focused commands, run from the repository root, include:

```sh
SKIA_DOC_RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$SKIA_DOC_RACKET" -l raco -- test \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/reference-render.rkt \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-catalog.rkt \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/support/documentation-navigation.rkt \
  /Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/reader-test.rkt
python3 -B /Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-reference.py
python3 -B /Users/soegaard/Dropbox/GitHub/skia-for-racket/tools/test-documentation-navigation.py
python3 -B /Users/soegaard/Dropbox/GitHub/skia-for-racket/scribblings/tutorials/test-check-3b.py
```

These are commands for the implementation handoff, not claims that the follow-up is implemented or tested. Run the tutorial source checker and the navigation HTML checker against the appropriate actual build as well; unit fixtures alone do not prove the full site. The navigation checker currently takes the site directory as a positional argument and supports `--output` for its report. Record the exact build paths and commands used, and include any additional fixture entry points introduced during implementation.

Use fresh validation/output directories outside the checkout, as required by the existing Reference checker. The installed-build and site-check recipes are in [Reference Development](/Users/soegaard/Dropbox/GitHub/skia-for-racket/docs/REFERENCE-DEVELOPMENT.md:1692) and the Pages workflow. A full `raco setup` can write installed documentation state; use an isolated package/user-home environment for reproducible staging tests and preserve the user's existing installation.

## Definition of done

This follow-up is ready when:

- The tutorial index presents Start here, All tutorials, Suggested reading routes, and Running the examples in that order, with API lookup retained afterward.
- All 22 current tutorials appear exactly once in the catalog and exactly once in the dropdown, under the eight explicit categories above. Category headings, membership, order, and destinations agree; full index titles/goals and compact menu labels come from shared tutorial metadata.
- The eight existing reading routes remain intact in their own later section. They may reuse tutorials, and changing routes cannot change catalog/menu structure. A future categorized tutorial need not belong to a route to be discoverable.
- Existing manual URLs, canonical lesson titles, prerequisites, next-step destinations, running-example links, and old route/API anchors remain valid. New index/category anchors also work after relocation.
- The shared band, current-tutorial state, Guide treatment, disclosure behavior, keyboard/touch access, no-script fallback, narrow-screen layout, and print behavior do not regress. The index remains usable without JavaScript.
- Updated source/rendered-output checks pass on installed and relocated complete-site output. Uncompleted environmental checks must be reported as open acceptance items, not claimed as passes or used to declare full completion. No deployment is performed.

Include a short maintenance note: add a tutorial record and menu title, assign it to exactly one explicit category, and optionally place it in reading routes; category ordering controls both browsing surfaces, while route edits only change suggested reading. Document how to run the checks and which browser/accessibility checks actually completed. Preserve the existing Guide integration note and optional gradient treatment; neither is redesigned by this follow-up.
