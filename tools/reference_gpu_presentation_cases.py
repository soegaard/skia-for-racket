"""Independent R4d public shapes for source-check fixtures; not GUI evidence."""

R4D_PROCEDURES = {
    'gpu-presenter?': (2, []),
    'gpu-presenter-backend': (2, []),
    'gpu-presenter-context': (2, []),
    'gpu-presenter-state': (2, []),
    'gpu-presenter-info': (2, []),
    'gpu-presenter-render!': (2, []),
    'gpu-presenter-request-render!': (2, []),
    'gpu-presenter-set-render!': (4, []),
    'gpu-presenter-close!': (2, []),
    'gpu-drain-pending-presenters!': (1, []),
    'gpu-frame?': (2, []),
    'gpu-frame-expired?': (2, []),
    'gpu-frame-canvas': (2, []),
    'gpu-frame-context': (2, []),
    'gpu-frame-info': (2, []),
    'gpu-frame-width': (2, []),
    'gpu-frame-height': (2, []),
    'gpu-frame-logical-width': (2, []),
    'gpu-frame-logical-height': (2, []),
    'gpu-frame-scale-x': (2, []),
    'gpu-frame-scale-y': (2, []),
    'gpu-frame-generation': (2, []),
    'gpu-frame-index': (2, []),
    'skia-canvas?': (2, []),
    'skia-gpu-canvas?': (2, []),
    'make-skia-render-canvas': (2, ['adapter', 'adapter-index', 'backend', 'background',
                                    'min-height', 'min-width', 'on-error', 'paint-callback',
                                    'renderer', 'smoothing', 'sync-interval']),
    'skia-render-canvas?': (2, []),
    'make-gpu-raster-executor': (2, []),
    'call-with-gpu-raster-executor': (4, ['on-unavailable']),
}

R4D_VALUES = {
    'skia-canvas%': 'class',
    'gpu-canvas%': 'class',
    'gpu-window%': 'class',
    'skia-gpu-canvas%': 'class',
    'skia-gpu-window%': 'class',
    'skia-render-canvas<%>': 'interface',
    'skia-render-window%': 'class',
}

R4D_MODULES = {
    'gpu.rkt': [name for name in R4D_PROCEDURES if name.startswith('gpu-')],
    'canvas.rkt': ['skia-canvas%', 'skia-canvas?'],
    'gpu-gui.rkt': ['gpu-canvas%', 'gpu-window%'],
    'gpu-canvas.rkt': ['skia-gpu-canvas%', 'skia-gpu-canvas?', 'skia-gpu-window%'],
    'render-canvas.rkt': ['make-skia-render-canvas', 'skia-render-canvas<%>',
                          'skia-render-canvas?', 'skia-render-window%'],
    'gpu-output.rkt': ['make-gpu-raster-executor', 'call-with-gpu-raster-executor'],
}

R4D_GUI_MODULES = ('skia/canvas', 'skia/gpu-canvas', 'skia/gpu-gui', 'skia/render-canvas')
