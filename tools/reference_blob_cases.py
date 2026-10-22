"""Independent R3b call shapes transcribed from pinned public implementations.

These are regression expectations, not a captured or replacement API inventory.
The normal coverage checker still requires the full hash-pinned snapshots.
"""
BLOB_EXPORTS = '''
text-blob-builder? make-text-blob-builder text-blob-builder-run-count
text-blob-builder-add-run! text-blob-builder-add-horizontal-run!
text-blob-builder-add-positioned-run! text-blob-builder-add-transformed-run!
text-blob-builder-add-shaped-run! text-blob-builder-finish!
text-blob-run-count text-blob-runs text-blob-run-font text-blob-intercepts
text-run-info? text-run-info-positioning text-run-info-glyphs
text-run-info-positions text-run-info-transforms text-run-info-utf8 text-run-info-clusters
positioned-glyphs->path shaped-run->text-blob/on-path draw-shaped-run/on-path
'''.split()
ATLAS_EXPORTS = 'atlas-transform? make-atlas-transform atlas-transform-coefficients'.split()

BLOB_PROCEDURES = {
    'make-text-blob-builder': (1, []),
    **{name: (2, []) for name in '''
      text-blob-builder? text-blob-builder-run-count text-blob-builder-finish!
      text-blob-run-count text-blob-runs text-run-info? text-run-info-positioning
      text-run-info-glyphs text-run-info-positions text-run-info-transforms
      text-run-info-utf8 text-run-info-clusters atlas-transform? atlas-transform-coefficients
      '''.split()},
    'text-blob-builder-add-run!': (8, ['clusters', 'origin', 'text']),
    'text-blob-builder-add-horizontal-run!': (16, ['clusters', 'text', 'y']),
    'text-blob-builder-add-positioned-run!': (16, ['clusters', 'text']),
    'text-blob-builder-add-transformed-run!': (16, ['clusters', 'text']),
    'text-blob-builder-add-shaped-run!': (4, ['origin']),
    'text-blob-run-font': (4, []),
    'text-blob-intercepts': (8, ['paint']),
    'positioned-glyphs->path': (8, ['missing-outline']),
    'shaped-run->text-blob/on-path':
        (4, ['contour', 'force-closed?', 'normal-offset', 'start-offset']),
    'draw-shaped-run/on-path':
        (16, ['contour', 'force-closed?', 'normal-offset', 'start-offset']),
    'make-atlas-transform': (4, ['anchor', 'rotation', 'scale']),
}
assert len(BLOB_EXPORTS) == 23 and len(ATLAS_EXPORTS) == 3
assert set(BLOB_EXPORTS + ATLAS_EXPORTS) == BLOB_PROCEDURES.keys()
