# DXGI presentation ABI checks

These sources verify Windows SDK structures and COM identifiers used by DXGI
presentation, with explicitly limited non-Windows mirrors for authoring.

| File | Contents |
| --- | --- |
| [CMakeLists.txt](CMakeLists.txt) | Builds the real SDK check on Windows or the host mirror elsewhere and registers CTest entries. |
| [check.c](check.c) | Checks swap-chain, resource-barrier, resource-description, copy-footprint, and texture-info layouts, presentation constants, and COM slots. |
| [guid.cpp](guid.cpp) | Checks DXGI/Direct3D interface GUIDs against the SDK. |
| [mirror.c](mirror.c) | Checks local 64-bit C mirrors and explicitly reports that Windows/GPU execution was not performed. |

[check-dxgi-layouts.rkt](../check-dxgi-layouts.rkt) exposes the Racket-side sizes.
The [DXGI validator](../validate-dxgi.py) requires real Windows SDK/runtime
evidence; the host mirror cannot satisfy that gate.
