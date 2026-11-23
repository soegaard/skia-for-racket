# Explicitly unsafe GPU interoperability

These small public facade modules expose native-object ingress that cannot be
made safe by ordinary Racket argument checks. They are separate from the default
`skia` import and forward to the private backend implementations.

| Module | Contents and caller obligations |
| --- | --- |
| [gpu-metal.rkt](gpu-metal.rkt) | Exports `make-metal-external-texture` and `call-with-gpu-metal-device`. Supplied Objective-C objects must be live and implement the documented protocols. |
| [gpu-d3d12.rkt](gpu-d3d12.rkt) | Exports `make-d3d12-external-texture` and `call-with-gpu-d3d12-device`. Supplied COM pointers must be live objects of the documented interface types. |

A protocol or interface query cannot validate an arbitrary address or resurrect
a freed object. Read the complete ownership, device-affinity, synchronization,
and scope requirements in [Metal interoperability](../docs/GPU-METAL-INTEROP.md)
or [Direct3D interoperability](../docs/GPU-D3D12-INTEROP.md) before using these
entry points. Ordinary applications should begin with the checked
[GPU API](../gpu.rkt) and [interoperability facade](../gpu-interop.rkt).
