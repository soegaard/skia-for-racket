#lang scribble/manual

@title[#:tag "skia-reference-text-fonts" #:style 'toc]{Text and Fonts}

@(require (for-label skia))

Choose a text interface according to how much preparation the text needs:

@itemlist[
 @item{Use @racket[draw-simple-text] when direct character-to-glyph mapping is
       sufficient. It does not apply contextual letter forms, ligatures, kerning,
       or font fallback.}
 @item{Use @racket[draw-shaped-text] for text that needs @tech{shaping} with one
       font. To inspect or reuse the positioned glyphs, call @racket[shape-text]
       and @racket[draw-shaped-run] separately.}
 @item{Use @racket[layout-text] for wrapping and alignment with one font, or
       @racket[layout-mixed-text] for paragraphs that also need mixed-direction
       ordering and @tech{font fallback}.}
 @item{Use a @tech{text blob} to store glyph placement for repeated drawing,
       possibly with different paints or canvas transforms. A blob captures the
       font settings it needs; it does not wrap or reshape text when drawn.}]

All of these interfaces use @tech{fonts}. A font combines a @tech{typeface}'s
glyph designs with a size and rendering settings. @tech{Font managers} help
select typefaces from the available fonts; load a font file when a particular
design is required independently of the machine's installed families.

@local-table-of-contents[]

@include-section["typefaces.scrbl"]
@include-section["fonts.scrbl"]
@include-section["shaping.scrbl"]
@include-section["text-blobs.scrbl"]
@include-section["text-layout.scrbl"]
