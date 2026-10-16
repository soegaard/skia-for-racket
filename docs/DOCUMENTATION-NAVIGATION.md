# Documentation navigation

The shared navigation band is rendered by
`scribblings/support/documentation-navigation.rkt`. It is intentionally
native-free and takes its collection metadata from
`scribblings/support/documentation-catalog.rkt` and tutorial labels/routes from
the existing tutorial catalog. JavaScript only operates the Tutorials shortcut
disclosure; the collection links and lesson links are present in the HTML before
the script runs.

The current visible order is **Reference, Tutorials**. `Guide` remains a
disabled, reserved catalog record and is deliberately not rendered while no
registered Guide manual exists. To enable it, give the record a real module
path and output-directory identity, register that exact manual in `info.rkt`,
and let `validate-documentation-collections!` reject incomplete metadata.
The Guide will then occupy the middle position automatically.

Tutorial shortcuts are grouped from the tutorial index routes. Repeated route
prerequisites occur once, in their first route, and an uncategorized lesson is
a build error. The neutral Pages landing is generated from the same metadata by
`tools/render-documentation-landing.rkt`, using
`scribblings/tutorials/pages-index.html` only as its page scaffold.

For complete-site evidence, build all installed manuals, stage the Pages tree,
then run `tools/check-documentation-navigation.py` against that staged root.
It checks every Reference page, the landing page, the Tutorials index, every
tutorial, all shortcut targets, active state, and local CSS/JavaScript assets.
Reference-only previews remain useful, but report their unavailable navigation
destinations and are not complete-site navigation evidence.
