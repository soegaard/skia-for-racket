"""Independent R3d call shapes, transcribed from the pinned public implementations.

These are regression expectations, not a replacement API inventory. The ordinary
checker continues to require the original hash-pinned repository JSON files.
"""
COLOR_SPACE_EXPORTS = '''
transfer-function? make-transfer-function transfer-function-coefficients
named-transfer-function transfer-function-evaluate transfer-function-invert
named-xyz-d50 primaries->xyz-d50 make-rgb-color-space
color-space-transfer-function color-space-xyz-d50 xyz-d50-concat xyz-d50-invert
'''.split()
COLOR4F_EXPORTS = '''
color4f? make-color4f color4f-red color4f-green color4f-blue color4f-alpha
color4f->vector color->color4f color4f->rgba
'''.split()
FLOAT_COLOR_EXPORTS = '''
make-paint/color4f paint-color4f paint-set-color4f! canvas-clear-color4f! draw-color4f
make-color4f-shader make-linear-gradient-color4f-shader make-radial-gradient-color4f-shader
make-sweep-gradient-color4f-shader make-two-point-conical-gradient-color4f-shader
'''.split()
DESCRIPTOR_EXPORTS = ['color-space-descriptor?']
COLOR_PROCEDURES = {}
for names, arity in (
    ('transfer-function? transfer-function-coefficients named-transfer-function '
     'transfer-function-invert named-xyz-d50 color-space-transfer-function '
     'color-space-xyz-d50 xyz-d50-invert color-space-gamma-close-to-srgb? '
     'color-space->linear-gamma color-space->srgb-gamma color-space-from-icc-bytes '
     'color-space->icc-bytes color-space-descriptor? color4f? color4f-red color4f-green '
     'color4f-blue color4f-alpha color4f->vector color->color4f paint-color4f', 2),
    ('transfer-function-evaluate make-rgb-color-space xyz-d50-concat canvas-clear-color4f!', 4),
    ('primaries->xyz-d50', 16), ('make-transfer-function', 128), ('make-color4f', 24),
):
    COLOR_PROCEDURES.update({name: (arity, []) for name in names.split()})
COLOR_PROCEDURES.update({
    'color4f->rgba': (2, ['out-of-range']),
    'image-convert-color-space': (4, ['source-color-space']),
    'make-paint/color4f': (2, ['antialias?', 'color-space', 'stroke-width', 'style']),
    'paint-set-color4f!': (4, ['color-space']),
    'draw-color4f': (4, ['blend-mode']),
    'make-color4f-shader': (2, ['color-space']),
    'make-linear-gradient-color4f-shader': (32, ['color-space', 'matrix', 'positions', 'tile-mode']),
    'make-radial-gradient-color4f-shader': (16, ['color-space', 'matrix', 'positions', 'tile-mode']),
    'make-sweep-gradient-color4f-shader':
        (8, ['color-space', 'end-angle', 'matrix', 'start-angle', 'positions', 'tile-mode']),
    'make-two-point-conical-gradient-color4f-shader':
        (128, ['color-space', 'matrix', 'positions', 'tile-mode']),
})
COLOR_REQUIRED_KEYWORDS = {
    name: ['color-space'] for name, (_, keywords) in COLOR_PROCEDURES.items()
    if 'color-space' in keywords
}
assert len(COLOR_SPACE_EXPORTS) == 13
assert len(COLOR4F_EXPORTS) == 9
assert len(FLOAT_COLOR_EXPORTS) == 10
assert len(COLOR_PROCEDURES) == 39
assert len(COLOR_REQUIRED_KEYWORDS) == 7
