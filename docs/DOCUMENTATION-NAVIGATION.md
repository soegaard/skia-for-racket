# Documentation navigation

The shared navigation band is rendered by
`scribblings/support/documentation-navigation.rkt`. It is intentionally
native-free and takes its collection metadata from
`scribblings/support/documentation-catalog.rkt` and tutorial labels, subject
categories, and routes from the tutorial catalog. JavaScript only operates the
Tutorials shortcut disclosure; the collection links and lesson links are present
in the HTML before the script runs.

The current visible order is **Reference, Guide, Tutorials**. Each collection
has a registered manual and a real destination; the Guide occupies the middle
position automatically from the collection catalog.

Tutorial shortcuts are grouped by the catalog's explicit subject categories,
not by reading routes. Every lesson belongs to exactly one category; routes may
overlap and may omit lessons. The Tutorials index uses the same categories for
its full-title-and-goal catalog, while the shortcut disclosure uses each
lesson's compact `menu_title`. The neutral Pages landing is generated from the
same metadata by `tools/render-documentation-landing.rkt`, using
`scribblings/tutorials/pages-index.html` only as its page scaffold.

For complete-site evidence, build all installed manuals, stage the Pages tree,
then run `tools/check-documentation-navigation.py` against that staged root.
It checks every Reference, Guide, and tutorial page, all shortcut targets,
active state, and local CSS/JavaScript assets. Each manual page must also have
exactly one GitHub paragraph-feedback configuration and both feedback assets.
Reference-only previews remain useful, but report their unavailable navigation
destinations and are not complete-site navigation evidence.

Paragraph feedback is configured by `scribblings/support/paragraph-feedback.rkt`.
Its scripts and stylesheets propagate through a Scribble manual, but its
`head-extra` metadata does not. The Reference page decorator therefore applies
the shared feedback style to every separately rendered chapter, section, and
index. Guide and tutorial titles apply the same style to their single-page manuals.

Run `raco test scribblings/support/documentation-navigation.rkt` for a rendered
multipage regression check and `python3 -B tools/test-documentation-navigation.py`
for the site-checker regressions. Documentation review bundles include the feedback
module, browser assets, and checker tests with their current source fingerprints.
