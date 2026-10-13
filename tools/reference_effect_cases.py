"""Independent R3c call shapes transcribed from the pinned implementations.

These are test expectations, not captured API inventories. Full source validation
still requires the hash-pinned repository snapshots.
"""
EFFECT_EXPORTS = '''
make-1d-path-effect make-2d-line-path-effect make-2d-path-effect
make-table-mask-filter make-gamma-mask-filter make-clip-mask-filter make-shader-mask-filter
make-fractal-noise-shader make-turbulence-shader make-empty-shader shader-with-color-filter
make-blender-shader make-arithmetic-blender make-blender-image-filter
'''.split()
COLOR_FILTER_EXPORTS = '''
make-hsla-matrix-filter make-linear-to-srgb-gamma-color-filter
make-srgb-to-linear-gamma-color-filter make-lerp-color-filter make-luma-color-filter
make-high-contrast-color-filter make-table-color-filter make-table-argb-color-filter
make-lighting-color-filter
'''.split()
RUNTIME_EXPORTS = '''
runtime-effect? make-runtime-effect runtime-effect-kind runtime-effect-source
runtime-effect-uniform-byte-size runtime-effect-uniforms runtime-effect-children
runtime-effect-uniform-bytes runtime-effect->shader runtime-effect->color-filter
runtime-effect->blender runtime-uniform? runtime-uniform-name runtime-uniform-offset
runtime-uniform-type runtime-uniform-count runtime-uniform-byte-size runtime-uniform-array?
runtime-uniform-color? runtime-uniform-half-precision? runtime-child? runtime-child-name
runtime-child-kind runtime-child-index exn:fail:skia-sksl? exn:fail:skia-sksl-kind
exn:fail:skia-sksl-source exn:fail:skia-sksl-diagnostics blender? make-blend-mode-blender
paint-blender paint-set-blender!
'''.split()
EFFECT_PROCEDURES = {}
for names, arity in (
    ('make-dash-path-effect', 6), ('make-corner-path-effect', 2),
    ('make-discrete-path-effect', 12),
    ('make-compose-path-effect make-sum-path-effect make-2d-line-path-effect '
     'make-2d-path-effect', 4),
    ('make-table-mask-filter make-gamma-mask-filter make-shader-mask-filter', 2),
    ('make-clip-mask-filter', 4),
    ('make-color-matrix-filter make-hsla-matrix-filter make-table-color-filter', 2),
    ('make-blend-color-filter make-compose-color-filter make-lighting-color-filter', 4),
    ('make-lerp-color-filter', 8),
    ('make-linear-to-srgb-gamma-color-filter make-srgb-to-linear-gamma-color-filter '
     'make-luma-color-filter make-empty-shader', 1),
    ('shader-with-color-filter', 4), ('make-blender-shader', 8),
    ('runtime-effect? runtime-effect-kind runtime-effect-source '
     'runtime-effect-uniform-byte-size runtime-effect-uniforms runtime-effect-children '
     'runtime-uniform? runtime-uniform-name runtime-uniform-offset runtime-uniform-type '
     'runtime-uniform-count runtime-uniform-byte-size runtime-uniform-array? '
     'runtime-uniform-color? runtime-uniform-half-precision? runtime-child? '
     'runtime-child-name runtime-child-kind runtime-child-index exn:fail:skia-sksl? '
     'exn:fail:skia-sksl-kind exn:fail:skia-sksl-source exn:fail:skia-sksl-diagnostics '
     'blender? make-blend-mode-blender paint-blender', 2),
    ('runtime-effect-uniform-bytes paint-set-blender!', 4),
):
    EFFECT_PROCEDURES.update({name: (arity, []) for name in names.split()})
EFFECT_PROCEDURES.update({
    'make-trim-path-effect': (4, ['mode']),
    'make-1d-path-effect': (12, ['style']),
    'make-blur-mask-filter': (2, ['respect-ctm?', 'style']),
    'make-fractal-noise-shader': (24, ['tile-size']),
    'make-turbulence-shader': (24, ['tile-size']),
    'make-high-contrast-color-filter': (1, ['contrast', 'grayscale?', 'invert-style']),
    'make-table-argb-color-filter': (1, ['alpha', 'blue', 'green', 'red']),
    'make-blur-image-filter': (4, ['crop', 'input', 'tile-mode']),
    'make-drop-shadow-image-filter': (32, ['crop', 'input']),
    'make-drop-shadow-only-image-filter': (32, ['crop', 'input']),
    'make-color-filter-image-filter': (2, ['crop', 'input']),
    'make-compose-image-filter': (4, ['crop']),
    'make-crop-image-filter': (2, ['input']),
    'make-offset-image-filter': (4, ['crop', 'input']),
    'make-merge-image-filter': (2, ['crop']),
    'make-blend-image-filter': (8, ['crop']),
    'make-arithmetic-image-filter': (64, ['crop', 'enforce-premul?']),
    'make-dilate-image-filter': (4, ['crop', 'input']),
    'make-erode-image-filter': (4, ['crop', 'input']),
    'make-displacement-map-image-filter': (32, ['crop']),
    'make-matrix-convolution-image-filter':
        (8, ['bias', 'convolve-alpha?', 'crop', 'gain', 'input', 'offset', 'tile-mode']),
    'make-matrix-transform-image-filter': (2, ['crop', 'input', 'sampling']),
    'make-image-source-filter': (2, ['crop', 'destination', 'sampling', 'source']),
    'make-shader-image-filter': (2, ['crop', 'dither?']),
    'make-tile-image-filter': (4, ['crop', 'input']),
    'make-magnifier-image-filter': (4, ['crop', 'input', 'inset', 'sampling']),
    'make-arithmetic-blender': (16, ['enforce-premul?']),
    'make-blender-image-filter': (8, ['crop']),
    'make-runtime-effect': (2, ['kind']),
    'runtime-effect->shader': (2, ['children', 'local-matrix', 'uniforms']),
    'runtime-effect->color-filter': (2, ['children', 'uniforms']),
    'runtime-effect->blender': (2, ['children', 'uniforms']),
})
for model in ('diffuse', 'specular'):
    for lamp in ('distant', 'point', 'spot'):
        keywords = ['coefficient', 'crop', 'input', 'surface-scale']
        if model == 'specular':
            keywords.append('shininess')
        if lamp == 'spot':
            keywords += ['cutoff-angle', 'exponent']
        EFFECT_PROCEDURES[f'make-{lamp}-lit-{model}-image-filter'] = (
            8 if lamp == 'spot' else 4, sorted(keywords))
assert len(EFFECT_EXPORTS) == 14
assert len(COLOR_FILTER_EXPORTS) == 9
assert len(RUNTIME_EXPORTS) == 32
assert len(EFFECT_PROCEDURES) == 90
assert set(EFFECT_EXPORTS + COLOR_FILTER_EXPORTS + RUNTIME_EXPORTS) <= EFFECT_PROCEDURES.keys()
