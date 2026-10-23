"""Independent R4a call shapes for synthetic checker tests, not runtime evidence."""

GPU_CONTEXT_EXPORTS = (
    'gpu-backends gpu-backend? gpu-backend-capabilities '
    'make-gpu-provider gpu-provider? gpu-provider-name gpu-provider-backend '
    'exn:fail:gpu:unavailable? exn:fail:gpu:unavailable-step '
    'gpu-context? make-gpu-context call-with-gpu-context call-with-new-gpu-context gpu-context-backend '
    'gpu-context-generation gpu-context-state gpu-context-info gpu-context-close! '
    'gpu-context-abandon! gpu-context-release-and-abandon! gpu-context-request-shutdown! '
    'gpu-drain-releases! gpu-drain-pending-contexts!').split()

GPU_OPTION_EXPORTS = (
    'gpu-context-options? make-gpu-context-options '
    'gpu-context-options-avoid-stencil-buffers? '
    'gpu-context-options-runtime-program-cache-size '
    'gpu-context-options-glyph-cache-texture-maximum-bytes '
    'gpu-context-options-allow-path-mask-caching? gpu-context-options-manual-mipmapping? '
    'gpu-context-options-buffer-map-threshold gpu-context-options->jsexpr').split()

R4A_PROCEDURES = {
    name: (2, []) for name in [*GPU_CONTEXT_EXPORTS, *GPU_OPTION_EXPORTS]
}
R4A_PROCEDURES.update({
    'gpu-backends': (1, []),
    'make-gpu-provider': (1, ['backend', 'call-as-current', 'current?', 'describe',
                             'get-proc-address', 'key', 'name']),
    'make-gpu-context': (3, ['adapter', 'adapter-index', 'backend', 'gl-interface', 'options']),
    'call-with-gpu-context': (4, []),
    'call-with-new-gpu-context': (4, []),
    'gpu-drain-pending-contexts!': (1, ['abandon?']),
    'make-gpu-context-options': (1, ['allow-path-mask-caching?', 'avoid-stencil-buffers?',
                                   'buffer-map-threshold', 'glyph-cache-texture-maximum-bytes',
                                   'manual-mipmapping?', 'runtime-program-cache-size']),
})
R4A_REQUIRED_KEYWORDS = {
    'make-gpu-provider': ['backend', 'call-as-current', 'current?', 'key', 'name'],
}
R4A_MODULES = {
    'gpu.rkt': [*GPU_CONTEXT_EXPORTS, *GPU_OPTION_EXPORTS],
    'gpu-context-options.rkt': GPU_OPTION_EXPORTS,
}
