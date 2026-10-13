"""Independent R3a call-shape fixtures, not a captured public API inventory.

These expectations were transcribed from the reviewed public wrappers and core
implementation. The production checker still requires the hash-pinned full snapshots.
"""

TYPEFACE_EXPORTS = '''
typeface-from-bytes font-manager-typeface-from-bytes
font-style? make-font-style font-style-weight font-style-width font-style-slant
font-style-entry? font-style-entry-index font-style-entry-name font-style-entry-style
font-style-set? make-empty-font-style-set font-manager-style-set font-manager-style-set-ref
font-style-set-count font-style-set-ref font-style-set-styles
font-style-set-typeface font-style-set-match typeface-style
typeface-postscript-name typeface-fixed-pitch? typeface-glyph-count typeface-units-per-em
font-table-tag font-table-tag->bytes typeface-table-tags typeface-table-size typeface-table-bytes
typeface-kerning-pair-adjustments typeface->font-bytes
'''.split()
FONT_EXPORTS = '''
font-embedded-bitmaps? font-set-embedded-bitmaps!
font-force-auto-hinting? font-set-force-auto-hinting!
font-baseline-snap? font-set-baseline-snap!
font-typeface font-set-typeface!
font-glyph-widths font-glyph-bounds font-glyph-widths+bounds
font-glyph-positions font-glyph-x-positions font-glyph-paths font-break-text
'''.split()
TEXT_PROCEDURES = {}


def fixed(names, count):
    for name in names.split():
        assert name not in TEXT_PROCEDURES, name
        TEXT_PROCEDURES[name] = (1 << count, [])


fixed('make-font-manager default-font-manager make-typeface make-empty-font-style-set', 0)
fixed('''font-manager? font-manager-family-count font-manager-families
 typeface? typeface-family-name typeface-weight typeface-width typeface-slant
 font-style? font-style-weight font-style-width font-style-slant
 font-style-entry? font-style-entry-index font-style-entry-name font-style-entry-style
 font-style-set? font-style-set-count font-style-set-styles typeface-style
 typeface-postscript-name typeface-fixed-pitch? typeface-glyph-count typeface-units-per-em
 font-table-tag font-table-tag->bytes typeface-table-tags typeface->font-bytes
 font? font-size font-scale-x font-skew-x font-edging font-hinting
 font-subpixel? font-linear-metrics? font-embolden? font-get-metrics font-metrics?
 font-embedded-bitmaps? font-force-auto-hinting? font-baseline-snap? font-typeface
 shaper? make-shaper shaped-run? shaped-run-glyphs shaped-run-clusters shaped-run-positions
 shaped-run-advance-x shaped-run-advance-y shaped-run-glyph-count
 text-blob? text-blob-bounds text-blob-unique-id text-blob->path
 layout-break-opportunity? layout-break-opportunity-index layout-break-opportunity-insert
 text-layout? text-layout-lines text-layout-width text-layout-height text-layout-line-height
 text-layout-line-count text-layout-line? text-layout-line-text text-layout-line-run
 text-layout-line-origin-x text-layout-line-baseline text-layout-line-width text-layout-line-direction
 mixed-text-layout? mixed-text-layout-lines mixed-text-layout-width mixed-text-layout-height
 mixed-text-layout-line-height mixed-text-layout-line-count
 mixed-text-line? mixed-text-line-text mixed-text-line-runs mixed-text-line-origin-x
 mixed-text-line-baseline mixed-text-line-width mixed-text-line-direction
 mixed-text-run? mixed-text-run-text mixed-text-run-shaped-run mixed-text-run-origin-x
 mixed-text-run-width mixed-text-run-direction mixed-text-run-level mixed-text-run-script
 mixed-text-run-family''', 1)
fixed(' '.join('font-metrics-' + suffix for suffix in (
    'top ascent descent bottom leading average-character-width max-character-width '
    'x-min x-max x-height cap-height underline-thickness underline-position '
    'strikeout-thickness strikeout-position spacing').split()), 1)
fixed('''font-manager-family-name font-manager-style-set font-manager-style-set-ref
 font-style-set-ref font-style-set-typeface typeface-table-size typeface-kerning-pair-adjustments
 font-set-size! font-set-scale-x! font-set-skew-x! font-set-edging! font-set-hinting!
 font-set-subpixel! font-set-linear-metrics! font-set-embolden!
 font-set-embedded-bitmaps! font-set-force-auto-hinting! font-set-baseline-snap!
 font-set-typeface! font-char->glyph font-text->glyphs font-glyph-path font-glyph-paths
 shaped-run->text-blob shaped-run->path''', 2)
fixed('make-positioned-text-blob', 3)
fixed('draw-text-blob draw-text-layout draw-mixed-text-layout', 5)
fixed('draw-simple-text draw-shaped-run', 6)

STYLE = ['slant', 'weight', 'width']
SHAPE = ['direction', 'features', 'language', 'script']
LAYOUT = ['align', 'break-provider', 'direction', 'features', 'language', 'line-height', 'width']
TEXT_PROCEDURES.update({
    'make-font-style': (1, STYLE),
    'font-manager-match-family': (4, STYLE),
    'typeface-from-family': (2, STYLE),
    'font-manager-match-character': (4, sorted([*STYLE, 'family', 'languages'])),
    'typeface-from-file': (2, ['index']),
    'typeface-from-bytes': (2, ['index']),
    'font-manager-typeface-from-bytes': (4, ['index']),
    'font-style-set-match': (6, []),
    'typeface-table-bytes': (4, ['end', 'start']),
    'make-font': (3, ['baseline-snap?', 'edging', 'embedded-bitmaps?', 'embolden?',
                     'force-auto-hinting?', 'hinting', 'linear-metrics?', 'scale-x',
                     'size', 'skew-x', 'subpixel?']),
    'measure-simple-text': (4, ['paint']),
    'simple-text-bounds': (4, ['paint']),
    'simple-text-path': (28, []),
    'font-glyph-widths': (4, ['paint']),
    'font-glyph-bounds': (4, ['paint']),
    'font-glyph-widths+bounds': (4, ['paint']),
    'font-glyph-positions': (4, ['origin']),
    'font-glyph-x-positions': (4, ['origin']),
    'font-break-text': (8, ['paint']),
    'shape-text': (4, SHAPE),
    'draw-shaped-text': (64, SHAPE),
    'layout-text': (4, sorted([*LAYOUT, 'script'])),
    'layout-mixed-text': (8, LAYOUT),
    'make-layout-break-opportunity': (6, []),
})
assert len(TEXT_PROCEDURES) == 169
assert len(TYPEFACE_EXPORTS) == 32 and len(FONT_EXPORTS) == 15
assert set(TYPEFACE_EXPORTS + FONT_EXPORTS) <= TEXT_PROCEDURES.keys()
