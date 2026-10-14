"""Independent R4c call shapes for source-check fixtures; not native evidence."""

R4C_PROCEDURES = {
    'make-egl-gpu-context': (1, ['device-index', 'gl-interface', 'options', 'platform', 'surface']),
    'make-current-egl-gpu-provider': (1, []),
    'make-racket-gl-provider': (2, []),
    'gpu-gl-interface-info': (2, []),
    'gpu-gl-has-extension?': (4, []),
    'gpu-smoke-test': (2, []),
    'call-with-gpu-external-gl': (4, ['wait?']),
    'call-with-gpu-gl-framebuffer': (32, ['color-space', 'origin', 'wait?']),
    'gpu-copy-gl-texture': (16, ['color-space', 'origin', 'premultiplied?', 'wait?']),
    'gpu-external-texture?': (2, []),
    'gpu-external-texture-info': (2, []),
    'gpu-external-texture-close!': (2, []),
    'gpu-import-image': (4, []),
    'call-with-gpu-external-surface': (8, []),
    'call-with-gpu-metal-device': (4, []),
    'make-metal-external-texture': (4, ['color-space', 'premultiplied?',
                                        'producer-command-buffer', 'timeout-ms']),
    'call-with-gpu-d3d12-device': (4, []),
    'make-d3d12-external-texture': (4, ['color-space', 'incoming-state', 'outgoing-state',
                                        'premultiplied?', 'producer-fence', 'producer-value',
                                        'timeout-ms']),
}

R4C_REQUIRED_KEYWORDS = {
    'make-metal-external-texture': ['producer-command-buffer'],
    'make-d3d12-external-texture': ['incoming-state', 'outgoing-state',
                                    'producer-fence', 'producer-value'],
}

R4C_MODULES = {
    'gpu.rkt': ['gpu-gl-has-extension?', 'gpu-gl-interface-info', 'gpu-smoke-test'],
    'gpu-diagnostics.rkt': ['gpu-gl-has-extension?', 'gpu-gl-interface-info'],
    'gpu-egl.rkt': ['make-current-egl-gpu-provider', 'make-egl-gpu-context'],
    'gpu-racket-gl.rkt': ['make-racket-gl-provider'],
    'gpu-gl-interop.rkt': ['call-with-gpu-external-gl', 'call-with-gpu-gl-framebuffer',
                           'gpu-copy-gl-texture'],
    'gpu-interop.rkt': ['call-with-gpu-external-surface', 'gpu-external-texture-close!',
                        'gpu-external-texture-info', 'gpu-external-texture?', 'gpu-import-image'],
    'unsafe/gpu-metal.rkt': ['call-with-gpu-metal-device', 'make-metal-external-texture'],
    'unsafe/gpu-d3d12.rkt': ['call-with-gpu-d3d12-device', 'make-d3d12-external-texture'],
}
