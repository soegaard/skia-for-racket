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
It checks every Reference page, the Guide and Tutorials indexes, every
tutorial, all shortcut targets, active state, and local CSS/JavaScript assets.
Reference-only previews remain useful, but report their unavailable navigation
destinations and are not complete-site navigation evidence.
