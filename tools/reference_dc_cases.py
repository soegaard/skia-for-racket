"""Independent R4e public shapes for source-check fixtures; not native DC evidence."""

R4E_PROCEDURES = {
    'skia-dc?': (2, []),
    'skia-dc-capabilities': (1, []),
    'skia-dc-compatibility': (3, []),
    'exn:fail:skia-dc:unsupported': (32, []),
    'exn:fail:skia-dc:unsupported?': (2, []),
    'exn:fail:skia-dc:unsupported-method': (2, []),
    'exn:fail:skia-dc:unsupported-feature': (2, []),
    'exn:fail:skia-dc:unsupported-stage': (2, []),
    'call-with-output-dc': (16, ['background', 'policy', 'raster-scale', 'smoothing', 'text-mode']),
    'dc-annotate-url!': (64, []),
    'dc-define-destination!': (16, []),
    'dc-link-destination!': (64, []),
    'draw-dc-raster-group': (64, ['label', 'scale']),
    'make-dc-output-page': (8, ['background', 'margins', 'on-report', 'policy', 'smoothing', 'unit']),
    'output-dc-capabilities': (1, []),
    'skia-output-dc?': (2, []),
    'call-with-gpu-frame-dc': (4, ['background', 'color-space', 'color-type', 'sample-count',
                                   'smoothing', 'surface-properties']),
    'call-with-gpu-surface-dc': (4, ['background', 'clear?', 'logical-height', 'logical-width',
                                     'smoothing']),
    'skia-gpu-dc-capabilities': (1, []),
    'skia-gpu-dc?': (2, []),
}

R4E_VALUES = {
    'skia-dc%': 'class',
    'struct:exn:fail:skia-dc:unsupported': 'value',
}

R4E_PARAMETERS = ('current-output-dc-command-limit',)

R4E_MODULES = {
    'dc.rkt': ['skia-dc%', 'skia-dc?', 'skia-dc-capabilities', 'skia-dc-compatibility',
               'exn:fail:skia-dc:unsupported', 'struct:exn:fail:skia-dc:unsupported',
               'exn:fail:skia-dc:unsupported?', 'exn:fail:skia-dc:unsupported-method',
               'exn:fail:skia-dc:unsupported-feature', 'exn:fail:skia-dc:unsupported-stage'],
    'dc-output.rkt': ['call-with-output-dc', 'current-output-dc-command-limit',
                      'dc-annotate-url!', 'dc-define-destination!', 'dc-link-destination!',
                      'draw-dc-raster-group', 'make-dc-output-page',
                      'output-dc-capabilities', 'skia-output-dc?'],
    'gpu-dc.rkt': ['call-with-gpu-frame-dc', 'call-with-gpu-surface-dc',
                   'skia-gpu-dc-capabilities', 'skia-gpu-dc?'],
}
