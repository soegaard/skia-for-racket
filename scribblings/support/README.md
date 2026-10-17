# Shared Documentation Navigation

These files implement the collection band shared by the Reference and
Tutorials, with metadata for the future Guide. Scribble creates real document
links; browser code enhances the tutorial disclosure rather than defining routes.

- [documentation-catalog.rkt](documentation-catalog.rkt) defines collection
  identities, enabled destinations, and subject-based tutorial shortcuts.
- [documentation-navigation.rkt](documentation-navigation.rkt) builds the band
  and adds it to separately rendered Reference pages.
- [skia-doc-nav.css](skia-doc-nav.css) styles collection colors, responsive
  layout, focus treatment, and the tutorial disclosure.
- [skia-doc-nav.js](skia-doc-nav.js) provides disclosure interactions and
  keyboard/focus behavior for the existing markup.

Tutorial titles, categories, and separate reading routes remain authoritative in
[the tutorial catalog](../tutorials/support/catalog.json). Collection destinations
must agree with [manual registration](../../info.rkt).
