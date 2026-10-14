"""Independent R3e call shapes, transcribed from the pinned implementation.

These expectations are synthetic regression inputs, not live reflection and not
substitutes for the two hash-pinned API snapshots required by the ordinary checker.
"""
PICTURE_EXPORTS = '''
picture->bytes picture-from-bytes picture-from-file save-picture
picture-cull-bounds picture-unique-id picture-approximate-op-count
picture-approximate-bytes-used make-picture-shader
'''.split()
OUTPUT_EXPORTS = '''
unit->points output-page? make-output-page output-page-width output-page-height
output-page-unit output-page-margins output-page-background output-page-clip?
output-page-size-in-points output-page-content-size draw-output-page
output-page->image output->bytes save-output
'''.split()
ANNOTATION_EXPORTS = '''
canvas-annotation-backend canvas-annotate-url! canvas-define-destination!
canvas-link-destination! destination-id svg-destination-id
'''.split()
OUTPUT_PARAMETERS = ['current-text-output-mode', 'current-raster-output-scale']
OUTPUT_SYNTAX = ['with-document-page']
PDF_OPTIONS = sorted('''
title author subject keywords creator producer creation-date modified-date
raster-dpi encoding-quality pdfa?
'''.split())
SVG_OPTIONS = ['description', 'id-prefix', 'title']
PAGE_OPTIONS = sorted('''
title description text-mode raster-dpi id-prefix encoding-quality pdfa?
'''.split())
OUTPUT_PROCEDURES = {}
for names, arity in (
    ('picture? picture-width picture-height picture-recorder? picture-recorder-recording? '
     'picture-recorder-finish-recording! picture-cull-bounds picture-unique-id '
     'picture-approximate-bytes-used picture->bytes document? document-state document-page-count '
     'document-end-page! document-finish! document-abort! document->pdf-bytes '
     'svg-document? svg-document-width svg-document-height svg-document-state '
     'svg-document-canvas svg-document-finish! svg-document-abort! svg-document->bytes '
     'svg-document->string output-page? output-page-width output-page-height output-page-unit '
     'output-page-margins output-page-background output-page-clip? output-page-size-in-points '
     'output-page-content-size canvas-annotation-backend destination-id', 2),
    ('make-picture-recorder', 1), ('document-begin-page!', 8),
    ('call-with-document-page canvas-define-destination!', 16),
    ('canvas-annotate-url! canvas-link-destination!', 64), ('unit->points', 6),
):
    OUTPUT_PROCEDURES.update({name: (arity, []) for name in names.split()})
OUTPUT_PROCEDURES.update({
    'picture-recorder-begin-recording!': (32, ['spatial-index']),
    'call-with-picture': (8, ['spatial-index']),
    'draw-picture': (4, ['height', 'width', 'x', 'y']),
    'picture->image': (8, ['background']),
    'picture-approximate-op-count': (2, ['nested?']),
    'picture-from-bytes': (2, ['height', 'trusted?', 'width']),
    'picture-from-file': (2, ['height', 'trusted?', 'width']),
    'save-picture': (4, ['exists']),
    'make-picture-shader': (2, ['local-matrix', 'sampling', 'tile-rect', 'tile-x', 'tile-y']),
    'make-picture-image-filter': (2, ['crop', 'target']),
    'make-pdf-document': (1, PDF_OPTIONS),
    'save-pdf': (4, ['exists']),
    'call-with-pdf-bytes': (2, PDF_OPTIONS),
    'call-with-pdf-file': (4, sorted([*PDF_OPTIONS, 'exists'])),
    'make-svg-document': (4, SVG_OPTIONS),
    'save-svg': (4, ['exists']),
    'call-with-svg-bytes': (8, SVG_OPTIONS),
    'call-with-svg-string': (8, SVG_OPTIONS),
    'call-with-svg-file': (16, sorted([*SVG_OPTIONS, 'exists'])),
    'make-output-page': (8, ['background', 'clip?', 'margins', 'unit']),
    'draw-output-page': (4, ['raster-dpi', 'text-mode']),
    'output-page->image': (2, ['color-space', 'dpi', 'text-mode']),
    'output->bytes': (4, PAGE_OPTIONS),
    'save-output': (8, sorted([*PAGE_OPTIONS, 'exists'])),
    'draw-rasterized': (64, ['color-space', 'padding', 'scale']),
    'svg-destination-id': (2, ['id-prefix']),
})
